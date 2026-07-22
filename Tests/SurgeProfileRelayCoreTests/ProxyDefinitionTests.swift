import XCTest
@testable import SurgeProfileRelayCore

final class ProxyDefinitionTests: XCTestCase {
    func testProxyAndGroupSectionsParseAndRenderAsStructuredDefinitions() {
        let profile = """
        [Proxy]
        Home = https, proxy.example.com, 443, user, password
        # keep note
        [Proxy Group]
        PROXY = select, Home, DIRECT
        """

        let proxies = ProxyDefinitionCodec.parse(profile: profile, section: "Proxy")
        let groups = ProxyDefinitionCodec.parse(profile: profile, section: "Proxy Group")

        XCTAssertEqual(proxies[0].name, "Home")
        XCTAssertEqual(proxies[0].type, "https")
        XCTAssertEqual(proxies[0].parameters, "proxy.example.com, 443, user, password")
        XCTAssertEqual(proxies[1].kind, .rawLine)
        XCTAssertEqual(groups[0].name, "PROXY")
        XCTAssertEqual(groups[0].type, "select")
        XCTAssertEqual(groups[0].parameters, "Home, DIRECT")
        XCTAssertTrue(
            ProxyDefinitionCodec.render(section: "Proxy", items: proxies)
                .contains("Home = https, proxy.example.com, 443, user, password")
        )
    }

    func testDefinitionValidationRejectsNameInjectionAndSectionHeaderRawLine() {
        XCTAssertFalse(ProxyDefinition(name: "Bad,Name", type: "http", parameters: "host, 80").isValid)
        XCTAssertFalse(ProxyDefinition(name: "Bad=Name", type: "http", parameters: "host, 80").isValid)
        XCTAssertFalse(ProxyDefinition(name: "Empty", type: "http", parameters: "").isValid)
        XCTAssertFalse(ProxyDefinition.rawLine("[Rule]").isValid)
        XCTAssertTrue(ProxyDefinition.rawLine("# keep comment").isValid)
    }

    func testOfficialCatalogContainsCurrentProxyAndGroupTypes() {
        XCTAssertEqual(ProxyDefinitionCatalog.proxyTypes.count, 17)
        XCTAssertTrue(ProxyDefinitionCatalog.proxyTypes.contains { $0.type == "tailscale" })
        XCTAssertTrue(ProxyDefinitionCatalog.proxyTypes.contains { $0.type == "trust-tunnel" })
        XCTAssertTrue(
            ProxyDefinitionCatalog.proxyTypes.contains {
                $0.id == "snell-v6" && $0.type == "snell"
            }
        )
        XCTAssertEqual(
            Set(ProxyDefinitionCatalog.groupTypes.map(\.type)),
            Set(["select", "url-test", "fallback", "load-balance", "subnet", "smart"])
        )
    }

    func testSnellV6PresetUsesSnellSyntaxAndRequiresVersionSix() {
        let valid = ProxyDefinition(
            name: "Snell6",
            type: "snell",
            parameters: "proxy.example.com, 8000, psk=password, version=6",
            presetID: "snell-v6"
        )
        let invalid = ProxyDefinition(
            name: "Snell6",
            type: "snell",
            parameters: "proxy.example.com, 8000, psk=password, version=4",
            presetID: "snell-v6"
        )

        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(
            valid.renderedLine,
            "Snell6 = snell, proxy.example.com, 8000, psk=password, version=6"
        )
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(invalid.presetValidationIssue, "Snell v6 参数必须包含 version=6。")

        let parsed = ProxyDefinitionCodec.parse(
            profile: "[Proxy]\n\(valid.renderedLine!)\n",
            section: "Proxy"
        )
        XCTAssertEqual(parsed.first?.presetID, "snell-v6")
        XCTAssertEqual(
            ProxyDefinitionCatalog.proxyDescriptor(for: parsed[0])?.id,
            "snell-v6"
        )
    }

    func testSharedConfigurationRejectsDuplicateNamesAndManagedAdvancedSections() {
        var shared = SharedProfile.defaults
        shared.proxies = [
            ProxyDefinition(name: "PROXY", type: "https", parameters: "example.com, 443")
        ]
        shared.advancedProfile = "[General]\nloglevel = info"

        XCTAssertTrue(shared.configurationIssues.contains { $0.contains("名称不能重复") })
        XCTAssertTrue(shared.configurationIssues.contains { $0.contains("[General]") })
    }
}
