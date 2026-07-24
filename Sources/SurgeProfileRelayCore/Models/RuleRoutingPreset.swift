import Foundation

public enum RuleRoutingPreset: String, CaseIterable, Codable, Identifiable, Sendable {
  case comprehensiveWhitelist
  case comprehensiveBlacklist
  case domesticWhitelist
  case domesticBlacklist

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .comprehensiveWhitelist: "整体白名单"
    case .comprehensiveBlacklist: "整体黑名单"
    case .domesticWhitelist: "国内白名单"
    case .domesticBlacklist: "国内黑名单"
    }
  }

  public var shortDetail: String {
    switch self {
    case .comprehensiveWhitelist:
      "已知本地与国内流量直连，其余默认代理"
    case .comprehensiveBlacklist:
      "广泛匹配境外与受限流量，其余默认直连"
    case .domesticWhitelist:
      "仅确认属于中国大陆的流量直连，其余代理"
    case .domesticBlacklist:
      "仅高可信境外与受限流量代理，其余直连"
    }
  }

  public var detail: String {
    switch self {
    case .comprehensiveWhitelist:
      "适合代理线路稳定、流量充足的场景。综合 Loyalsoldier 与 Sukka 的本地、Apple、iCloud、国内、全球及 IP 规则；未命中规则的连接使用所选代理策略。"
    case .comprehensiveBlacklist:
      "适合希望尽量直连、节省代理流量的场景。使用较广的境外顶级域名、GFW、全球与 Telegram 规则；只有命中这些规则的连接才使用所选代理策略。"
    case .domesticWhitelist:
      "严格确认国内流量后才直连。使用国内域名、直连域名、中国大陆 IPv4 与本地网络规则；所有未知流量使用所选代理策略。"
    case .domesticBlacklist:
      "保守识别需要代理的流量。只使用 GFW、Sukka 全球与 Telegram 等高可信规则，未命中流量保持直连。"
    }
  }

  public var finalUsesProxy: Bool {
    switch self {
    case .comprehensiveWhitelist, .domesticWhitelist: true
    case .comprehensiveBlacklist, .domesticBlacklist: false
    }
  }

  public var finalPolicyDescription: String {
    finalUsesProxy ? "未命中 → 所选代理" : "未命中 → DIRECT"
  }

  public var sourceDefinitions: [RulePresetSourceDefinition] {
    switch self {
    case .comprehensiveWhitelist:
      [
        .sukkaLANNonIP,
        .loyalPrivate,
        .loyalReject,
        .loyalICloud,
        .loyalApple,
        .sukkaDomesticNonIP,
        .sukkaDirectNonIP,
        .loyalDirect,
        .sukkaGlobalNonIP,
        .loyalProxy,
        .loyalTelegram,
        .sukkaDomesticIP,
        .loyalChinaIP,
        .sukkaLANIP,
      ]
    case .comprehensiveBlacklist:
      [
        .sukkaLANNonIP,
        .loyalPrivate,
        .loyalReject,
        .loyalTLDNotChina,
        .loyalGFW,
        .sukkaGlobalNonIP,
        .loyalProxy,
        .loyalTelegram,
        .sukkaLANIP,
      ]
    case .domesticWhitelist:
      [
        .sukkaLANNonIP,
        .loyalPrivate,
        .loyalReject,
        .sukkaDomesticNonIP,
        .sukkaDirectNonIP,
        .loyalDirect,
        .sukkaDomesticIP,
        .loyalChinaIP,
        .sukkaLANIP,
      ]
    case .domesticBlacklist:
      [
        .sukkaLANNonIP,
        .loyalPrivate,
        .loyalReject,
        .loyalGFW,
        .sukkaGlobalNonIP,
        .loyalTelegram,
        .sukkaLANIP,
      ]
    }
  }

  public static func active(in document: RelayDocument) -> Self? {
    let managedSources = document.sources.filter { $0.managedPresetID != nil }
    let presetIDs = Set(managedSources.compactMap(\.managedPresetID))
    guard presetIDs.count == 1, let id = presetIDs.first else { return nil }
    guard let preset = Self(rawValue: id) else { return nil }
    let actualEntryIDs = managedSources.compactMap(\.managedPresetEntryID)
    let expectedEntryIDs = preset.sourceDefinitions.map(\.id)
    guard actualEntryIDs.count == expectedEntryIDs.count,
      Set(actualEntryIDs) == Set(expectedEntryIDs)
    else { return nil }
    return preset
  }

  @discardableResult
  public func apply(
    to document: inout RelayDocument,
    proxyPolicy: String
  ) throws -> RulePresetApplicationResult {
    let normalizedPolicy = proxyPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedPolicy.isEmpty,
      !normalizedPolicy.contains(","),
      !normalizedPolicy.contains("\n"),
      !normalizedPolicy.contains("\r")
    else {
      throw RuleRoutingPresetError.invalidProxyPolicy
    }

    let before = document
    let previousManaged = document.sources.filter { $0.managedPresetID != nil }
    let previousByEntryID = Dictionary(
      previousManaged.compactMap { source in
        source.managedPresetEntryID.map { ($0, source) }
      },
      uniquingKeysWith: { first, _ in first }
    )
    let manualSources = document.sources.filter { $0.managedPresetID == nil }
    let managedSources = sourceDefinitions.map { definition in
      definition.makeSource(
        presetID: id,
        proxyPolicy: normalizedPolicy,
        reusing: previousByEntryID[definition.id]
      )
    }
    let reusedIDs = Set(managedSources.map(\.id))
    let removedIDs = previousManaged.map(\.id).filter { !reusedIDs.contains($0) }

    // Manual rules intentionally remain first so explicit user choices override a preset.
    document.sources = manualSources + managedSources
    let finalPolicy = finalUsesProxy ? normalizedPolicy : "DIRECT"
    for index in document.targets.indices {
      document.targets[index].finalPolicy = finalPolicy
      document.targets[index].lastValidationMessage = "一键规则集“\(title)”已应用，等待重新生成。"
    }

    return RulePresetApplicationResult(
      preset: self,
      installedSourceIDs: managedSources.map(\.id),
      removedSourceIDs: removedIDs,
      finalPolicy: finalPolicy,
      changed: before != document
    )
  }
}

