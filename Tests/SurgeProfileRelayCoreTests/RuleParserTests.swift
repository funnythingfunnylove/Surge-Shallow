import XCTest
@testable import SurgeProfileRelayCore

final class RuleParserTests: XCTestCase {
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
}
