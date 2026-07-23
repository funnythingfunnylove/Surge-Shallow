import Foundation
import XCTest
@testable import SurgeProfileRelayCore

final class ProfileImportServiceTests: XCTestCase {
    func testParsesCompleteProfileAndClassifiesReusableAndPlatformOptions() throws {
        let profile = """
        # existing profile
        #!MANAGED-CONFIG https://example.com/profile interval=86400
        [General]
        loglevel = info
        include-all-networks = true
        read-etc-hosts = true
        custom-general = kept
        [Proxy]
        Home = snell, server.example.com, 8000, psk=secret, version=6
        [Proxy Group]
        PROXY = smart, Home, DIRECT
        [Rule]
        DOMAIN,example.com,PROXY
        IP-CIDR,192.0.2.0/24,DIRECT,no-resolve
        FINAL,PROXY
        [MITM]
        hostname = example.com
        [WireGuard Home]
        private-key = redacted
        """

        let draft = try ProfileImportService.parse(content: profile, fileName: "Existing.conf")

        XCTAssertEqual(draft.summary.generalOptionCount, 4)
        XCTAssertEqual(draft.summary.proxyCount, 1)
        XCTAssertEqual(draft.summary.proxyGroupCount, 1)
        XCTAssertEqual(draft.summary.ruleCount, 2)
        XCTAssertEqual(draft.finalPolicy, "PROXY")
        XCTAssertTrue(draft.sharedProfile.preamble.contains("existing profile"))
        XCTAssertFalse(draft.sharedProfile.preamble.localizedCaseInsensitiveContains("managed-config"))
        XCTAssertTrue(draft.sharedProfile.generalOptions.contains { $0.key == "loglevel" })
        XCTAssertTrue(draft.sharedProfile.generalOptions.contains { $0.key == "custom-general" })
        XCTAssertTrue(draft.platformDifferences[.iOS, default: []].contains { $0.key == "include-all-networks" })
        XCTAssertTrue(draft.platformDifferences[.macOS, default: []].contains { $0.key == "read-etc-hosts" })
        XCTAssertTrue(draft.sharedProfile.advancedProfile.contains("[MITM]"))
        XCTAssertTrue(draft.platformDifferences[.macOS, default: []].contains { $0.section == "WireGuard Home" })
        XCTAssertTrue(draft.platformDifferences[.iOS, default: []].contains { $0.section == "WireGuard Home" })
        XCTAssertFalse(draft.importedRules.contains("FINAL"))
        XCTAssertTrue(draft.warnings.contains { $0.contains("MANAGED-CONFIG") })
    }

    func testMultipleFinalUsesLastAndPreservesRuleInclude() throws {
        let profile = """
        [Rule]
        #!include Rules/Common.list
        DOMAIN,one.example,DIRECT
        FINAL,DIRECT
        FINAL,PROXY # latest
        """

        let draft = try ProfileImportService.parse(content: profile, fileName: "Rules.conf")

        XCTAssertEqual(draft.finalPolicy, "PROXY")
        XCTAssertEqual(draft.summary.ruleCount, 1)
        XCTAssertEqual(draft.summary.includeDirectiveCount, 1)
        XCTAssertTrue(draft.importedRules.contains("#!include Rules/Common.list"))
        XCTAssertTrue(draft.warnings.contains { $0.contains("2 条 FINAL") })
    }

    func testRemoteRulesetsBecomeIndependentSourcesWithoutChangingRuleOrder() throws {
        let profile = """
        [Rule]
        # before remote sources
        DOMAIN,before.example,DIRECT
        RULE-SET,https://rules.example.com/set/a.list,Proxy,no-resolve
        DOMAIN,middle.example,PROXY
        RULE-SET,https://rules.example.com/set/b.list,DIRECT,extended-matching
        RULE-SET,LAN,DIRECT
        DOMAIN,after.example,DIRECT
        FINAL,PROXY
        """

        let draft = try ProfileImportService.parse(content: profile, fileName: "Ordered.conf")
        let applied = ProfileImportService.applying(draft, to: RelayDocument(), platforms: [.macOS])

        XCTAssertEqual(draft.summary.ruleCount, 4)
        XCTAssertEqual(draft.summary.rulesetCount, 2)
        XCTAssertEqual(applied.sources.count, 5)
        XCTAssertEqual(applied.sources.map(\.format), [
            .surgeRuleList,
            .surgeRuleset,
            .surgeRuleList,
            .surgeRuleset,
            .surgeRuleList
        ])
        XCTAssertEqual(applied.sources.map(\.platforms), Array(repeating: [.macOS], count: 5))

        let firstRuleset = applied.sources[1]
        XCTAssertEqual(firstRuleset.url, "https://rules.example.com/set/a.list")
        XCTAssertEqual(firstRuleset.policy, "Proxy")
        XCTAssertEqual(firstRuleset.rulesetOptions, [.noResolve])
        XCTAssertFalse(firstRuleset.preservesSourcePolicy)
        XCTAssertEqual(firstRuleset.outputMode, .remoteReference)

        let secondRuleset = applied.sources[3]
        XCTAssertEqual(secondRuleset.url, "https://rules.example.com/set/b.list")
        XCTAssertEqual(secondRuleset.policy, "DIRECT")
        XCTAssertEqual(secondRuleset.rulesetOptions, [.extendedMatching])
        XCTAssertEqual(secondRuleset.outputMode, .remoteReference)
        XCTAssertEqual(applied.sources[0].outputMode, .inlineMerged)
        XCTAssertEqual(applied.sources[2].outputMode, .inlineMerged)
        XCTAssertEqual(applied.sources[4].outputMode, .inlineMerged)
        XCTAssertTrue(applied.sources[4].embeddedContent?.contains("RULE-SET,LAN,DIRECT") == true)
        XCTAssertFalse(draft.importedRules.contains("https://rules.example.com"))
    }