public enum RulePresetProvider: String, CaseIterable, Sendable {
  case loyalsoldier
  case sukka

  public var displayName: String {
    switch self {
    case .loyalsoldier: "Loyalsoldier/surge-rules"
    case .sukka: "ruleset.skk.moe"
    }
  }
}

public enum RulePresetRuleKind: Int, Comparable, Sendable {
  case nonIP
  case ip

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum RulePresetPolicy: Sendable {
  case direct
  case reject
  case proxy

  func resolved(proxyPolicy: String) -> String {
    switch self {
    case .direct: "DIRECT"
    case .reject: "REJECT"
    case .proxy: proxyPolicy
    }
  }
}

public struct RulePresetSourceDefinition: Identifiable, Sendable {
  public var id: String
  public var name: String
  public var provider: RulePresetProvider
  public var url: String
  public var policy: RulePresetPolicy
  public var kind: RulePresetRuleKind
  public var options: Set<RuleSourceRulesetOption>

  public init(
    id: String,
    name: String,
    provider: RulePresetProvider,
    url: String,
    policy: RulePresetPolicy,
    kind: RulePresetRuleKind = .nonIP,
    options: Set<RuleSourceRulesetOption> = []
  ) {
    self.id = id
    self.name = name
    self.provider = provider
    self.url = url
    self.policy = policy
    self.kind = kind
    self.options = options
  }

  func makeSource(
    presetID: String,
    proxyPolicy: String,
    reusing existing: RuleSource?
  ) -> RuleSource {
    RuleSource(
      id: existing?.id ?? UUID(),
      name: "\(name) · \(provider.displayName)",
      url: url,
      format: .surgeRuleset,
      policy: policy.resolved(proxyPolicy: proxyPolicy),
      preservesSourcePolicy: false,
      rulesetOptions: options,
      outputMode: .remoteReference,
      isEnabled: true,
      platforms: Set(RelayPlatform.allCases),
      createdAt: existing?.createdAt ?? .now,
      managedPresetID: presetID,
      managedPresetEntryID: id
    )
  }
}

public struct RulePresetApplicationResult: Sendable {
  public var preset: RuleRoutingPreset
  public var installedSourceIDs: [UUID]
  public var removedSourceIDs: [UUID]
  public var finalPolicy: String
  public var changed: Bool

  public init(
    preset: RuleRoutingPreset,
    installedSourceIDs: [UUID],
    removedSourceIDs: [UUID],
    finalPolicy: String,
    changed: Bool
  ) {
    self.preset = preset
    self.installedSourceIDs = installedSourceIDs
    self.removedSourceIDs = removedSourceIDs
    self.finalPolicy = finalPolicy
    self.changed = changed
  }
}

public enum RuleRoutingPresetError: LocalizedError, Sendable {
  case invalidProxyPolicy

