import Foundation

struct PreparedApplicationUpdate: Sendable {
    let release: SoftwareRelease
    let applicationURL: URL
    let workingDirectory: URL
}

enum SoftwareUpdateInstallationResult: Equatable {
    case pendingConfirmation(String)
    case restoredPreviousVersion
    case installationFailed
}

enum SoftwareUpdateInstallationResultStore {
    static func resultURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> URL {
        let applicationSupport: URL
        if let applicationSupportURL {
            applicationSupport = applicationSupportURL
        } else {
            applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let directory = applicationSupport
            .appending(path: "Surge Shallow", directoryHint: .isDirectory)
            .appending(path: "Software Update", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "last-result.txt")
    }

    static func consume(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> SoftwareUpdateInstallationResult? {
        guard let url = try? resultURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        ),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        try? fileManager.removeItem(at: url)
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        guard let status = lines.first else { return nil }
        if status == "pending", lines.count >= 2 {
            return .pendingConfirmation(lines[1])
        }
        if status == "restored" {
            return .restoredPreviousVersion
        }
        if status == "failed" {
            return .installationFailed
        }
        return nil
    }

    static func confirmationURL(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> URL {
        try resultURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        .deletingLastPathComponent()
        .appending(path: "installation-confirmed")
    }

    static func confirmInstallation(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws {
        let url = try confirmationURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        try Data("confirmed\n".utf8).write(to: url, options: .atomic)
    }
}

actor SoftwareUpdateInstaller {
    typealias PhaseHandler = @Sendable (SoftwareUpdatePhase) async -> Void

    private let session: URLSession
    private let fileManager: FileManager
    private let bundleIdentifier = "com.surgeprofilerelay.app"

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func downloadAndPrepare(
        _ release: SoftwareRelease,
        phaseHandler: PhaseHandler? = nil
    ) async throws -> PreparedApplicationUpdate {
        let workingDirectory = fileManager.temporaryDirectory
            .appending(path: "SurgeShallowUpdates", directoryHint: .isDirectory)
            .appending(path: "\(release.version)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        var preservesWorkingDirectory = false
        defer {
            if !preservesWorkingDirectory {
                try? fileManager.removeItem(at: workingDirectory)
            }
        }

        var request = URLRequest(
            url: release.asset.downloadURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 180
        )
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Surge-Shallow-Updater/\(release.version)", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SoftwareUpdateError.invalidReleaseResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SoftwareUpdateError.downloadFailed(httpResponse.statusCode)
        }

        let archiveURL = workingDirectory.appending(path: release.asset.name)
        try fileManager.copyItem(at: temporaryURL, to: archiveURL)
        let attributes = try fileManager.attributesOfItem(atPath: archiveURL.path)
        let downloadedSize = (attributes[.size] as? NSNumber)?.int64Value
        guard downloadedSize == release.asset.size else {
            throw SoftwareUpdateError.downloadSizeMismatch
        }

        await phaseHandler?(.verifying)
        try SoftwareUpdatePackageVerifier.verifySHA256(
            of: archiveURL,
            expected: release.asset.sha256
        )

        let extractionDirectory = workingDirectory.appending(path: "Extracted", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        do {
            try await runTool(
                executable: URL(filePath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
            )
        } catch {
            throw SoftwareUpdateError.archiveExtractionFailed
        }

        let applicationURL = extractionDirectory.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        try SoftwareUpdatePackageVerifier.validateApplication(
            at: applicationURL,
            expectedVersion: release.version,
            expectedBundleIdentifier: bundleIdentifier
        )
        do {
            try await runTool(
                executable: URL(filePath: "/usr/bin/codesign"),
                arguments: ["--verify", "--deep", "--strict", applicationURL.path]
            )
        } catch {
            throw SoftwareUpdateError.invalidCodeSignature
        }

        let prepared = PreparedApplicationUpdate(
            release: release,
            applicationURL: applicationURL,
            workingDirectory: workingDirectory
        )
        preservesWorkingDirectory = true
        return prepared
    }

    func scheduleInstallation(
        _ prepared: PreparedApplicationUpdate,
        currentApplicationURL: URL,
        processIdentifier: Int32
    ) async throws {
        var handedOffToHelper = false
        defer {
            if !handedOffToHelper {
                try? fileManager.removeItem(at: prepared.workingDirectory)
            }
        }

        let targetURL = currentApplicationURL.standardizedFileURL.resolvingSymlinksInPath()
        guard targetURL.pathExtension.lowercased() == "app",
              !targetURL.path.contains("/AppTranslocation/"),
              !targetURL.path.hasPrefix("/Volumes/") else {
            throw SoftwareUpdateError.applicationNotInstalled
        }

        try SoftwareUpdatePackageVerifier.validateApplication(
            at: prepared.applicationURL,
            expectedVersion: prepared.release.version,
            expectedBundleIdentifier: bundleIdentifier
        )

        let helperURL = prepared.workingDirectory.appending(path: "install-update.sh")
        try Data(Self.installationHelper.utf8).write(to: helperURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        let readyURL = prepared.workingDirectory.appending(path: "installer-ready")
        let resultURL = try SoftwareUpdateInstallationResultStore.resultURL(fileManager: fileManager)
        let confirmationURL = try SoftwareUpdateInstallationResultStore.confirmationURL(
            fileManager: fileManager
        )
        try? fileManager.removeItem(at: confirmationURL)

        let parentURL = targetURL.deletingLastPathComponent()
        let canInstallDirectly = fileManager.isWritableFile(atPath: parentURL.path)
            && fileManager.isWritableFile(atPath: targetURL.path)
        let process = Process()
        if canInstallDirectly {
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = Self.helperArguments(
                helperURL: helperURL,
                prepared: prepared,
                targetURL: targetURL,
                processIdentifier: processIdentifier,
                readyURL: readyURL,
                resultURL: resultURL,
                confirmationURL: confirmationURL
            )
        } else {
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", Self.authorizationScript]
                + Self.helperArguments(
                    helperURL: helperURL,
                    prepared: prepared,
                    targetURL: targetURL,
                    processIdentifier: processIdentifier,
                    readyURL: readyURL,
                    resultURL: resultURL,
                    confirmationURL: confirmationURL
                )
        }
        try process.run()

        for _ in 0..<600 {
            if fileManager.fileExists(atPath: readyURL.path) {
                handedOffToHelper = true
                return
            }
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning { process.terminate() }
        throw SoftwareUpdateError.installationCouldNotStart
    }

    private static func helperArguments(
        helperURL: URL,
        prepared: PreparedApplicationUpdate,
        targetURL: URL,
        processIdentifier: Int32,
        readyURL: URL,
        resultURL: URL,
        confirmationURL: URL
    ) -> [String] {
        [
            helperURL.path,
            prepared.applicationURL.path,
            targetURL.path,
            String(processIdentifier),
            readyURL.path,
            resultURL.path,
            prepared.release.version.description,
            confirmationURL.path
        ]
    }

    private func runTool(executable: URL, arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw SoftwareUpdateError.archiveExtractionFailed
            }
        }.value
    }

    private static let authorizationScript = #"""
    on run argv
        if (count of argv) is not 8 then error "Invalid updater arguments"
        set commandText to "/bin/sh"
        repeat with argumentValue in argv
            set commandText to commandText & " " & quoted form of argumentValue
        end repeat
        do shell script commandText with administrator privileges
    end run
    """#

    private static let installationHelper = #"""
    #!/bin/sh
    set -u

    staged_app="$1"
    target_app="$2"
    app_pid="$3"
    ready_file="$4"
    result_file="$5"
    target_version="$6"
    confirmation_file="$7"
    backup_app="${target_app}.update-backup"
    target_executable="${target_app}/Contents/MacOS/SurgeShallow"

    process_matches_target() {
        running_command=$(/bin/ps -p "$1" -o command= 2>/dev/null)
        [ "$running_command" = "$target_executable" ]
    }

    find_target_pid() {
        /bin/ps -axo pid=,command= | while read -r running_pid running_command; do
            if [ "$running_command" = "$target_executable" ]; then
                /usr/bin/printf '%s\n' "$running_pid"
                break
            fi
        done
    }

    write_result() {
        /usr/bin/printf '%s\n%s\n' "$1" "$2" > "$result_file"
    }

    cleanup_working_directory() {
        /bin/rm -rf "$(/usr/bin/dirname "$ready_file")"
    }

    /usr/bin/touch "$ready_file" || exit 10

    attempts=0
    while process_matches_target "$app_pid"; do
        /bin/sleep 0.1
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 600 ]; then
            write_result failed shutdown-timeout
            cleanup_working_directory
            exit 11
        fi
    done

    /bin/rm -rf "$backup_app"
    if [ -e "$target_app" ]; then
        if ! /bin/mv "$target_app" "$backup_app"; then
            write_result restored move-failed
            /usr/bin/open -n "$target_app"
            cleanup_working_directory
            exit 12
        fi
    fi

    /bin/rm -f "$confirmation_file"
    if /usr/bin/ditto "$staged_app" "$target_app" && \
       /usr/bin/codesign --verify --deep --strict "$target_app" && \
       write_result pending "$target_version" && \
       /usr/bin/open -n "$target_app"; then
        new_app_pid=""
        attempts=0
        while [ -z "$new_app_pid" ]; do
            /bin/sleep 0.1
            new_app_pid=$(find_target_pid)
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 100 ]; then
                break
            fi
        done

        attempts=0
        while [ -n "$new_app_pid" ] && process_matches_target "$new_app_pid" && \
              [ ! -f "$confirmation_file" ]; do
            /bin/sleep 0.1
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 600 ]; then
                break
            fi
        done
        if [ -f "$confirmation_file" ] && process_matches_target "$new_app_pid"; then
            /bin/rm -f "$confirmation_file"
            /bin/rm -rf "$backup_app"
            cleanup_working_directory
            exit 0
        fi
    fi

    write_result failed install-failed
    if [ -n "${new_app_pid:-}" ] && process_matches_target "$new_app_pid"; then
        /bin/kill "$new_app_pid" 2>/dev/null || true
        attempts=0
        while process_matches_target "$new_app_pid"; do
            /bin/sleep 0.1
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 50 ]; then
                /bin/kill -9 "$new_app_pid" 2>/dev/null || true
                break
            fi
        done
        attempts=0
        while process_matches_target "$new_app_pid"; do
            /bin/sleep 0.1
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 20 ]; then
                write_result failed termination-failed
                cleanup_working_directory
                exit 14
            fi
        done
    fi
    /bin/rm -rf "$target_app"
    if [ -e "$backup_app" ]; then
        if /bin/mv "$backup_app" "$target_app"; then
            write_result restored install-failed
            /usr/bin/open -n "$target_app"
        fi
    fi
    cleanup_working_directory
    exit 13
    """#
}
