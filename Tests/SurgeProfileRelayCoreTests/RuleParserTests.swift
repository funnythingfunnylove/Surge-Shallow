import XCTest
@testable import SurgeProfileRelayCore

final class RuleParserTests: XCTestCase {
    func testNewRemoteSourceDefaultsToCompactRulesetReference() {
        let source = RuleSource(
            name: "Compact",
            url: "https://rules.example.com/compact.list",
            format: .surgeRuleset,
            policy: "PROXY",
            rulesetOptions: [.noResolve, .extendedMatching]
        )

        XCTAssertEqual(source.outputMode, .remoteReference)
        XCTAssertEqual(source.resolvedOutputMode, .remoteReference)
        XCTAssertEqual(
            source.remoteRulesetDirective,
            "RULE-SET,https://rules.example.com/compact.list,PROXY,no-resolve,extended-matching"
        )
    }

    func testAutomaticDetectionFindsProfileRuleSection() throws {
        let content = """
        [General]
        loglevel = notify
        [Rule]
        DOMAIN,example.com,DIRECT
        FINAL,DIRECT
        [MITM]
        hostname = example.com
        """
        let source = RuleSource(name: "Profile", url: "https://example.com/a.conf", policy: "PROXY")

        let parsed = try RuleParser.parse(content, for: source)

        XCTAssertEqual(parsed.detectedFormat, .surgeProfile)
        XCTAssertEqual(parsed.rules, ["DOMAIN,example.com,PROXY"])
        XCTAssertTrue(parsed.warnings.contains(where: { $0.contains("FINAL") }))
    }

    func testDomainListConvertsToDomainSuffixRules() throws {
        let source = RuleSource(
            name: "Domains",
            url: "https://example.com/domains.txt",
            format: .domainList,
            policy: "REJECT"
        )
        let parsed = try RuleParser.parse("example.com\n*.ads.example.org\n# comment", for: source)

        XCTAssertEqual(parsed.rules, [
            "DOMAIN-SUFFIX,example.com,REJECT",
            "DOMAIN-SUFFIX,ads.example.org,REJECT"
        ])
    }

    func testClashPayloadAndSourcePolicyPreservation() throws {
        let source = RuleSource(
            name: "Clash",
            url: "https://example.com/a.yaml",
            format: .automatic,
            policy: "FALLBACK",
            preservesSourcePolicy: true
        )
        let content = """
        payload:
          - 'DOMAIN-SUFFIX,example.com'
          - 'DOMAIN,api.example.com,DIRECT'
        """

        let parsed = try RuleParser.parse(content, for: source)

        XCTAssertEqual(parsed.detectedFormat, .clashPayload)
        XCTAssertEqual(parsed.rules, [
            "DOMAIN-SUFFIX,example.com,FALLBACK",
            "DOMAIN,api.example.com,DIRECT"
        ])
    }

    func testTopLevelCSVPreservesLogicalRuleCondition() {
        let tokens = RuleParser.splitTopLevelCSV("AND,((DOMAIN,example.com),(PROTOCOL,UDP)),Proxy,no-resolve")

        XCTAssertEqual(tokens, ["AND", "((DOMAIN,example.com),(PROTOCOL,UDP))", "Proxy", "no-resolve"])
    }

    func testInlineRequirementSurvivesPolicyRewrite() throws {
        let source = RuleSource(name: "Requirements", url: "https://example.com/list", policy: "Proxy")
        let parsed = try RuleParser.parse(
            "DOMAIN,example.com,DIRECT #!REQUIREMENT SYSTEM=='macOS'",
            for: source
        )

        XCTAssertEqual(parsed.rules, ["DOMAIN,example.com,Proxy #!REQUIREMENT SYSTEM=='macOS'"])
    }

    func testPolicylessNoResolveOptionIsPreserved() throws {
        let source = RuleSource(name: "CIDR", url: "https://example.com/list", policy: "Proxy")

        let parsed = try RuleParser.parse("IP-CIDR,192.0.2.0/24,no-resolve", for: source)

        XCTAssertEqual(parsed.rules, ["IP-CIDR,192.0.2.0/24,Proxy,no-resolve"])
    }

    func testUnsafePolicyNameIsRejected() {
        let source = RuleSource(
            name: "Unsafe",
            url: "https://example.com/list",
            policy: "DIRECT\nFINAL,REJECT"
        )

        XCTAssertThrowsError(try RuleParser.parse("DOMAIN,example.com", for: source))
    }

