import Foundation

public enum RuleSourceFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case surgeRuleList
    case surgeProfile
    case domainList
    case clashPayload

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动识别"
        case .surgeRuleList: "Surge 规则列表"
        case .surgeProfile: "Surge Profile"
        case .domainList: "域名列表"
        case .clashPayload: "Clash payload"
        }
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
    public var format: RuleSourceFormat
    public var policy: String
    public var preservesSourcePolicy: Bool
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
        format: RuleSourceFormat = .automatic,
        policy: String = "PROXY",
        preservesSourcePolicy: Bool = false,
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
        self.format = format
        self.policy = policy
        self.preservesSourcePolicy = preservesSourcePolicy
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
        URL(string: url)?.host ?? url
    }

    public func isDue(globalIntervalMinutes: Int, now: Date = .now) -> Bool {
        let minutes = updateIntervalMinutes > 0 ? updateIntervalMinutes : globalIntervalMinutes
        guard minutes > 0, let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= Double(minutes * 60)
    }
}
