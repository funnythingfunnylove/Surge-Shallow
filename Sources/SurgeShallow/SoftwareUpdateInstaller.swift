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
    private let helperScript: String
    private let directInstallationOverride: Bool?
    private let bundleIdentifier = "com.surgeprofilerelay.app"

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        helperScript: String = SoftwareUpdateInstaller.installationHelper,
        directInstallationOverride: Bool? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.helperScript = helperScript
        self.directInstallationOverride = directInstallationOverride
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
        try Data(helperScript.utf8).write(to: helperURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        let readyURL = prepared.workingDirectory.appending(path: "installer-ready")
        let resultURL = try SoftwareUpdateInstallationResultStore.resultURL(fileManager: fileManager)
        let confirmationURL = try SoftwareUpdateInstallationResultStore.confirmationURL(
            fileManager: fileManager
        )
        try? fileManager.removeItem(at: confirmationURL)

        let parentURL = targetURL.deletingLastPathComponent()
        let canInstallDirectly = directInstallationOverride ?? (
            fileManager.isWritableFile(atPath: parentURL.path)
                && fileManager.isWritableFile(atPath: targetURL.path)
        )
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

    static let installationHelper = #"""
    #!/bin/sh
    set -u

    staged_app="$1"
    target_app="$2"
    app_pid="$3"
    ready_file="$4"
    result_file="$5"
    target_version="$6"
    confirmation_file="$7"
    enumeration_error_file="${ready_file}.lsof-error"
    backup_app="${target_app}.update-backup"
    target_executable_command="${target_app}/Contents/MacOS/SurgeShallow"
    backup_executable_command="${backup_app}/Contents/MacOS/SurgeShallow"
    target_executable=$(/bin/realpath "$target_executable_command" 2>/dev/null || \
        /usr/bin/printf '%s\n' "$target_executable_command")

    process_is_running() {
        running_state=$(/bin/ps -p "$1" -o state= 2>/dev/null)
        case "$running_state" in
            ""|Z*) return 1 ;;
            *) return 0 ;;
        esac
    }

    process_executable_path() {
        /usr/sbin/lsof -a -p "$1" -d txt -Fn 2>/dev/null | \
            /usr/bin/awk 'substr($0, 1, 1) == "n" { print substr($0, 2); exit }'
    }

    process_matches_target() {
        running_executable=$(process_executable_path "$1")
        [ "$running_executable" = "$target_executable" ]
    }

    command_matches_target() {
        case "$1" in
            "$target_executable_command"|"$target_executable_command "*) return 0 ;;
        esac
        case "$1" in
            "$target_executable"|"$target_executable "*) return 0 ;;
        esac
        return 1
    }

    verify_process_enumerator() {
        : > "$enumeration_error_file" || return 1
        enumeration_probe=$(
            /usr/sbin/lsof -a -p "$$" -d txt -Fn 2>"$enumeration_error_file"
        )
        enumeration_status=$?
        [ "$enumeration_status" -eq 0 ] || return 1
        [ ! -s "$enumeration_error_file" ] || return 1
        /usr/bin/printf '%s\n' "$enumeration_probe" | \
            /usr/bin/awk -v expected_pid="p$$" '
                $0 == expected_pid { found = 1 }
                END { exit(found ? 0 : 1) }
            '
    }

    find_target_pids() {
        executable_to_scan="$1"
        [ -e "$executable_to_scan" ] || return 2
        : > "$enumeration_error_file" || return 2
        enumeration_output=$(
            /usr/sbin/lsof -a -d txt -Fn "$executable_to_scan" \
                2>"$enumeration_error_file"
        )
        enumeration_status=$?
        [ ! -s "$enumeration_error_file" ] || return 2
        case "$enumeration_status" in
            0)
                /usr/bin/printf '%s\n' "$enumeration_output" | \
                    /usr/bin/awk 'substr($0, 1, 1) == "p" { print substr($0, 2) }' | \
                    /usr/bin/sort -u
                ;;
            1)
                return 0
                ;;
            *)
                return 2
                ;;
        esac
    }

    pid_was_running_before_launch() {
        candidate_pid="$1"
        before_launch_pids="$2"
        for before_launch_pid in $before_launch_pids; do
            if [ "$candidate_pid" = "$before_launch_pid" ]; then
                return 0
            fi
        done
        return 1
    }

    find_new_target_pid() {
        before_launch_pids="$1"
        /bin/ps -axo pid=,command= | while read -r running_pid running_command; do
            if command_matches_target "$running_command" && \
               ! pid_was_running_before_launch "$running_pid" "$before_launch_pids"; then
                /usr/bin/printf '%s\n' "$running_pid"
            fi
        done | /usr/bin/tail -n 1
    }

    write_result() {
        /usr/bin/printf '%s\n%s\n' "$1" "$2" > "$result_file"
    }

    cleanup_working_directory() {
        /bin/rm -rf "$(/usr/bin/dirname "$ready_file")"
    }

    restore_backup_and_abort() {
        failure_reason="$1"
        if [ -e "$target_app" ] || [ ! -e "$backup_app" ] || \
           ! /bin/mv "$backup_app" "$target_app"; then
            write_result failed preinstall-rollback-failed
            cleanup_working_directory
            exit 12
        fi
        write_result failed "$failure_reason"
        cleanup_working_directory
        exit 11
    }

    abort_if_process_identity_changed() {
        if process_is_running "$app_pid" && ! process_matches_target "$app_pid"; then
            write_result failed shutdown-process-mismatch
            cleanup_working_directory
            exit 11
        fi
    }

    /usr/bin/touch "$ready_file" || exit 10
    if ! verify_process_enumerator; then
        write_result failed process-enumeration-failed
        cleanup_working_directory
        exit 11
    fi

    # Give the application five seconds to quit cleanly after its update
    # sheet is dismissed. If AppKit still refuses termination, escalate only
    # against the exact PID whose executable path still matches this app.
    abort_if_process_identity_changed
    attempts=0
    while process_matches_target "$app_pid"; do
        /bin/sleep 0.1
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 50 ]; then
            break
        fi
    done
    abort_if_process_identity_changed
    if process_matches_target "$app_pid"; then
        /bin/kill "$app_pid" 2>/dev/null || true
        attempts=0
        while process_matches_target "$app_pid"; do
            /bin/sleep 0.1
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 20 ]; then
                break
            fi
        done
    fi
    abort_if_process_identity_changed
    if process_matches_target "$app_pid"; then
        /bin/kill -9 "$app_pid" 2>/dev/null || true
        attempts=0
        while process_matches_target "$app_pid"; do
            /bin/sleep 0.1
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 20 ]; then
                write_result failed shutdown-termination-failed
                cleanup_working_directory
                exit 11
            fi
        done
    fi
    abort_if_process_identity_changed

    remaining_target_pids=$(find_target_pids "$target_executable")
    enumeration_status=$?
    if [ "$enumeration_status" -ne 0 ]; then
        write_result failed process-enumeration-failed
        cleanup_working_directory
        exit 11
    fi
    if [ -n "$remaining_target_pids" ]; then
        write_result failed multiple-running-instances
        cleanup_working_directory
        exit 11
    fi

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
    backup_executable=$(/bin/realpath "$backup_executable_command" 2>/dev/null || \
        /usr/bin/printf '%s\n' "$backup_executable_command")
    stable_scans=0
    while [ "$stable_scans" -lt 10 ]; do
        /bin/sleep 0.1
        remaining_target_pids=$(find_target_pids "$backup_executable")
        enumeration_status=$?
        if [ "$enumeration_status" -ne 0 ]; then
            restore_backup_and_abort process-enumeration-failed
        fi
        if [ -n "$remaining_target_pids" ]; then
            restore_backup_and_abort multiple-running-instances
        fi
        stable_scans=$((stable_scans + 1))
    done

    # The target path is intentionally absent between the backup move and
    # ditto. The stable backup-vnode scans above therefore establish an empty
    # pre-launch target PID set without conflating a missing path with an lsof
    # failure.
    preexisting_target_pids=""
    remaining_target_pids=$(find_target_pids "$backup_executable")
    enumeration_status=$?
    if [ "$enumeration_status" -ne 0 ]; then
        restore_backup_and_abort process-enumeration-failed
    fi
    if [ -n "$remaining_target_pids" ]; then
        restore_backup_and_abort multiple-running-instances
    fi
    if /usr/bin/ditto "$staged_app" "$target_app" && \
       /usr/bin/codesign --verify --deep --strict "$target_app" && \
       write_result pending "$target_version" && \
       /usr/bin/open -n "$target_app"; then
        new_app_pid=""
        attempts=0
        while [ -z "$new_app_pid" ]; do
            /bin/sleep 0.1
            new_app_pid=$(find_new_target_pid "$preexisting_target_pids")
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
