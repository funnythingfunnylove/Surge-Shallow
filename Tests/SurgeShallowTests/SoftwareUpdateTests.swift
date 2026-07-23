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
        SoftwareUpdateURLProtocol.payload = try githubReleasePayload(
            sha256: String(repeating: "c", count: 64)
        )

        let result = try await GitHubSoftwareUpdateService(session: session).check(
            installedVersion: SemanticVersion("2.1.0")!
        )

        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected a newer release")
        }
        XCTAssertEqual(release.version, SemanticVersion("2.2.0"))
        XCTAssertEqual(
            SoftwareUpdateURLProtocol.lastRequest?.url?.absoluteString,
            "https://api.github.com/repos/funnythingfunnylove/Surge-Shallow/releases/latest"
        )
        XCTAssertEqual(
            SoftwareUpdateURLProtocol.lastRequest?.value(forHTTPHeaderField: "Accept"),
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

private final class SoftwareUpdateURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
