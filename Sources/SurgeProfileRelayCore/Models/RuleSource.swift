import Foundation

public enum RuleSourceFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case surgeRuleList
    case surgeRuleset
    case surgeProfile
    case domainList
    case clashPayload

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动识别"
        case .surgeRuleList: "Surge 规则列表"
        case .surgeRuleset: "Surge 远端 Ruleset"
        case .surgeProfile: "Surge Profile"
        case .domainList: "域名列表"
        case .clashPayload: "Clash payload"
        }
    }
}

public enum RuleSourceRulesetOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case noResolve = "no-resolve"
    case extendedMatching = "extended-matching"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .noResolve: "跳过 DNS 解析"
        case .extendedMatching: "扩展域名匹配"
        }
    }

    public var detail: String {
        switch self {
        case .noResolve: "为 IP-CIDR、IP-CIDR6 与 GEOIP 规则附加 no-resolve。"
        case .extendedMatching: "让域名规则同时匹配 SNI 与 HTTP Host / :authority。"
        }
    }
}

public struct RemoteRulesetReference: Hashable, Sendable {
    public var url: String
    public var policy: String
    public var options: Set<RuleSourceRulesetOption>

    public init(url: String, policy: String, options: Set<RuleSourceRulesetOption> = []) {
        self.url = url
        self.policy = policy
        self.options = options
    }

    public static func parse(_ value: String) -> RemoteRulesetReference? {
        let tokens = RuleParser.splitTopLevelCSV(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard tokens.count >= 3,
              tokens[0].caseInsensitiveCompare("RULE-SET") == .orderedSame,
              isRemoteURL(tokens[1]) else { return nil }
        let policy = tokens[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !policy.isEmpty else { return nil }
        let options = Set(tokens.dropFirst(3).compactMap { token in
            RuleSourceRulesetOption(rawValue: token.lowercased())
        })
        return RemoteRulesetReference(url: tokens[1], policy: policy, options: options)
    }

    public static func isRemoteURL(_ value: String) -> Bool {
        guard let components = URLComponents(
            string: value.trimmingCharacters(in: .whitespacesAndNewlines)
        ), let scheme = components.scheme?.lowercased() else { return false }
        return ["https", "http"].contains(scheme) && components.host != nil
    }
}

public enum RuleSourceState: String, Codable, Sendable {
    case never
    case checking
    case current
    case updated
    case staleCache
    case failed

    public var displayName: String {
        switch self {
        case .never: "尚未更新"
        case .checking: "正在检查"
        case .current: "已是最新"
        case .updated: "已更新"
        case .staleCache: "使用缓存"
        case .failed: "更新失败"
        }
    }
}

public struct RuleSource: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    /// Rules captured from an imported local Profile. Keeping them in relay.json makes the
    /// migrated configuration portable to every Mac that shares the management document.
    public var embeddedContent: String?
    public var format: RuleSourceFormat
    public var policy: String
    public var preservesSourcePolicy: Bool
    /// Parameters applied when a policy-less external Surge Ruleset is expanded locally.
    /// Optional keeps relay.json documents from schema v1-v5 source-compatible.
    public var rulesetOptions: Set<RuleSourceRulesetOption>?
    public var isEnabled: Bool
    public var platforms: Set<RelayPlatform>
    public var updateIntervalMinutes: Int
    public var createdAt: Date
    public var lastCheckedAt: Date?
    public var lastUpdatedAt: Date?
    public var etag: String?
    public var lastModified: String?
    public var contentHash: String?
    public var lastRuleCount: Int
    public var state: RuleSourceState
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        embeddedContent: String? = nil,
        format: RuleSourceFormat = .automatic,
        policy: String = "PROXY",
        preservesSourcePolicy: Bool = false,
        rulesetOptions: Set<RuleSourceRulesetOption> = [],
        isEnabled: Bool = true,
        platforms: Set<RelayPlatform> = Set(RelayPlatform.allCases),
        updateIntervalMinutes: Int = 0,
        createdAt: Date = .now,
        lastCheckedAt: Date? = nil,
        lastUpdatedAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        contentHash: String? = nil,
        lastRuleCount: Int = 0,
        state: RuleSourceState = .never,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.embeddedContent = embeddedContent
        self.format = format
        self.policy = policy
        self.preservesSourcePolicy = preservesSourcePolicy
        self.rulesetOptions = rulesetOptions
        self.isEnabled = isEnabled
        self.platforms = platforms
        self.updateIntervalMinutes = updateIntervalMinutes
        self.createdAt = createdAt
        self.lastCheckedAt = lastCheckedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.etag = etag
        self.lastModified = lastModified
        self.contentHash = contentHash
        self.lastRuleCount = lastRuleCount
        self.state = state
        self.lastError = lastError
    }

    public var hostDisplayName: String {
        if embeddedContent != nil { return "内嵌于管理配置" }
        return URL(string: url)?.host ?? url
    }

    public var isEmbedded: Bool {
        embeddedContent != nil
    }

    public func isDue(globalIntervalMinutes: Int, now: Date = .now) -> Bool {
        let minutes = updateIntervalMinutes > 0 ? updateIntervalMinutes : globalIntervalMinutes
        guard minutes > 0, let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= Double(minutes * 60)
    }
}
