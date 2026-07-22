import Foundation
import XCTest
@testable import SurgeProfileRelayCore

final class RelayPersistenceTests: XCTestCase {
    func testInjectedApplicationSupportKeepsPreviewAndCacheOutOfUserDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SurgeProfileRelayPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let output = root.appending(path: "Output", directoryHint: .isDirectory)
        let support = root.appending(path: "Application Support", directoryHint: .isDirectory)
        let persistence = RelayPersistence(
            outputDirectory: output,
            applicationSupportDirectory: support
        )
        let sourceID = UUID()

        let sharedURL = try persistence.writeSharedPreview("shared", fileName: "Shared.dconf")
        let platformURL = try persistence.writePreview("platform", for: .macOS)
        try persistence.saveCachedContent("cache", for: sourceID)

        let expectedPreviewDirectory = support.appending(path: "Preview", directoryHint: .isDirectory)
        XCTAssertEqual(
            sharedURL.deletingLastPathComponent().standardizedFileURL.path,
            expectedPreviewDirectory.standardizedFileURL.path
        )
        XCTAssertEqual(
            platformURL.deletingLastPathComponent().standardizedFileURL.path,
            expectedPreviewDirectory.standardizedFileURL.path
        )
        XCTAssertEqual(try String(contentsOf: sharedURL, encoding: .utf8), "shared")
        XCTAssertEqual(try String(contentsOf: platformURL, encoding: .utf8), "platform")
        XCTAssertEqual(try persistence.cachedContent(for: sourceID), "cache")
        XCTAssertFalse(sharedURL.path.hasPrefix(RelayPaths.localApplicationSupportDirectory.path))
    }
}
