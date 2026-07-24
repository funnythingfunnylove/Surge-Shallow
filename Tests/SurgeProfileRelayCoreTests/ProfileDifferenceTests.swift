import XCTest
@testable import SurgeProfileRelayCore

final class ProfileDifferenceTests: XCTestCase {
    func testKnownBooleanChoiceTextAndCustomItemsRenderIntoSections() {
        let items = [
            ProfileDifferenceItem(section: "General", key: "include-all-networks", value: "true"),
            ProfileDifferenceItem(section: "General", key: "compatibility-mode", value: "3"),
            ProfileDifferenceItem(section: "General", key: "wifi-access-http-port", value: "6152"),
            ProfileDifferenceItem(section: "MITM", key: "hostname", value: "ios.example"),
            ProfileDifferenceItem(section: "Custom", key: "custom-key", value: "custom-value")
        ]

        let rendered = ProfileDifferenceCodec.render(items)

        XCTAssertTrue(rendered.contains("[General]"))
        XCTAssertTrue(rendered.contains("include-all-networks = true"))
        XCTAssertTrue(rendered.contains("compatibility-mode = 3"))
        XCTAssertTrue(rendered.contains("wifi-access-http-port = 6152"))
        XCTAssertTrue(rendered.contains("[MITM]\nhostname = ios.example"))
        XCTAssertTrue(rendered.contains("[Custom]\ncustom-key = custom-value"))
    }

    func testParserAndRendererPreserveUnknownKeyValuesCommentsAndDirectives() {
        let input = """
        # custom preamble
        [General]
        unknown-key = unknown-value
        # custom section note
        #!include Additional.dconf
        """

        let items = ProfileDifferenceCodec.parse(input)
        let output = ProfileDifferenceCodec.render(items)

        XCTAssertTrue(output.contains("# custom preamble"))
        XCTAssertTrue(output.contains("unknown-key = unknown-value"))
        XCTAssertTrue(output.contains("# custom section note"))
        XCTAssertTrue(output.contains("#!include Additional.dconf"))
    }

    func testRuleSectionIsRejectedFromStructuredDifferences() {
        let parsed = ProfileDifferenceCodec.parse("""
        [General]
        loglevel = info
        [Rule]
        DOMAIN,manual.example,DIRECT
        FINAL,DIRECT
        """)
        var injected = parsed
        injected.append(ProfileDifferenceItem(section: "Rule", key: "manual", value: "bad"))
        injected.append(.rawLine(section: "", line: "[Rule]"))

        let rendered = ProfileDifferenceCodec.render(injected)

        XCTAssertFalse(rendered.contains("[Rule]"))
        XCTAssertFalse(rendered.contains("manual.example"))
        XCTAssertFalse(rendered.contains("manual = bad"))
    }

    func testRemovingDifferenceRestoresSharedInheritanceOnly() {
        var target = TargetProfile(
            platform: .macOS,
            outputFileName: "mac.conf",
            platformDifferences: [
                ProfileDifferenceItem(section: "General", key: "loglevel", value: "info")
            ]
        )

        XCTAssertTrue(target.platformProfile.contains("loglevel = info"))
        target.platformDifferences.removeAll()
        XCTAssertEqual(target.platformProfile, "")
    }

    func testCatalogSeparatesCommonAndPlatformOnlyOptions() {
        XCTAssertTrue(ProfileOptionCatalog.common.contains { $0.key == "dns-server" })
        XCTAssertTrue(ProfileOptionCatalog.iOSOnly.contains { $0.key == "include-all-networks" })
        XCTAssertTrue(ProfileOptionCatalog.macOSOnly.contains { $0.key == "http-listen" })
        XCTAssertFalse(ProfileOptionCatalog.platformOnlyOptions(for: .macOS).contains {
            $0.key == "include-all-networks"
        })
    }

    func testAdvancedSectionCatalogMatchesDocumentedPlatformAvailability() throws {
        let names = ProfileSectionCatalog.advanced.map(\.name)

        XCTAssertTrue(names.starts(with: [
            "Host", "MITM", "Script", "URL Rewrite", "Header Rewrite",
            "Body Rewrite", "Map Local", "SSID Setting", "Panel"
        ]))
        XCTAssertEqual(ProfileSectionCatalog.descriptor(named: "[host]")?.name, "Host")
        XCTAssertTrue(try XCTUnwrap(ProfileSectionCatalog.descriptor(named: "Panel")).isAvailable(on: .iOS))
        XCTAssertFalse(try XCTUnwrap(ProfileSectionCatalog.descriptor(named: "Panel")).isAvailable(on: .macOS))
        XCTAssertTrue(try XCTUnwrap(ProfileSectionCatalog.descriptor(named: "DHCP")).isAvailable(on: .macOS))
        XCTAssertFalse(try XCTUnwrap(ProfileSectionCatalog.descriptor(named: "DHCP")).isAvailable(on: .iOS))
        XCTAssertTrue(try XCTUnwrap(ProfileSectionCatalog.descriptor(named: "Ruleset Streaming")).isAvailable(on: .macOS))
        XCTAssertFalse(try XCTUnwrap(ProfileSectionCatalog.descriptor(named: "Ruleset Streaming")).isAvailable(on: .iOS))
    }

    func testCustomSectionNamesAreNormalizedDeduplicatedAndExcludeManagedSections() {
        let items = [
            ProfileDifferenceItem(section: "[WireGuard Office]", key: "private-key", value: "placeholder"),
            .rawLine(section: "wireguard office", line: "self = 10.0.0.2/32"),
            ProfileDifferenceItem(section: "General", key: "loglevel", value: "info"),
            .rawLine(section: "Custom Future Section", line: "value")
        ]

        XCTAssertEqual(
            ProfileSectionCatalog.customSectionNames(in: items),
            ["WireGuard Office", "Custom Future Section"]
        )
        XCTAssertTrue(ProfileSectionCatalog.isValidCustomSectionName("[Future Section]"))
        XCTAssertFalse(ProfileSectionCatalog.isValidCustomSectionName("[Rule]"))
        XCTAssertFalse(ProfileSectionCatalog.isValidCustomSectionName("Bad]Section"))
    }
}
