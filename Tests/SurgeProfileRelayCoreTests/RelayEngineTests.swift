import Foundation
import XCTest
@testable import SurgeProfileRelayCore

final class RelayEngineTests: XCTestCase {
    func testEngineFetchesValidatesAndPublishesBothProfiles() async throws {
        let sourceID = UUID()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fetcher = MockFetcher(mode: .content("DOMAIN,example.com"))
        let engine = RelayEngine(fetcher: fetcher)
        let document = makeDocument(sourceID: sourceID, directory: directory)

        let result = await engine.refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        XCTAssertEqual(result.generatedProfiles.count, 2)
        XCTAssertNotNil(result.generatedSharedProfile)
        XCTAssertTrue(result.generatedSharedProfile.map {
            FileManager.default.fileExists(atPath: $0.outputURL.path)
        } ?? false)
        XCTAssertEqual(result.totalRuleCount, 2)
        XCTAssertTrue(result.generatedProfiles.allSatisfy {
            FileManager.default.fileExists(atPath: $0.outputURL.path)
        })
        XCTAssertTrue(result.generatedProfiles.allSatisfy {
            $0.content.contains("#!include \(document.sharedProfile.outputFileName)")
        })
        XCTAssertEqual(result.document.sources[0].state, .updated)
        XCTAssertEqual(result.document.sources[0].lastRuleCount, 1)
        try? testPersistence(outputDirectory: directory).removeCache(for: sourceID)
    }

    func testEngineStopsPublishingWhenFirstFetchFails() async {
        let sourceID = UUID()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let engine = RelayEngine(fetcher: MockFetcher(mode: .failure))
        let document = makeDocument(sourceID: sourceID, directory: directory)
        let result = await engine.refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.generatedProfiles.isEmpty)
        XCTAssertEqual(result.document.sources[0].state, .failed)
        XCTAssertTrue(result.title.contains("保留最后成功版本"))
    }

    func testEngineKeepsRulesPerPlatformWhenMergedRulesDiffer() async {
        let sourceID = UUID()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = RelayEngine(fetcher: MockFetcher(mode: .content("DOMAIN,mac-only.example")))
        var document = makeDocument(sourceID: sourceID, directory: directory)
        document.sources[0].platforms = [.macOS]

        let result = await engine.refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        let sharedLines = result.generatedSharedProfile?.content.components(separatedBy: "\n") ?? []
        XCTAssertFalse(sharedLines.contains("[Rule]"))
        let macOS = result.generatedProfiles.first { $0.platform == .macOS }
        let iOS = result.generatedProfiles.first { $0.platform == .iOS }
        XCTAssertTrue(macOS?.content.contains("DOMAIN,mac-only.example,PROXY") == true)
        XCTAssertFalse(iOS?.content.contains("mac-only.example") ?? true)
        XCTAssertTrue(macOS?.content.contains("[Rule]\n\(ProfileAssembler.ownershipMarker)") == true)
        XCTAssertTrue(iOS?.content.contains("[Rule]\n\(ProfileAssembler.ownershipMarker)") == true)
    }

    func testEngineUsesLastGoodCacheAfterUpstreamFailure() async throws {
        let sourceID = UUID()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = testPersistence(outputDirectory: directory)
        try persistence.saveCachedContent("DOMAIN,cached.example", for: sourceID)

        let engine = RelayEngine(fetcher: MockFetcher(mode: .failure))
        let document = makeDocument(sourceID: sourceID, directory: directory)
        let result = await engine.refresh(
            document: document,
            persistence: persistence,
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        XCTAssertEqual(result.outcome, .warning)
        XCTAssertEqual(result.document.sources[0].state, .staleCache)
        XCTAssertTrue(result.generatedSharedProfile?.content.contains("DOMAIN,cached.example,PROXY") == true)
        try? persistence.removeCache(for: sourceID)
    }

    func testPublisherRefusesToOverwriteUnownedFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = TargetProfile.defaults(for: .macOS)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appending(path: target.outputFileName)
        try Data("user content".utf8).write(to: existing)
        let managedContent = "[Rule]\n\(ProfileAssembler.ownershipMarker)\nFINAL,DIRECT"

        XCTAssertThrowsError(
            try ProfilePublisher().publish(content: managedContent, target: target, directory: directory)
        )
    }

    func testPublisherRefusesUnmarkedNewContent() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try ProfilePublisher().publish(
                content: "[Rule]\nFINAL,DIRECT",
                target: TargetProfile.defaults(for: .macOS),
                directory: directory
            )
        )
    }

    func testEngineRepairsMissingCacheAfterNotModifiedResponse() async {
        let sourceID = UUID()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = NotModifiedThenContentFetcher()
        let engine = RelayEngine(fetcher: fetcher)
        var document = makeDocument(sourceID: sourceID, directory: directory)
        document.sources[0].etag = "stale-etag"

        let result = await engine.refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        let callCount = await fetcher.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertTrue(result.generatedSharedProfile?.content.contains("DOMAIN,repaired.example,PROXY") == true)
        try? testPersistence(outputDirectory: directory).removeCache(for: sourceID)
    }

    private func makeDocument(sourceID: UUID, directory: URL) -> RelayDocument {
        let source = RuleSource(
            id: sourceID,
            name: "Test",
            url: "https://example.com/rules",
            policy: "PROXY"
        )
        let suffix = UUID().uuidString
        var targets = RelayPlatform.allCases.map(TargetProfile.defaults)
        for index in targets.indices {
            targets[index].outputFileName = "\(suffix)-\(targets[index].platform.rawValue).conf"
        }
        var settings = RelaySettings(outputDirectory: directory.path)
        settings.validateWithSurgeCLI = false
        return RelayDocument(sources: [source], targets: targets, settings: settings)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SurgeProfileRelayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func testPersistence(outputDirectory: URL) -> RelayPersistence {
        RelayPersistence(
            outputDirectory: outputDirectory,
            applicationSupportDirectory: outputDirectory.appending(
                path: "Application Support",
                directoryHint: .isDirectory
            )
        )
    }
}

private struct MockFetcher: RuleSourceFetching {
    enum Mode: Sendable {
        case content(String)
        case notModified
        case failure
    }

    let mode: Mode

    func fetch(
        source: RuleSource,
        timeoutSeconds: Int,
        maximumSizeMB: Int
    ) async throws -> RuleSourceFetchResult {
        switch mode {
        case .content(let content):
            return .modified(
                content: content,
                etag: "etag-1",
                lastModified: "Tue, 21 Jul 2026 00:00:00 GMT",
                contentHash: "hash-1",
                checkedAt: Date(timeIntervalSince1970: 100)
            )
        case .notModified:
            return .notModified(checkedAt: Date(timeIntervalSince1970: 100))
        case .failure:
            throw MockError.offline
        }
    }
}

private enum MockError: LocalizedError {
    case offline

    var errorDescription: String? { "offline" }
}

private actor NotModifiedThenContentFetcher: RuleSourceFetching {
    private(set) var callCount = 0

    func fetch(
        source: RuleSource,
        timeoutSeconds: Int,
        maximumSizeMB: Int
    ) async throws -> RuleSourceFetchResult {
        callCount += 1
        if callCount == 1 {
            return .notModified(checkedAt: .now)
        }
        XCTAssertNil(source.etag)
        XCTAssertNil(source.lastModified)
        return .modified(
            content: "DOMAIN,repaired.example",
            etag: "new-etag",
            lastModified: nil,
            contentHash: "new-hash",
            checkedAt: .now
        )
    }
}
