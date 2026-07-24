import Foundation
import XCTest
@testable import SurgeProfileRelayCore

final class ManualRuleSourceTests: XCTestCase {
    func testManualFactoryDefaultsAndCodableRoundTrip() throws {
        let source = RuleSource.manual(
            name: "Personal",
            content: "DOMAIN,example.com,DIRECT",
            policy: "PROXY"
        )

        XCTAssertTrue(source.isManual)
        XCTAssertEqual(source.contentOrigin, .manual)
        XCTAssertEqual(source.format, .surgeRuleList)
        XCTAssertEqual(source.resolvedOutputMode, .inlineMerged)
        XCTAssertEqual(source.resolvedManualPublicationMode, .inline)
        XCTAssertEqual(source.platforms, Set(RelayPlatform.allCases))
        XCTAssertTrue(source.preservesSourcePolicy)
        XCTAssertTrue(source.resolvedDetachedFileName.hasSuffix(".dconf"))

        let decoded = try JSONDecoder().decode(
            RuleSource.self,
            from: JSONEncoder().encode(source)
        )
        XCTAssertEqual(decoded, source)
    }

    func testLegacySourceWithoutManualFieldsStillDecodes() throws {
        let source = RuleSource(
            name: "Legacy",
            url: "https://example.com/rules.list",
            outputMode: nil
        )
        let encoded = try JSONEncoder().encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "contentOrigin")
        object.removeValue(forKey: "manualPublicationMode")
        object.removeValue(forKey: "detachedFileName")

