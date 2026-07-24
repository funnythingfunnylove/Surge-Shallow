import XCTest

@testable import SurgeProfileRelayCore

final class RuleRoutingPresetTests: XCTestCase {
  func testEveryPresetCombinesBothProvidersAndKeepsNonIPBeforeIP() {
    for preset in RuleRoutingPreset.allCases {
      let providers = Set(preset.sourceDefinitions.map { $0.provider.rawValue })
      XCTAssertEqual(
        providers,
        Set(RulePresetProvider.allCases.map(\.rawValue)),
        preset.title
      )

      var reachedIPRules = false
      for definition in preset.sourceDefinitions {
        if definition.kind == .ip {
          reachedIPRules = true
        } else {
          XCTAssertFalse(reachedIPRules, "\(preset.title) 在 IP 规则后放置了 non_ip 规则")
        }
      }
    }
  }

  func testWhitelistPresetPreservesManualPriorityAndUsesProxyAsFinal() throws {
    let manual = RuleSource(
      name: "Manual override",
      url: "https://example.com/manual.list",
      format: .surgeRuleset,
      policy: "DIRECT"
    )
    var document = RelayDocument(sources: [manual])

    let result = try RuleRoutingPreset.comprehensiveWhitelist.apply(
      to: &document,
      proxyPolicy: "Main Proxy"
    )

    XCTAssertEqual(document.sources.first?.id, manual.id)
    XCTAssertEqual(result.installedSourceIDs.count, 14)
    XCTAssertEqual(document.sources.filter { $0.managedPresetID != nil }.count, 14)
    XCTAssertTrue(document.targets.allSatisfy { $0.finalPolicy == "Main Proxy" })
    XCTAssertEqual(
      RuleRoutingPreset.active(in: document),
      .comprehensiveWhitelist
    )
    XCTAssertTrue(
      document.sources.dropFirst().allSatisfy {
        $0.remoteRulesetDirective?.hasPrefix("RULE-SET,https://") == true
      })
  }

  func testBlacklistPresetUsesDirectAsFinalButSelectedPolicyForProxyRules() throws {
    var document = RelayDocument()

    let result = try RuleRoutingPreset.comprehensiveBlacklist.apply(
      to: &document,
      proxyPolicy: "Fallback Group"
    )

    XCTAssertEqual(result.finalPolicy, "DIRECT")
    XCTAssertTrue(document.targets.allSatisfy { $0.finalPolicy == "DIRECT" })
    let proxyEntries = zip(
      RuleRoutingPreset.comprehensiveBlacklist.sourceDefinitions,
      document.sources
    ).filter { definition, _ in
      if case .proxy = definition.policy { return true }
      return false
    }
    XCTAssertFalse(proxyEntries.isEmpty)
    XCTAssertTrue(proxyEntries.allSatisfy { $0.1.policy == "Fallback Group" })
  }

  func testReapplyingPresetIsIdempotentAndKeepsStableSourceIDs() throws {
    var document = RelayDocument()
    _ = try RuleRoutingPreset.domesticWhitelist.apply(to: &document, proxyPolicy: "PROXY")
    let firstDocument = document
    let firstIDs = document.sources.map(\.id)

    let second = try RuleRoutingPreset.domesticWhitelist.apply(
      to: &document,
      proxyPolicy: "PROXY"
    )

    XCTAssertFalse(second.changed)
    XCTAssertEqual(document, firstDocument)
    XCTAssertEqual(document.sources.map(\.id), firstIDs)
    XCTAssertTrue(second.removedSourceIDs.isEmpty)
  }

  func testSwitchingPresetRemovesOnlyObsoleteManagedEntries() throws {
    let manual = RuleSource(
      name: "Manual",
      url: "https://example.com/manual.list",
      format: .surgeRuleset
    )
    var document = RelayDocument(sources: [manual])
    _ = try RuleRoutingPreset.comprehensiveWhitelist.apply(to: &document, proxyPolicy: "PROXY")
    let sharedEntryID = try XCTUnwrap(
      document.sources.first { $0.managedPresetEntryID == "sukka-lan-non-ip" }?.id
    )

    let result = try RuleRoutingPreset.domesticBlacklist.apply(
      to: &document,
      proxyPolicy: "PROXY"
    )

    XCTAssertEqual(document.sources.first?.id, manual.id)
    XCTAssertEqual(
      document.sources.first { $0.managedPresetEntryID == "sukka-lan-non-ip" }?.id,
      sharedEntryID
    )
    XCTAssertFalse(result.removedSourceIDs.isEmpty)
    XCTAssertTrue(
      document.sources.dropFirst().allSatisfy {
        $0.managedPresetID == RuleRoutingPreset.domesticBlacklist.id
      })

    document.sources.removeLast()
    XCTAssertNil(RuleRoutingPreset.active(in: document))
  }

  func testPresetRejectsUnsafeProxyPolicy() {
    var document = RelayDocument()
    let before = document

    XCTAssertThrowsError(
      try RuleRoutingPreset.domesticBlacklist.apply(
        to: &document,
        proxyPolicy: "PROXY\nFINAL,REJECT"
      )
    )
    XCTAssertEqual(document, before)
  }

  func testAllPresetProfilesPassInstalledSurgeCLI() async throws {
    guard SurgeCLIValidator.executableURL != nil else {
      throw XCTSkip("Surge CLI is not installed")
    }
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "SurgePresetCheck-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for preset in RuleRoutingPreset.allCases {
      var document = RelayDocument()
      let result = try preset.apply(to: &document, proxyPolicy: "PROXY")
      let merged = RuleMerger.merge(
        document.sources.map { (source: $0, parsed: Optional<ParsedRuleSource>.none) },
        for: .macOS
      )
      let sharedFileName = "\(preset.id)-Shared.dconf"
      let shared = try ProfileAssembler.assembleShared(
        baseProfile: document.sharedProfile.baseProfile,
        sharedRules: merged,
        finalPolicy: result.finalPolicy,
        generatedAt: Date(timeIntervalSince1970: 0)
      )
      try Data(shared.content.utf8).write(to: directory.appending(path: sharedFileName))

      for platform in RelayPlatform.allCases {
        let profile = try ProfileAssembler.assemblePlatform(
          platformProfile: "",
          sharedFileName: sharedFileName,
          sharedSections: shared.sections,
          mergedRules: merged,
          finalPolicy: result.finalPolicy,
          generatedAt: Date(timeIntervalSince1970: 0)
        )
        let url = directory.appending(path: "\(preset.id)-\(platform.rawValue).conf")
        try Data(profile.content.utf8).write(to: url)
        let validation = await SurgeCLIValidator.validate(profileAt: url)
        XCTAssertTrue(
          validation.isValid,
          "\(preset.title) · \(platform.displayName)：\(validation.message)"
        )
      }
    }
  }
}
