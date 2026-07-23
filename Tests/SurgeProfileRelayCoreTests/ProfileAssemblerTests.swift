import XCTest
@testable import SurgeProfileRelayCore

final class ProfileAssemblerTests: XCTestCase {
    func testDetachedProfileReusesSharedSectionsAndKeepsOnlyPlatformDifferencesLocal() throws {
        let common = """
        [General]
        loglevel = notify
        dns-server = 1.1.1.1
        [Proxy]
        [Proxy Group]
        PROXY = select, DIRECT
        [Rule]
        FINAL,DIRECT
        """
        let merged = MergedRules(
            lines: ["DOMAIN,shared.example,PROXY"],
            ruleCount: 1,
            duplicateCount: 0,
            warnings: []
        )

        let shared = try ProfileAssembler.assembleShared(
            baseProfile: common,
            sharedRules: merged,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let platform = try ProfileAssembler.assemblePlatform(
            platformProfile: "[General]\nloglevel = info",
            sharedFileName: "Shared.dconf",
            sharedSections: shared.sections,
            mergedRules: merged,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(shared.content.contains("[Rule]\n\(ProfileAssembler.ownershipMarker)"))
        XCTAssertTrue(shared.content.contains("DOMAIN,shared.example,PROXY"))
        XCTAssertTrue(platform.content.contains("[General]\n#!include Shared.dconf\nloglevel = info"))
        XCTAssertTrue(platform.content.contains("[Proxy]\n#!include Shared.dconf"))
        XCTAssertTrue(platform.content.contains("[Proxy Group]\n#!include Shared.dconf"))
        XCTAssertTrue(platform.content.contains("[Rule]\n#!include Shared.dconf"))
        XCTAssertFalse(platform.content.contains("DOMAIN,shared.example,PROXY"))
        XCTAssertTrue(ProfileAssembler.lint(platform.content).isValid)
    }

    func testPlatformKeepsGeneratedRuleLocalWhenRulesCannotBeShared() throws {
        let merged = MergedRules(
            lines: ["DOMAIN,mac-only.example,PROXY"],
            ruleCount: 1,
            duplicateCount: 0,
            warnings: []
        )
        let shared = try ProfileAssembler.assembleShared(
            baseProfile: "[General]\nloglevel = notify\n[Rule]\nFINAL,DIRECT",
            sharedRules: nil,
            finalPolicy: nil,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let platform = try ProfileAssembler.assemblePlatform(
            platformProfile: "",
            sharedFileName: "Shared.dconf",
            sharedSections: shared.sections,
            mergedRules: merged,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(shared.sections.contains(where: { $0.caseInsensitiveCompare("Rule") == .orderedSame }))
        XCTAssertFalse(shared.content.contains("[Rule]"))
        XCTAssertTrue(platform.content.contains("[General]\n#!include Shared.dconf"))
        XCTAssertTrue(platform.content.contains("[Rule]\n\(ProfileAssembler.ownershipMarker)"))
        XCTAssertTrue(platform.content.contains("DOMAIN,mac-only.example,PROXY"))
        XCTAssertTrue(platform.content.hasSuffix("FINAL,DIRECT\n"))
    }

    func testDetachedProfilesPassInstalledSurgeCLI() async throws {
        guard SurgeCLIValidator.executableURL != nil else {
            throw XCTSkip("Surge CLI is not installed")
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SurgeProfileRelayDetachedCheck-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sharedFileName = "Shared.dconf"
        let merged = MergedRules(
            lines: ["DOMAIN,shared.example,PROXY"],
            ruleCount: 1,
            duplicateCount: 0,
            warnings: []
        )
        var structuredShared = SharedProfile.defaults
        structuredShared.proxies = [
            ProxyDefinition(
                name: "LocalHTTP",
                type: "http",
                parameters: "127.0.0.1, 8080"
            ),
            ProxyDefinition(
                name: "SnellV6",
                type: "snell",
                parameters: "127.0.0.1, 7177, psk=test-password, version=6",
                presetID: "snell-v6"
            )
        ]
        structuredShared.proxyGroups = [
            ProxyDefinition(name: "PROXY", type: "smart", parameters: "LocalHTTP, SnellV6")
        ]
        let shared = try ProfileAssembler.assembleShared(
            baseProfile: structuredShared.baseProfile,
            sharedRules: merged,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(shared.content.contains("LocalHTTP = http, 127.0.0.1, 8080"))
        XCTAssertTrue(
            shared.content.contains(
                "SnellV6 = snell, 127.0.0.1, 7177, psk=test-password, version=6"
            )
        )
        XCTAssertTrue(shared.content.contains("PROXY = smart, LocalHTTP, SnellV6"))
        try Data(shared.content.utf8).write(to: directory.appending(path: sharedFileName))

        for platform in RelayPlatform.allCases {
            let differences: [ProfileDifferenceItem] = if platform == .macOS {
                [
                    ProfileDifferenceItem(section: "General", key: "loglevel", value: "info"),
                    ProfileDifferenceItem(section: "General", key: "http-listen", value: "127.0.0.1:6152")
                ]
            } else {
                [
                    ProfileDifferenceItem(section: "General", key: "include-all-networks", value: "true"),
                    ProfileDifferenceItem(section: "General", key: "include-local-networks", value: "true"),
                    ProfileDifferenceItem(section: "General", key: "allow-wifi-access", value: "true"),
                    ProfileDifferenceItem(section: "General", key: "wifi-access-http-port", value: "6152")
                ]
            }
            let target = TargetProfile(
                platform: platform,
                outputFileName: "\(platform.rawValue).conf",
                platformDifferences: differences
            )
            let profile = try ProfileAssembler.assemblePlatform(
                platformProfile: target.platformProfile,
                sharedFileName: sharedFileName,
                sharedSections: shared.sections,
                mergedRules: merged,
                finalPolicy: "DIRECT",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
            let url = directory.appending(path: "\(platform.rawValue).conf")
            try Data(profile.content.utf8).write(to: url)
            let validation = await SurgeCLIValidator.validate(profileAt: url)
            XCTAssertTrue(validation.isValid, "\(platform.displayName): \(validation.message)")
        }
    }

    func testCompactRulesetProfilesPassInstalledSurgeCLIAndStaySmallerThanInlineOutput() async throws {
        guard SurgeCLIValidator.executableURL != nil else {
            throw XCTSkip("Surge CLI is not installed")
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SurgeProfileRelayCompactCheck-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = """
        [General]
        loglevel = notify
        [Proxy]
        [Proxy Group]
        PROXY = select, DIRECT
        [Rule]
        FINAL,DIRECT
        """
        let compactRules = MergedRules(
            lines: [
                "RULE-SET,https://rules.example.com/compact.list,PROXY,no-resolve,extended-matching"
            ],
            ruleCount: 1,
            duplicateCount: 0,
            warnings: []
        )
        let expandedRuleLines = (0..<20_000).map { index in
            "DOMAIN,expanded-\(index).example,PROXY"
        }
        let expandedRules = MergedRules(
            lines: expandedRuleLines,
            ruleCount: expandedRuleLines.count,
            duplicateCount: 0,
            warnings: []
        )
        let compactShared = try ProfileAssembler.assembleShared(
            baseProfile: base,
            sharedRules: compactRules,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let expandedShared = try ProfileAssembler.assembleShared(
            baseProfile: base,
            sharedRules: expandedRules,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertLessThan(compactShared.content.utf8.count * 100, expandedShared.content.utf8.count)
        XCTAssertLessThan(
            compactShared.content.components(separatedBy: "\n").count * 100,
            expandedShared.content.components(separatedBy: "\n").count
        )

        let sharedFileName = "Compact Shared.dconf"
        try Data(compactShared.content.utf8).write(to: directory.appending(path: sharedFileName))
        for platform in RelayPlatform.allCases {
            let profile = try ProfileAssembler.assemblePlatform(
                platformProfile: "",
                sharedFileName: sharedFileName,
                sharedSections: compactShared.sections,
                mergedRules: compactRules,
                finalPolicy: "DIRECT",
                generatedAt: Date(timeIntervalSince1970: 0)
            )
            let url = directory.appending(path: "compact-\(platform.rawValue).conf")
            try Data(profile.content.utf8).write(to: url)
            let validation = await SurgeCLIValidator.validate(profileAt: url)
            XCTAssertTrue(validation.isValid, "\(platform.displayName): \(validation.message)")
        }
    }

    func testAssemblerReplacesOnlyRuleSectionAndStripsManagedDirective() throws {
        let base = """
        #!MANAGED-CONFIG https://example.com/base.conf interval=60
        [General]
        loglevel = notify
        [Rule]
        DOMAIN,old.example,DIRECT
        FINAL,DIRECT
        [MITM]
        hostname = example.com
        """
        let merged = MergedRules(
            lines: ["DOMAIN,new.example,PROXY"],
            ruleCount: 1,
            duplicateCount: 0,
            warnings: []
        )

        let result = try ProfileAssembler.assemble(
            baseProfile: base,
            mergedRules: merged,
            finalPolicy: "DIRECT",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(result.content.contains("MANAGED-CONFIG"))
        XCTAssertFalse(result.content.contains("old.example"))
        XCTAssertTrue(result.content.contains("DOMAIN,new.example,PROXY"))
        XCTAssertTrue(result.content.contains("[MITM]\nhostname = example.com"))
        XCTAssertTrue(result.content.contains(ProfileAssembler.ownershipMarker))
        XCTAssertEqual(result.content.components(separatedBy: "FINAL,DIRECT").count - 1, 1)
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("MANAGED-CONFIG") }))
    }

    func testAssemblerCreatesMissingRuleSection() throws {
        let merged = MergedRules(lines: [], ruleCount: 0, duplicateCount: 0, warnings: [])

        let result = try ProfileAssembler.assemble(
            baseProfile: "[General]\nloglevel = notify",
            mergedRules: merged,
            finalPolicy: "DIRECT"
        )

        XCTAssertTrue(result.content.contains("[Rule]"))
        XCTAssertTrue(result.content.hasSuffix("FINAL,DIRECT\n"))
        XCTAssertTrue(result.warnings.contains(where: { $0.contains("自动创建") }))
    }

    func testLintRejectsFinalBeforeAnotherRule() {
        let profile = """
        [General]
        [Rule]
        FINAL,DIRECT
        DOMAIN,example.com,DIRECT
        """

        let lint = ProfileAssembler.lint(profile)

        XCTAssertFalse(lint.isValid)
        XCTAssertTrue(lint.errors.contains(where: { $0.contains("最后") }))
    }

    func testOutputFileNameSanitization() {
        let name = TargetProfile.sanitizedFileName("bad/name:ios", platform: .iOS)
        XCTAssertEqual(name, "bad-name-ios.conf")
    }

    func testUnsafeFinalPolicyIsRejected() {
        let merged = MergedRules(lines: [], ruleCount: 0, duplicateCount: 0, warnings: [])

        XCTAssertThrowsError(
            try ProfileAssembler.assemble(
                baseProfile: "[General]\n[Rule]\nFINAL,DIRECT",
                mergedRules: merged,
                finalPolicy: "DIRECT\n[MITM]"
            )
        )
    }
}
