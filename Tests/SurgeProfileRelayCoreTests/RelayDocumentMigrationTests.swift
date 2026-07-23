import Foundation
import XCTest
@testable import SurgeProfileRelayCore

final class RelayDocumentMigrationTests: XCTestCase {
    func testSchemaFiveSourceWithoutRulesetFieldsStillDecodes() throws {
        let sourceID = UUID()
        let legacyJSON = """
        {
          "schemaVersion": 5,
          "sources": [
            {
              "id": "\(sourceID.uuidString)",
              "name": "Legacy URL",
              "url": "https://example.com/rules.list",
              "format": "surgeRuleList",
              "policy": "PROXY",
              "preservesSourcePolicy": false,
              "isEnabled": true,
              "platforms": ["macOS", "iOS"],
              "updateIntervalMinutes": 0,
              "createdAt": 0,
              "lastRuleCount": 0,
              "state": "never"
            }
          ],
          "sharedProfile": {
            "outputFileName": "Surge Shallow Shared.dconf",
            "preamble": "",
            "generalOptions": [],
            "proxies": [],
            "proxyGroups": [],
            "advancedProfile": ""
          },
          "targets": [],
          "settings": {
            "outputDirectory": "/tmp",
            "automaticallyRefresh": true,
            "refreshOnLaunch": true,
            "refreshIntervalMinutes": 60,
            "validateWithSurgeCLI": true,
            "launchAtLogin": false,
            "requestTimeoutSeconds": 30,
            "maximumSourceSizeMB": 10
          },
          "history": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let migrated = try decoder.decode(RelayDocument.self, from: Data(legacyJSON.utf8))
        let source = try XCTUnwrap(migrated.sources.first)

        XCTAssertEqual(migrated.schemaVersion, RelayDocument.currentSchemaVersion)
        XCTAssertEqual(source.id, sourceID)
        XCTAssertNil(source.embeddedContent)
        XCTAssertNil(source.rulesetOptions)
        XCTAssertNil(source.outputMode)
        XCTAssertEqual(source.resolvedOutputMode, .inlineMerged)
    }

    func testSchemaOneProfilesExtractIdenticalSectionsAndPreserveDifferences() throws {
        let common = """
        [General]
        loglevel = notify
        [Proxy]
        [Proxy Group]
        PROXY = select, DIRECT
        """
        let legacy = LegacyDocument(
            schemaVersion: 1,
            sources: [],
            targets: [
                LegacyTarget(
                    platform: .macOS,
                    outputFileName: "mac.conf",
                    baseProfile: common + "\n[Rule]\nFINAL,DIRECT\n[MITM]\nhostname = mac.example"
                ),
                LegacyTarget(
                    platform: .iOS,
                    outputFileName: "ios.conf",
                    baseProfile: common + "\n[Rule]\nFINAL,DIRECT\n[MITM]\nhostname = ios.example"
                )
            ],
            settings: RelaySettings(outputDirectory: "/tmp"),
            history: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let migrated = try decoder.decode(RelayDocument.self, from: encoder.encode(legacy))

        XCTAssertEqual(migrated.schemaVersion, RelayDocument.currentSchemaVersion)
        XCTAssertTrue(migrated.sharedProfile.baseProfile.contains("[General]"))
        XCTAssertTrue(migrated.sharedProfile.baseProfile.contains("[Proxy Group]"))
        XCTAssertTrue(migrated.sharedProfile.baseProfile.contains("[Rule]"))
        XCTAssertFalse(migrated.sharedProfile.baseProfile.contains("[MITM]"))
        XCTAssertFalse(migrated.targets[0].platformProfile.contains("[General]"))
        XCTAssertTrue(migrated.targets[0].platformProfile.contains("hostname = mac.example"))
        XCTAssertTrue(migrated.targets[1].platformProfile.contains("hostname = ios.example"))

        let reencoded = try encoder.encode(migrated)
        let json = try XCTUnwrap(String(data: reencoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"sharedProfile\""))
        XCTAssertTrue(json.contains("\"platformDifferences\""))
        XCTAssertFalse(json.contains("\"platformProfile\""))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
        let targets = try XCTUnwrap(object["targets"] as? [[String: Any]])
        XCTAssertTrue(targets.allSatisfy { $0["baseProfile"] == nil })
        XCTAssertTrue(targets.allSatisfy { $0["platformDifferences"] != nil })
    }

    func testSchemaTwoTextDifferencesMigrateToStructuredItemsWithoutLosingUnknownLines() throws {
        let legacy = SchemaTwoDocument(
            schemaVersion: 2,
            sharedProfile: .defaults,
            targets: [
                SchemaTwoTarget(
                    platform: .iOS,
                    outputFileName: "ios.conf",
                    platformProfile: """
                    # keep this note
                    [General]
                    include-all-networks = true
                    custom-option = custom-value
                    #!include Extra.dconf
                    [Rule]
                    DOMAIN,should-not-survive.example,DIRECT
                    """
                )
            ],
            settings: RelaySettings(outputDirectory: "/tmp")
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let migrated = try decoder.decode(RelayDocument.self, from: encoder.encode(legacy))
        let target = try XCTUnwrap(migrated.targets.first)

        XCTAssertEqual(migrated.schemaVersion, RelayDocument.currentSchemaVersion)
        XCTAssertTrue(target.platformDifferences.contains {
            $0.section == "General" && $0.key == "include-all-networks" && $0.value == "true"
        })
        XCTAssertTrue(target.platformDifferences.contains {
            $0.section == "General" && $0.key == "custom-option" && $0.value == "custom-value"
        })
        XCTAssertTrue(target.platformDifferences.contains {
            $0.kind == .rawLine && $0.value == "#!include Extra.dconf"
        })
        XCTAssertTrue(target.platformDifferences.contains {
            $0.kind == .rawLine && $0.value == "# keep this note"
        })
        XCTAssertFalse(target.platformProfile.contains("should-not-survive.example"))
    }

    func testSchemaThreeSharedProfileMigratesGeneralProxyGroupsAndAdvancedSections() throws {
        let legacyShared = SchemaThreeSharedProfile(
            outputFileName: "Shared.dconf",
            baseProfile: """
            # keep preamble
            [General]
            loglevel = info
            custom-general = value
            [Proxy]
            Home = https, proxy.example.com, 443, user, password
            # keep proxy note
            [Proxy Group]
            PROXY = select, Home, DIRECT
            [MITM]
            hostname = example.com
            [Rule]
            FINAL,DIRECT
            """
        )
        let legacy = SchemaThreeDocument(
            schemaVersion: 3,
            sharedProfile: legacyShared,
            targets: RelayPlatform.allCases.map(TargetProfile.defaults),
            settings: RelaySettings(outputDirectory: "/tmp")
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let migrated = try decoder.decode(RelayDocument.self, from: encoder.encode(legacy))
        let shared = migrated.sharedProfile

        XCTAssertEqual(migrated.schemaVersion, RelayDocument.currentSchemaVersion)
        XCTAssertEqual(shared.preamble, "# keep preamble")
        XCTAssertTrue(shared.generalOptions.contains {
            $0.key == "loglevel" && $0.value == "info"
        })
        XCTAssertTrue(shared.generalOptions.contains {
            $0.key == "custom-general" && $0.value == "value"
        })
        XCTAssertEqual(shared.proxies.first?.name, "Home")
        XCTAssertEqual(shared.proxies.first?.type, "https")
        XCTAssertEqual(shared.proxies.first?.parameters, "proxy.example.com, 443, user, password")
        XCTAssertTrue(shared.proxies.contains {
            $0.kind == .rawLine && $0.parameters == "# keep proxy note"
        })
        XCTAssertEqual(shared.proxyGroups.first?.name, "PROXY")
        XCTAssertEqual(shared.proxyGroups.first?.type, "select")
        XCTAssertEqual(shared.proxyGroups.first?.parameters, "Home, DIRECT")
        XCTAssertTrue(shared.advancedProfile.contains("[MITM]"))
        XCTAssertTrue(shared.baseProfile.contains("[General]\nloglevel = info"))
        XCTAssertTrue(shared.baseProfile.contains("[Proxy]\nHome = https"))
        XCTAssertTrue(shared.baseProfile.contains("[Proxy Group]\nPROXY = select"))
        XCTAssertTrue(shared.baseProfile.contains("[MITM]\nhostname = example.com"))

        let reencoded = try encoder.encode(migrated)
        let json = try XCTUnwrap(String(data: reencoded, encoding: .utf8))
        XCTAssertTrue(json.contains("\"generalOptions\""))
        XCTAssertTrue(json.contains("\"proxies\""))
        XCTAssertTrue(json.contains("\"proxyGroups\""))
        XCTAssertTrue(json.contains("\"advancedProfile\""))
        XCTAssertFalse(json.contains("\"baseProfile\""))
    }
}

private struct LegacyDocument: Encodable {
    var schemaVersion: Int
    var sources: [RuleSource]
    var targets: [LegacyTarget]
    var settings: RelaySettings
    var history: [UpdateRecord]
}

private struct LegacyTarget: Encodable {
    var platform: RelayPlatform
    var isEnabled = true
    var outputFileName: String
    var finalPolicy = "DIRECT"
    var baseProfile: String
    var lastGeneratedAt: Date?
    var lastRuleCount = 0
    var lastValidationMessage: String?
}

private struct SchemaTwoDocument: Encodable {
    var schemaVersion: Int
    var sources: [RuleSource] = []
    var sharedProfile: SharedProfile
    var targets: [SchemaTwoTarget]
    var settings: RelaySettings
    var history: [UpdateRecord] = []
}

private struct SchemaTwoTarget: Encodable {
    var platform: RelayPlatform
    var isEnabled = true
    var outputFileName: String
    var finalPolicy = "DIRECT"
    var platformProfile: String
    var lastGeneratedAt: Date?
    var lastRuleCount = 0
    var lastValidationMessage: String?
}

private struct SchemaThreeDocument: Encodable {
    var schemaVersion: Int
    var sources: [RuleSource] = []
    var sharedProfile: SchemaThreeSharedProfile
    var targets: [TargetProfile]
    var settings: RelaySettings
    var history: [UpdateRecord] = []
}

private struct SchemaThreeSharedProfile: Encodable {
    var outputFileName: String
    var baseProfile: String
    var lastGeneratedAt: Date?
    var lastValidationMessage: String?
}