    func testSourceNameCannotInjectGeneratedRules() throws {
        let source = RuleSource(
            name: "First\nFINAL,REJECT",
            url: "https://example.com/list",
            policy: "Proxy"
        )
        let parsed = try RuleParser.parse("DOMAIN,example.com", for: source)

        let merged = RuleMerger.merge([(source, parsed)], for: .macOS)

        XCTAssertEqual(merged.lines[0], "# --- First FINAL,REJECT · 1 条 ---")
        XCTAssertEqual(merged.ruleCount, 1)
    }

    func testMergerKeepsFirstSourcePriorityAndFiltersPlatform() throws {
        let first = RuleSource(
            name: "First",
            url: "https://one.example/list",
            policy: "Proxy",
            platforms: [.macOS]
        )
        let second = RuleSource(
            name: "Second",
            url: "https://two.example/list",
            policy: "DIRECT",
            platforms: Set(RelayPlatform.allCases)
        )
        let firstParsed = try RuleParser.parse("DOMAIN,example.com", for: first)
        let secondParsed = try RuleParser.parse("DOMAIN,example.com\nDOMAIN,other.com", for: second)

        let mac = RuleMerger.merge([(first, firstParsed), (second, secondParsed)], for: .macOS)
        let ios = RuleMerger.merge([(first, firstParsed), (second, secondParsed)], for: .iOS)

        XCTAssertEqual(mac.ruleCount, 2)
        XCTAssertEqual(mac.duplicateCount, 1)
        XCTAssertTrue(mac.lines.contains("DOMAIN,example.com,Proxy"))
        XCTAssertFalse(mac.lines.contains("DOMAIN,example.com,DIRECT"))
        XCTAssertEqual(ios.ruleCount, 2)
        XCTAssertEqual(ios.duplicateCount, 0)
        XCTAssertTrue(ios.lines.contains("DOMAIN,example.com,DIRECT"))
    }

    func testMergerKeepsCompactReferencesInSourceOrderWithoutContentDeduplication() {
        let first = RuleSource(
            name: "First",
            url: "https://rules.example.com/shared.list",
            format: .surgeRuleset,
            policy: "PROXY",
            rulesetOptions: [.noResolve]
        )
        let second = RuleSource(
            name: "Second",
            url: "https://rules.example.com/shared.list",
            format: .surgeRuleset,
            policy: "DIRECT",
            platforms: [.macOS]
        )

        let mac = RuleMerger.merge(
            [(source: first, parsed: nil), (source: second, parsed: nil)],
            for: .macOS
        )
        let ios = RuleMerger.merge(
            [(source: first, parsed: nil), (source: second, parsed: nil)],
            for: .iOS
        )

        XCTAssertEqual(mac.lines, [
            "RULE-SET,https://rules.example.com/shared.list,PROXY,no-resolve",
            "RULE-SET,https://rules.example.com/shared.list,DIRECT"
        ])
        XCTAssertEqual(mac.ruleCount, 2)
        XCTAssertEqual(mac.duplicateCount, 0)
        XCTAssertEqual(ios.lines, [
            "RULE-SET,https://rules.example.com/shared.list,PROXY,no-resolve"
        ])
    }

    func testRemoteRulesetExpandsPolicyAndOfficialOptions() throws {
        let source = RuleSource(
            name: "Remote Ruleset",
            url: "https://example.com/network.ruleset",
            format: .surgeRuleset,
            policy: "PROXY",
            preservesSourcePolicy: true,
            rulesetOptions: [.noResolve, .extendedMatching]
        )

        let parsed = try RuleParser.parse(
            """
            DOMAIN-SUFFIX,example.com
            DOMAIN,api.example.com,extended-matching
            IP-CIDR,192.0.2.0/24
            GEOIP,CN
            """,
            for: source
        )

        XCTAssertEqual(parsed.detectedFormat, .surgeRuleset)
        XCTAssertEqual(parsed.rules, [
            "DOMAIN-SUFFIX,example.com,PROXY,extended-matching",
            "DOMAIN,api.example.com,PROXY,extended-matching",
            "IP-CIDR,192.0.2.0/24,PROXY,no-resolve",
            "GEOIP,CN,PROXY,no-resolve"
        ])
    }

    func testCompleteRulesetDirectiveParsesURLPolicyAndKnownOptions() throws {
        let reference = try XCTUnwrap(RemoteRulesetReference.parse(
            "RULE-SET,https://rules.example.com/social.list,Social,no-resolve,extended-matching"
        ))

        XCTAssertEqual(reference.url, "https://rules.example.com/social.list")
        XCTAssertEqual(reference.policy, "Social")
        XCTAssertEqual(reference.options, [.noResolve, .extendedMatching])
        XCTAssertNil(RemoteRulesetReference.parse("RULE-SET,file:///tmp/local.list,PROXY"))
        XCTAssertNil(RemoteRulesetReference.parse("https://rules.example.com/plain.list"))
    }
}