    func testUnknownRemoteRulesetParameterProducesExplicitWarning() throws {
        let draft = try ProfileImportService.parse(
            content: "[Rule]\nRULE-SET,https://rules.example.com/reject.list,REJECT,pre-matching\nFINAL,DIRECT",
            fileName: "Legacy.conf"
        )

        XCTAssertEqual(draft.summary.rulesetCount, 1)
        XCTAssertEqual(draft.importedSources.first?.format, .surgeRuleset)
        XCTAssertEqual(draft.importedSources.first?.rulesetOptions, [])
        XCTAssertTrue(draft.warnings.contains { warning in
            warning.contains("pre-matching") && warning.contains("未应用")
        })
    }

    func testProfileWithoutRuleProducesWarningAndNoEmbeddedSource() throws {
        let draft = try ProfileImportService.parse(
            content: "[General]\nloglevel = notify\n[Host]\nrouter.local = 192.168.1.1",
            fileName: "NoRules.conf"
        )
        let applied = ProfileImportService.applying(
            draft,
            to: RelayDocument(sources: [RuleSource(name: "Old", url: "https://example.com")]),
            platforms: [.macOS]
        )

        XCTAssertTrue(applied.sources.isEmpty)
        XCTAssertTrue(draft.warnings.contains { $0.contains("没有 [Rule]") })
        XCTAssertTrue(applied.sharedProfile.advancedProfile.contains("[Host]"))
    }

    func testApplyReplacesManagedProfileButPreservesSettingsHistoryAndUnselectedTarget() throws {
        let draft = try ProfileImportService.parse(
            content: "[General]\nloglevel = verbose\n[Rule]\nDOMAIN,example.com,DIRECT\nFINAL,REJECT",
            fileName: "Mac.conf"
        )
        var input = RelayDocument()
        input.settings.refreshIntervalMinutes = 15
        input.history = [UpdateRecord(outcome: .success, title: "Existing", details: "kept")]
        let originalIOS = try XCTUnwrap(input.targets.first { $0.platform == .iOS })

        let applied = ProfileImportService.applying(draft, to: input, platforms: [.macOS])

        XCTAssertEqual(applied.settings.refreshIntervalMinutes, 15)
        XCTAssertEqual(applied.history.first?.title, "Existing")
        XCTAssertEqual(applied.targets.first { $0.platform == .iOS }, originalIOS)
        XCTAssertEqual(applied.targets.first { $0.platform == .macOS }?.finalPolicy, "REJECT")
        XCTAssertEqual(applied.sources.count, 1)
        XCTAssertEqual(applied.sources.first?.platforms, [.macOS])
        XCTAssertEqual(applied.sources.first?.embeddedContent, "DOMAIN,example.com,DIRECT")
    }

    func testInvalidUTF8IsRejected() {
        let invalid = Data([0xC3, 0x28])
        XCTAssertThrowsError(try ProfileImportService.parse(data: invalid, fileName: "Bad.conf")) { error in
            guard case ProfileImportError.invalidEncoding = error else {
                return XCTFail("Expected invalidEncoding, got \(error)")
            }
        }
    }

    func testEmbeddedSourceFetcherAndParserPreservePolicies() async throws {
        let source = RuleSource(
            name: "Imported",
            url: "embedded://profile",
            embeddedContent: "#!include SharedRules.list\nDOMAIN,example.com,DIRECT",
            format: .surgeRuleList,
            policy: "PROXY",
            preservesSourcePolicy: true
        )
        let result = try await URLSessionRuleSourceFetcher().fetch(
            source: source,
            timeoutSeconds: 5,
            maximumSizeMB: 1
        )
        guard case .modified(let content, _, _, _, _) = result else {
            return XCTFail("Expected embedded content")
        }
        let parsed = try RuleParser.parse(content, for: source)
        let merged = RuleMerger.merge([(source, parsed)], for: .macOS)

        XCTAssertTrue(merged.lines.contains("#!include SharedRules.list"))
        XCTAssertTrue(merged.lines.contains("DOMAIN,example.com,DIRECT"))
        XCTAssertTrue(merged.lines.contains("# --- Imported · 1 条 ---"))
        XCTAssertEqual(merged.ruleCount, 1)
    }

    func testInvalidProxyDefinitionIsPreservedAsRawLineWithoutBlockingSharedProfile() throws {
        let draft = try ProfileImportService.parse(
            content: "[Proxy]\nLocal = direct\n[Rule]\nFINAL,DIRECT",
            fileName: "RawProxy.conf"
        )

        XCTAssertEqual(draft.sharedProfile.proxies.first?.kind, .rawLine)
        XCTAssertEqual(draft.sharedProfile.proxies.first?.parameters, "Local = direct")
        XCTAssertTrue(draft.sharedProfile.configurationIssues.isEmpty)
        XCTAssertTrue(draft.warnings.contains { $0.contains("Proxy 中存在") })
    }
}