  public var errorDescription: String? {
    switch self {
    case .invalidProxyPolicy:
      "代理策略不能为空，也不能包含逗号或换行。"
    }
  }
}

extension RulePresetSourceDefinition {
  private static let loyalBase =
    "https://cdn.jsdelivr.net/gh/Loyalsoldier/surge-rules@release/ruleset"
  private static let sukkaBase = "https://ruleset.skk.moe/List"

  static let sukkaLANNonIP = Self(
    id: "sukka-lan-non-ip",
    name: "本地网络域名",
    provider: .sukka,
    url: "\(sukkaBase)/non_ip/lan.conf",
    policy: .direct
  )
  static let loyalPrivate = Self(
    id: "loyal-private",
    name: "私有网络",
    provider: .loyalsoldier,
    url: "\(loyalBase)/private.txt",
    policy: .direct
  )
  static let loyalReject = Self(
    id: "loyal-reject",
    name: "广告与跟踪拦截",
    provider: .loyalsoldier,
    url: "\(loyalBase)/reject.txt",
    policy: .reject
  )
  static let loyalICloud = Self(
    id: "loyal-icloud",
    name: "iCloud 中国大陆直连",
    provider: .loyalsoldier,
    url: "\(loyalBase)/icloud.txt",
    policy: .direct
  )
  static let loyalApple = Self(
    id: "loyal-apple",
    name: "Apple 中国大陆直连",
    provider: .loyalsoldier,
    url: "\(loyalBase)/apple.txt",
    policy: .direct
  )
  static let sukkaDomesticNonIP = Self(
    id: "sukka-domestic-non-ip",
    name: "中国大陆域名",
    provider: .sukka,
    url: "\(sukkaBase)/non_ip/domestic.conf",
    policy: .direct
  )
  static let sukkaDirectNonIP = Self(
    id: "sukka-direct-non-ip",
    name: "补充直连域名",
    provider: .sukka,
    url: "\(sukkaBase)/non_ip/direct.conf",
    policy: .direct
  )
  static let loyalDirect = Self(
    id: "loyal-direct",
    name: "直连域名",
    provider: .loyalsoldier,
    url: "\(loyalBase)/direct.txt",
    policy: .direct
  )
  static let sukkaGlobalNonIP = Self(
    id: "sukka-global-non-ip",
    name: "全球域名",
    provider: .sukka,
    url: "\(sukkaBase)/non_ip/global.conf",
    policy: .proxy
  )
  static let loyalProxy = Self(
    id: "loyal-proxy",
    name: "代理域名",
    provider: .loyalsoldier,
    url: "\(loyalBase)/proxy.txt",
    policy: .proxy
  )
  static let loyalTLDNotChina = Self(
    id: "loyal-tld-not-cn",
    name: "非中国大陆顶级域名",
    provider: .loyalsoldier,
    url: "\(loyalBase)/tld-not-cn.txt",
    policy: .proxy
  )
  static let loyalGFW = Self(
    id: "loyal-gfw",
    name: "GFW 域名",
    provider: .loyalsoldier,
    url: "\(loyalBase)/gfw.txt",
    policy: .proxy
  )
  static let loyalTelegram = Self(
    id: "loyal-telegram-ip",
    name: "Telegram IP",
    provider: .loyalsoldier,
    url: "\(loyalBase)/telegramcidr.txt",
    policy: .proxy,
    kind: .ip,
    options: [.noResolve]
  )
  static let sukkaDomesticIP = Self(
    id: "sukka-domestic-ip",
    name: "中国大陆服务 IP",
    provider: .sukka,
    url: "\(sukkaBase)/ip/domestic.conf",
    policy: .direct,
    kind: .ip,
    options: [.noResolve]
  )
  static let loyalChinaIP = Self(
    id: "loyal-china-ip",
    name: "中国大陆 IPv4",
    provider: .loyalsoldier,
    url: "\(loyalBase)/cncidr.txt",
    policy: .direct,
    kind: .ip,
    options: [.noResolve]
  )
  static let sukkaLANIP = Self(
    id: "sukka-lan-ip",
    name: "本地网络 IP",
    provider: .sukka,
    url: "\(sukkaBase)/ip/lan.conf",
    policy: .direct,
    kind: .ip,
    options: [.noResolve]
  )
}
