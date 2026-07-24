import Foundation
import XCTest
@testable import SurgeProfileRelayCore

final class RelayPersistenceTests: XCTestCase {
    func testLoadWaitsForTransientICloudConflictToSettle() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SurgeProfileRelayPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let output = root.appending(path: "Output", directoryHint: .isDirectory)
        let support = root.appending(path: "Application Support", directoryHint: .isDirectory)
        var expected = RelayDocument()
        expected.settings.outputDirectory = output.path
        try RelayPersistence(
            outputDirectory: output,
            applicationSupportDirectory: support
        ).saveDocument(expected)

        let conflictStatus = ScriptedConflictStatus([true, true, false])
        let persistence = RelayPersistence(
            outputDirectory: output,
            applicationSupportDirectory: support,
            maximumConflictChecks: 3,
            conflictRetryDelay: 0,
            unresolvedConflictCheck: { _ in conflictStatus.next() },
            conflictRetryWait: { _ in }
        )

        let loaded = try persistence.loadDocument()

        XCTAssertEqual(loaded.settings.outputDirectory, expected.settings.outputDirectory)
        XCTAssertEqual(conflictStatus.callCount, 3)
    }

    func testLoadStillRejectsPersistentICloudConflict() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SurgeProfileRelayPersistenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let output = root.appending(path: "Output", directoryHint: .isDirectory)
        let support = root.appending(path: "Application Support", directoryHint: .isDirectory)
        try RelayPersistence(
            outputDirectory: output,
            applicationSupportDirectory: support
        ).saveDocument(RelayDocument())

        let conflictStatus = ScriptedConflictStatus([true, true, true])
        let persistence = RelayPersistence(
            outputDirectory: output,
            applicationSupportDirectory: support,
            maximumConflictChecks: 3,
            conflictRetryDelay: 0,
            unresolvedConflictCheck: { _ in conflictStatus.next() },
            conflictRetryWait: { _ in }
        )

        XCTAssertThrowsError(try persistence.loadDocument()) { error in
            guard case RelayPersistenceError.iCloudConflict("relay.json") = error else {
                return XCTFail("Expected relay.json iCloud conflict, got \(error)")
            }
        }
        XCTAssertEqual(conflictStatus.callCount, 3)
    }

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

private final class ScriptedConflictStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool]
    private(set) var callCount = 0

    init(_ values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        lock.withLock {
            callCount += 1
            if values.isEmpty { return false }
            return values.removeFirst()
        }
    }
}
