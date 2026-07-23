import CryptoKit
import Foundation
import XCTest

@testable import SurgeShallow

final class SoftwareUpdateTests: XCTestCase {
    func testAutomaticCheckRunsAtMostOnceEverySixHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertTrue(SoftwareUpdateSchedule.shouldCheck(lastCheck: nil, now: now))
        XCTAssertFalse(
            SoftwareUpdateSchedule.shouldCheck(
                lastCheck: now.addingTimeInterval(-60 * 60),
                now: now
            )
        )
        XCTAssertTrue(
            SoftwareUpdateSchedule.shouldCheck(
                lastCheck: now.addingTimeInterval(-6 * 60 * 60),
                now: now
            )
        )
    }

    func testInstallationResultIsConsumedOnceAfterRelaunch() throws {
        let applicationSupport = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let resultURL = try SoftwareUpdateInstallationResultStore.resultURL(
            applicationSupportURL: applicationSupport
        )
        try Data("restored\ninstall-failed\n".utf8).write(to: resultURL)

        XCTAssertEqual(
            SoftwareUpdateInstallationResultStore.consume(
                applicationSupportURL: applicationSupport
            ),
            .restoredPreviousVersion
        )
        XCTAssertNil(
            SoftwareUpdateInstallationResultStore.consume(
                applicationSupportURL: applicationSupport
            )
        )

        try Data("failed\ninstall-failed\n".utf8).write(to: resultURL)
        XCTAssertEqual(
            SoftwareUpdateInstallationResultStore.consume(
                applicationSupportURL: applicationSupport
            ),
            .installationFailed
        )

        try Data("pending\n2.2.0\n".utf8).write(to: resultURL)
        XCTAssertEqual(
            SoftwareUpdateInstallationResultStore.consume(
                applicationSupportURL: applicationSupport
            ),
            .pendingConfirmation("2.2.0")
        )
        try SoftwareUpdateInstallationResultStore.confirmInstallation(
            applicationSupportURL: applicationSupport
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try SoftwareUpdateInstallationResultStore.confirmationURL(
                    applicationSupportURL: applicationSupport
                ).path
            )
        )
    }

    @MainActor
    func testPreparingToRestartDismissesPresentedReleaseBeforeRestarting() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let stagedApplicationURL = fixtureRoot
            .appending(path: "Staged", directoryHint: .isDirectory)
            .appending(path: "Surge Shallow.app", directoryHint: .isDirectory)
        try makeApplicationFixture(at: stagedApplicationURL, version: "2.2.0")
        try runFixtureTool(
            "/usr/bin/codesign",
            arguments: ["--force", "--deep", "--sign", "-", stagedApplicationURL.path]
        )

        let archiveURL = fixtureRoot.appending(path: "Surge-Shallow-2.2.0-macOS.zip")
        try runFixtureTool(
            "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", stagedApplicationURL.path, archiveURL.path]
        )
        let archiveData = try Data(contentsOf: archiveURL)
        let archiveDigest = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SoftwareUpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let applicationSupportURL = fixtureRoot
            .appending(path: "Application Support", directoryHint: .isDirectory)
        let temporaryDirectoryURL = fixtureRoot
            .appending(path: "Installer Temporary", directoryHint: .isDirectory)
        let updateFileManager = SoftwareUpdateTestFileManager(
            applicationSupportURL: applicationSupportURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
        let installer = SoftwareUpdateInstaller(
            session: session,
            fileManager: updateFileManager,
            helperScript: isolatedInstallationHandoffHelper,
            directInstallationOverride: true
        )
        let defaultsSuiteName = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let controller = SoftwareUpdateController(defaults: defaults, installer: installer)
        let downloadURL = URL(
            string: "https://github.com/funnythingfunnylove/Surge-Shallow/releases/"
                + "download/v2.2.0/Surge-Shallow-2.2.0-macOS.zip"
        )!
        SoftwareUpdateURLProtocol.register(archiveData, for: downloadURL)
        defer { SoftwareUpdateURLProtocol.unregister(downloadURL) }
        let release = SoftwareRelease(
            tagName: "v2.2.0",
            version: try XCTUnwrap(SemanticVersion("2.2.0")),
            title: "Surge Shallow 2.2.0",
            notes: "更新日志",
            pageURL: URL(string: "https://github.com/funnythingfunnylove/Surge-Shallow/releases/tag/v2.2.0")!,
            publishedAt: nil,
            asset: SoftwareUpdateAsset(
                name: archiveURL.lastPathComponent,
                downloadURL: downloadURL,
                sha256: archiveDigest,
                size: Int64(archiveData.count)
            )
        )

        let currentApplicationURL = fixtureRoot
            .appending(path: "Installed", directoryHint: .isDirectory)
            .appending(path: "Surge Shallow.app", directoryHint: .isDirectory)
        try makeApplicationFixture(at: currentApplicationURL, version: "2.1.0")
        let currentExecutableURL = currentApplicationURL
            .appending(path: "Contents/MacOS/SurgeShallow")
        try FileManager.default.createDirectory(
            at: currentExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: URL(filePath: "/usr/bin/caffeinate"),
            to: currentExecutableURL
        )
        guard FileManager.default.isWritableFile(
            atPath: currentApplicationURL.deletingLastPathComponent().path
        ), FileManager.default.isWritableFile(atPath: currentApplicationURL.path) else {
            return XCTFail("更新回归测试必须走临时目录的 direct-install 分支，禁止请求管理员授权。")
        }
        let runningApplication = Process()
        runningApplication.executableURL = currentExecutableURL
        try runningApplication.run()
        defer {
            if runningApplication.isRunning {
                runningApplication.terminate()
                runningApplication.waitUntilExit()
            }
        }

        controller.presentForVerification(release)
        try await controller.install(
            release,
            currentApplicationURL: currentApplicationURL,
            processIdentifier: runningApplication.processIdentifier
        )

        XCTAssertEqual(controller.phase, .restarting)
        XCTAssertNil(
            controller.presentedRelease,
            "准备重启时必须先关闭更新日志，再进入 restarting 状态"
        )

        runningApplication.terminate()
        runningApplication.waitUntilExit()
        try await waitForInstallerResult(
            "test-helper-complete",
            applicationSupportURL: applicationSupportURL
        )
        try await waitForNoInstallerProcess(containing: fixtureRoot.path)
    }

    func testSemanticVersionOrdersGitHubTagsAndTreatsMissingPatchAsZero() throws {
        let current = try XCTUnwrap(SemanticVersion("2.1.0"))
        let newer = try XCTUnwrap(SemanticVersion("v2.2.0"))
        let equivalent = try XCTUnwrap(SemanticVersion("2.1"))
        let prerelease = try XCTUnwrap(SemanticVersion("2.2.0-beta.1"))

        XCTAssertGreaterThan(newer, current)
        XCTAssertEqual(equivalent, current)
        XCTAssertLessThan(prerelease, newer)
        XCTAssertNil(SemanticVersion("latest"))
    }

    func testGitHubReleaseDecoderSelectsVerifiedMacOSZipAndKeepsReleaseNotes() throws {
        let payload = try githubReleasePayload(
            notes: "## 更新内容\n\n- 一键更新",
            sha256: String(repeating: "b", count: 64),
            includesUnrelatedAsset: true
        )

        let release = try GitHubReleaseDecoder().decode(payload)

        XCTAssertEqual(release.version, SemanticVersion("2.2.0"))
        XCTAssertEqual(release.title, "Surge Shallow 2.2.0")
        XCTAssertEqual(release.notes, "## 更新内容\n\n- 一键更新")
        XCTAssertEqual(release.asset.name, "Surge-Shallow-2.2.0-macOS.zip")
        XCTAssertEqual(
            release.asset.sha256,
            "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        )
        XCTAssertEqual(release.asset.size, 25_000_000)
    }

    func testGitHubCheckerReportsNewerReleaseAndUsesOfficialLatestEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SoftwareUpdateURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let endpoint = GitHubSoftwareUpdateService.latestReleaseURL
        SoftwareUpdateURLProtocol.register(try githubReleasePayload(
            sha256: String(repeating: "c", count: 64)
        ), for: endpoint)
        defer { SoftwareUpdateURLProtocol.unregister(endpoint) }

        let result = try await GitHubSoftwareUpdateService(session: session).check(
            installedVersion: SemanticVersion("2.1.0")!
        )

        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected a newer release")
        }
        XCTAssertEqual(release.version, SemanticVersion("2.2.0"))
        XCTAssertEqual(
            SoftwareUpdateURLProtocol.lastRequest(for: endpoint)?.url?.absoluteString,
            "https://api.github.com/repos/funnythingfunnylove/Surge-Shallow/releases/latest"
        )
        XCTAssertEqual(
            SoftwareUpdateURLProtocol.lastRequest(for: endpoint)?
                .value(forHTTPHeaderField: "Accept"),
            "application/vnd.github+json"
        )
    }

    func testPackageVerifierRejectsArchiveWhenGitHubDigestDoesNotMatch() throws {
        let archiveURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("zip")
        try Data("hello".utf8).write(to: archiveURL)
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        XCTAssertNoThrow(
            try SoftwareUpdatePackageVerifier.verifySHA256(
                of: archiveURL,
                expected: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
        )
        XCTAssertThrowsError(
            try SoftwareUpdatePackageVerifier.verifySHA256(
                of: archiveURL,
                expected: String(repeating: "0", count: 64)
            )
        ) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .checksumMismatch)
        }
    }

    func testPackageVerifierRejectsExtractedAppWithUnexpectedVersion() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.surgeprofilerelay.app",
            "CFBundleShortVersionString": "2.2.0",
            "CFBundleVersion": "17"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appending(path: "Info.plist"))
        defer { try? FileManager.default.removeItem(at: appURL) }

        XCTAssertNoThrow(
            try SoftwareUpdatePackageVerifier.validateApplication(
                at: appURL,
                expectedVersion: SemanticVersion("2.2.0")!,
                expectedBundleIdentifier: "com.surgeprofilerelay.app"
            )
        )
        XCTAssertThrowsError(
            try SoftwareUpdatePackageVerifier.validateApplication(
                at: appURL,
                expectedVersion: SemanticVersion("2.3.0")!,
                expectedBundleIdentifier: "com.surgeprofilerelay.app"
            )
        ) { error in
            XCTAssertEqual(error as? SoftwareUpdateError, .unexpectedApplicationVersion)
        }
    }

    func testLiveGitHubReleaseDownloadsVerifiesAndPreparesSignedApplication() async throws {
        guard ProcessInfo.processInfo.environment["SURGE_SHALLOW_RUN_LIVE_UPDATE_TESTS"] == "1" else {
            throw XCTSkip("Set SURGE_SHALLOW_RUN_LIVE_UPDATE_TESTS=1 to verify the published release.")
        }

        let result = try await GitHubSoftwareUpdateService().check(
            installedVersion: SemanticVersion("2.0.0")!
        )
        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected the published release to be newer than 2.0.0")
        }
        let prepared = try await SoftwareUpdateInstaller().downloadAndPrepare(release)
        defer { try? FileManager.default.removeItem(at: prepared.workingDirectory) }

        XCTAssertGreaterThan(release.version, SemanticVersion("2.0.0")!)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: prepared.applicationURL.appending(path: "Contents/MacOS/SurgeShallow").path
            )
        )
    }

    private func githubReleasePayload(
        version: String = "2.2.0",
        notes: String = "更新日志",
        sha256: String,
        includesUnrelatedAsset: Bool = false
    ) throws -> Data {
        var assets: [[String: Any]] = []
        if includesUnrelatedAsset {
            assets.append([
                "name": "Source code.zip",
                "browser_download_url": "https://github.com/example/source.zip",
                "content_type": "application/zip",
                "state": "uploaded",
                "size": 100,
                "digest": "sha256:\(String(repeating: "a", count: 64))"
            ])
        }
        assets.append([
            "name": "Surge-Shallow-\(version)-macOS.zip",
            "browser_download_url": "https://github.com/funnythingfunnylove/Surge-Shallow/releases/download/v\(version)/Surge-Shallow-\(version)-macOS.zip",
            "content_type": "application/zip",
            "state": "uploaded",
            "size": 25_000_000,
            "digest": "sha256:\(sha256)"
        ])

        return try JSONSerialization.data(withJSONObject: [
            "tag_name": "v\(version)",
            "name": "Surge Shallow \(version)",
            "body": notes,
            "html_url": "https://github.com/funnythingfunnylove/Surge-Shallow/releases/tag/v\(version)",
            "published_at": "2026-07-24T01:02:03Z",
            "draft": false,
            "prerelease": false,
            "assets": assets
        ])
    }
}