        let decoded = try JSONDecoder().decode(
            RuleSource.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.contentOrigin)
        XCTAssertNil(decoded.manualPublicationMode)
        XCTAssertNil(decoded.detachedFileName)
        XCTAssertEqual(decoded.resolvedOutputMode, .inlineMerged)
    }

    func testManualParserSupportsMultipleRulesPoliciesCommentsAndFinalFiltering() throws {
        var source = RuleSource.manual(name: "Manual", policy: "PROXY")
        source.preservesSourcePolicy = true
        let parsed = try RuleParser.parse(
            """
            # note

            DOMAIN,example.com,DIRECT
            DOMAIN-SUFFIX,example.org
            IP-CIDR,192.0.2.0/24,no-resolve
            FINAL,REJECT
            invalid
            """,
            for: source
        )

        XCTAssertEqual(parsed.rules, [
            "DOMAIN,example.com,DIRECT",
            "DOMAIN-SUFFIX,example.org,PROXY",
            "IP-CIDR,192.0.2.0/24,PROXY,no-resolve"
        ])
        XCTAssertTrue(parsed.warnings.contains { $0.contains("FINAL") })
        XCTAssertTrue(parsed.warnings.contains { $0.contains("不是有效") })
    }

    func testManualParserDoesNotAllowProfileIncludeDirectiveInjection() {
        let source = RuleSource.manual(
            name: "Manual",
            content: "#!include User-Owned.dconf"
        )

        XCTAssertThrowsError(
            try RuleParser.parse(source.embeddedContent ?? "", for: source)
        ) { error in
            guard case RuleParsingError.noUsableRules = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testEmbeddedManualSourceSizeLimitIsEnforcedWithoutNetwork() async throws {
        let source = RuleSource.manual(
            name: "Large",
            content: String(repeating: "a", count: 1_024 * 1_024 + 1)
        )

        do {
            _ = try await URLSessionRuleSourceFetcher().fetch(
                source: source,
                timeoutSeconds: 5,
                maximumSizeMB: 1
            )
            XCTFail("Expected source size rejection")
        } catch let error as RuleSourceFetchError {
            guard case .sourceTooLarge(1) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDetachedFilenameSanitization() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!

        XCTAssertEqual(
            RuleSource.sanitizedDetachedFileName(" ../My/Rules.CONF ", sourceID: id),
            "My-Rules.CONF.dconf"
        )
        XCTAssertEqual(
            RuleSource.sanitizedDetachedFileName("..", sourceID: id),
            "Manual-Rules-12345678.dconf"
        )
        XCTAssertEqual(
            RuleSource.sanitizedDetachedFileName("Personal.DCONF", sourceID: id),
            "Personal.dconf"
        )
    }

    func testDetachedManualSourceKeepsIncludePositionAndFirstSourcePriority() throws {
        let first = RuleSource(
            name: "First",
            url: "https://example.com/first",
            policy: "DIRECT",
            outputMode: .inlineMerged
        )
        var manual = RuleSource.manual(name: "Manual", policy: "PROXY")
        manual.manualPublicationMode = .detachedProfile
        manual.detachedFileName = "Personal.dconf"
        let last = RuleSource(
            name: "Last",
            url: "https://example.com/last",
            policy: "REJECT",
            outputMode: .inlineMerged
        )
        let firstParsed = try RuleParser.parse("DOMAIN,shared.example", for: first)
        let manualParsed = try RuleParser.parse(
            "DOMAIN,shared.example\nDOMAIN,manual.example",
            for: manual
        )
        let lastParsed = try RuleParser.parse(
            "DOMAIN,manual.example\nDOMAIN,last.example",
            for: last
        )

        let merged = RuleMerger.merge(
            [(first, firstParsed), (manual, manualParsed), (last, lastParsed)],
            for: .macOS
        )

        let firstIndex = try XCTUnwrap(merged.lines.firstIndex(of: "DOMAIN,shared.example,DIRECT"))
        let includeIndex = try XCTUnwrap(merged.lines.firstIndex(of: "#!include Personal.dconf"))
        let lastIndex = try XCTUnwrap(merged.lines.firstIndex(of: "DOMAIN,last.example,REJECT"))
        XCTAssertLessThan(firstIndex, includeIndex)
        XCTAssertLessThan(includeIndex, lastIndex)
        XCTAssertFalse(merged.lines.contains("DOMAIN,manual.example,REJECT"))
        XCTAssertEqual(merged.detachedRuleFiles.first?.rules, [
            "DOMAIN,shared.example,PROXY",
            "DOMAIN,manual.example,PROXY"
        ])
    }

    func testEnginePublishesMacOnlyDetachedRulesWithoutChangingIOSRules() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = RuleSource.manual(
            name: "Mac Personal",
            content: "DOMAIN,mac-personal.example,DIRECT"
        )
        source.manualPublicationMode = .detachedProfile
        source.detachedFileName = "Mac-Personal.dconf"
        source.platforms = [.macOS]
        let document = makeDocument(source: source, directory: directory, validatesWithCLI: false)

        let result = await RelayEngine().refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        XCTAssertEqual(result.generatedDetachedRuleFiles.count, 1)
        let detached = try XCTUnwrap(result.generatedDetachedRuleFiles.first)
        XCTAssertTrue(detached.content.contains(ProfileAssembler.ownershipMarker))
        XCTAssertTrue(detached.content.contains("[Rule]\nDOMAIN,mac-personal.example,DIRECT"))
        XCTAssertFalse(detached.content.contains("FINAL,"))
        XCTAssertTrue(result.generatedProfiles.first { $0.platform == .macOS }?
            .content.contains("#!include Mac-Personal.dconf") == true)
        XCTAssertFalse(result.generatedProfiles.first { $0.platform == .iOS }?
            .content.contains("Mac-Personal.dconf") ?? true)
        XCTAssertFalse(result.generatedSharedProfile?.content.contains("Mac-Personal.dconf") ?? true)
    }

    func testEngineMergesInlineManualRulesWithoutPublishingDetachedFile() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = RuleSource.manual(
            name: "Inline Personal",
            content: "DOMAIN,inline-personal.example,DIRECT"
        )
        let document = makeDocument(source: source, directory: directory, validatesWithCLI: false)

        let result = await RelayEngine().refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        XCTAssertTrue(result.generatedDetachedRuleFiles.isEmpty)
        XCTAssertTrue(result.generatedSharedProfile?.content.contains(
            "DOMAIN,inline-personal.example,DIRECT"
        ) == true)
    }

    func testEngineSharesDualPlatformDetachedRulesAndSurgeCLIValidatesReferences() async throws {
        guard SurgeCLIValidator.executableURL != nil else {
            throw XCTSkip("Surge CLI is not installed")
        }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var source = RuleSource.manual(
            name: "Shared Personal",
            content: "DOMAIN,shared-personal.example,DIRECT"
        )
        source.manualPublicationMode = .detachedProfile
        source.detachedFileName = "Shared-Personal.dconf"
        source.platforms = Set(RelayPlatform.allCases)
        let document = makeDocument(source: source, directory: directory, validatesWithCLI: true)

        let result = await RelayEngine().refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertTrue(result.succeeded, result.details)
        XCTAssertTrue(result.generatedSharedProfile?.content.contains(
            "#!include Shared-Personal.dconf"
        ) == true)
        XCTAssertEqual(result.generatedDetachedRuleFiles.count, 1)
        XCTAssertTrue(result.generatedProfiles.allSatisfy {
            $0.validationMessage.localizedCaseInsensitiveContains("pass")
                || $0.validationMessage.contains("通过")
                || $0.validationMessage.localizedCaseInsensitiveContains("successful")
                || $0.validationMessage.localizedCaseInsensitiveContains("valid")
                || $0.validationMessage.localizedCaseInsensitiveContains("ok")
        })
    }

    func testEngineRejectsDetachedFilenameCollision() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var first = RuleSource.manual(name: "First", content: "DOMAIN,first.example,DIRECT")
        first.manualPublicationMode = .detachedProfile
        first.detachedFileName = "Same.dconf"
        var second = RuleSource.manual(name: "Second", content: "DOMAIN,second.example,DIRECT")
        second.manualPublicationMode = .detachedProfile
        second.detachedFileName = "same.DCONF"
        var document = makeDocument(source: first, directory: directory, validatesWithCLI: false)
        document.sources.append(second)

        let result = await RelayEngine().refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.title, "输出文件名重复")
        XCTAssertTrue(result.details.localizedCaseInsensitiveContains("same.dconf"))
    }

    func testEngineNeverOverwritesUnownedDetachedFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appending(path: "Personal.dconf")
        let userContent = "[Rule]\nDOMAIN,user-owned.example,DIRECT\n"
        try Data(userContent.utf8).write(to: existing)
        var source = RuleSource.manual(name: "Manual", content: "DOMAIN,new.example,DIRECT")
        source.manualPublicationMode = .detachedProfile
        source.detachedFileName = "Personal.dconf"
        let document = makeDocument(source: source, directory: directory, validatesWithCLI: false)

        let result = await RelayEngine().refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.details.contains("不是本应用生成"))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), userContent)
    }

    func testEngineNeverOverwritesDetachedFileOwnedByAnotherManualSource() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appending(path: "Personal.dconf")
        let otherID = UUID()
        let otherContent = """
        \(ProfileAssembler.ownershipMarker)
        \(ProfileAssembler.manualSourceMarker(for: otherID))
        [Rule]
        DOMAIN,other.example,DIRECT
        """
        try Data(otherContent.utf8).write(to: existing)
        var source = RuleSource.manual(name: "Manual", content: "DOMAIN,new.example,DIRECT")
        source.manualPublicationMode = .detachedProfile
        source.detachedFileName = "Personal.dconf"
        let document = makeDocument(source: source, directory: directory, validatesWithCLI: false)

        let result = await RelayEngine().refresh(
            document: document,
            persistence: testPersistence(outputDirectory: directory),
            force: true
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.details.contains("不属于当前手工规则"))
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), otherContent)
    }

    private func makeDocument(
        source: RuleSource,
        directory: URL,
        validatesWithCLI: Bool
    ) -> RelayDocument {
        let suffix = UUID().uuidString
        var targets = RelayPlatform.allCases.map(TargetProfile.defaults)
        for index in targets.indices {
            targets[index].outputFileName = "\(suffix)-\(targets[index].platform.rawValue).conf"
        }
        var shared = SharedProfile.defaults
        shared.outputFileName = "\(suffix)-Common.dconf"
        var settings = RelaySettings(outputDirectory: directory.path)
        settings.validateWithSurgeCLI = validatesWithCLI
        return RelayDocument(
            sources: [source],
            sharedProfile: shared,
            targets: targets,
            settings: settings
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "SurgeManualRuleTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
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