private final class SoftwareUpdateTestFileManager: FileManager, @unchecked Sendable {
    private let applicationSupportURL: URL
    private let isolatedTemporaryDirectoryURL: URL

    init(applicationSupportURL: URL, temporaryDirectoryURL: URL) {
        self.applicationSupportURL = applicationSupportURL
        isolatedTemporaryDirectoryURL = temporaryDirectoryURL
        super.init()
    }

    override var temporaryDirectory: URL { isolatedTemporaryDirectoryURL }

    override func url(
        for directory: FileManager.SearchPathDirectory,
        in domain: FileManager.SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .applicationSupportDirectory, domain == .userDomainMask {
            if shouldCreate {
                try createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
            }
            return applicationSupportURL
        }
        return try super.url(
            for: directory,
            in: domain,
            appropriateFor: url,
            create: shouldCreate
        )
    }
}

private let isolatedInstallationHandoffHelper = #"""
#!/bin/sh
set -eu

app_pid="$3"
ready_file="$4"
result_file="$5"
working_directory=$(/usr/bin/dirname "$ready_file")

/usr/bin/touch "$ready_file"
while /bin/kill -0 "$app_pid" 2>/dev/null; do
    /bin/sleep 0.02
done
/bin/rm -rf "$working_directory"
/usr/bin/printf 'test-helper-complete\nisolated\n' > "$result_file"
"""#

private func makeApplicationFixture(at applicationURL: URL, version: String) throws {
    let contentsURL = applicationURL.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "com.surgeprofilerelay.app",
        "CFBundleName": "Surge Shallow",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": "1"
    ]
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .xml,
        options: 0
    )
    try plistData.write(to: contentsURL.appending(path: "Info.plist"))
}

private func runFixtureTool(_ executable: String, arguments: [String]) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let details = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        throw NSError(
            domain: "SoftwareUpdateFixture",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: details]
        )
    }
}

private func waitForInstallerResult(
    _ expectedStatus: String,
    applicationSupportURL: URL
) async throws {
    let resultURL = try SoftwareUpdateInstallationResultStore.resultURL(
        applicationSupportURL: applicationSupportURL
    )
    for _ in 0..<100 {
        if let content = try? String(contentsOf: resultURL, encoding: .utf8),
           content.hasPrefix(expectedStatus + "\n") {
            return
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("安装 helper 未写入预期结果：\(expectedStatus)")
}

private func waitForNoInstallerProcess(containing fixturePath: String) async throws {
    for _ in 0..<100 {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let commands = String(data: outputData, encoding: .utf8) ?? ""
        if !commands.contains(fixturePath) { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    XCTFail("安装 helper 在测试完成后仍未退出。")
}

private final class SoftwareUpdateURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var payloads: [URL: Data] = [:]
    nonisolated(unsafe) private static var requests: [URL: URLRequest] = [:]

    static func register(_ payload: Data, for url: URL) {
        lock.lock()
        payloads[url] = payload
        requests[url] = nil
        lock.unlock()
    }

    static func unregister(_ url: URL) {
        lock.lock()
        payloads[url] = nil
        requests[url] = nil
        lock.unlock()
    }

    static func lastRequest(for url: URL) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[url]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.requests[url] = request
        let payload = Self.payloads[url]
        Self.lock.unlock()
        guard let payload else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
