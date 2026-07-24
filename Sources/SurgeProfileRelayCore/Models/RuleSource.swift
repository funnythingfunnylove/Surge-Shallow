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

public enum RuleSourceOutputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case remoteReference
    case inlineMerged

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .remoteReference: "外部 Ruleset 引用"
        case .inlineMerged: "下载并内联合并"
        }
    }

    public var detail: String {
        switch self {
        case .remoteReference:
            "最终 Profile 只写入 RULE-SET URL，由 Surge 加载规则，文件体积最小。"
        case .inlineMerged:
            "由 Surge Shallow 下载、转换、合并并去重，再把规则正文写入 Profile。"
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

public enum RuleSourceContentOrigin: String, Codable, Sendable {
    case importedProfile
    case manual
}

public enum ManualRulePublicationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case inline
    case detachedProfile

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inline: "内联合并"
        case .detachedProfile: "独立 .dconf 引用"
        }
    }

    public var detail: String {
        switch self {
        case .inline:
            "规则正文按当前顺序合并到生成的 [Rule] 段。"
        case .detachedProfile:
            "生成独立 .dconf，并在对应 Profile 的 [Rule] 中使用 #!include 引用。"
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
    /// Missing retains compatibility with older imported Profile sources and remote sources.
    public var contentOrigin: RuleSourceContentOrigin?
    /// Manual sources may remain inline or be published as a managed detached [Rule] profile.
    /// Optional keeps existing relay.json documents source-compatible.
    public var manualPublicationMode: ManualRulePublicationMode?
    /// User-facing detached filename. The engine always uses the sanitized computed value.
    public var detachedFileName: String?
    public var format: RuleSourceFormat
    public var policy: String
    public var preservesSourcePolicy: Bool
    /// Parameters preserved on a compact RULE-SET directive or applied when the Ruleset is
    /// expanded locally.
    /// Optional keeps relay.json documents from schema v1-v5 source-compatible.
    public var rulesetOptions: Set<RuleSourceRulesetOption>?
    /// Missing means the source came from a legacy document and must retain the historical
    /// download/merge behavior. Newly created sources default to a compact remote reference.
    public var outputMode: RuleSourceOutputMode?
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
    /// Identifies sources installed by a one-click routing preset. Manual sources keep this nil.
    public var managedPresetID: String?
    /// Stable identity within the preset catalog, used to update shared entries without duplication.
    public var managedPresetEntryID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        url: String,
        embeddedContent: String? = nil,
        contentOrigin: RuleSourceContentOrigin? = nil,
        manualPublicationMode: ManualRulePublicationMode? = nil,
        detachedFileName: String? = nil,
        format: RuleSourceFormat = .automatic,
        policy: String = "PROXY",
        preservesSourcePolicy: Bool = false,
        rulesetOptions: Set<RuleSourceRulesetOption> = [],
        outputMode: RuleSourceOutputMode? = .remoteReference,
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
        lastError: String? = nil,
        managedPresetID: String? = nil,
        managedPresetEntryID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.embeddedContent = embeddedContent
        self.contentOrigin = contentOrigin
        self.manualPublicationMode = manualPublicationMode
        self.detachedFileName = detachedFileName
        self.format = format
        self.policy = policy
        self.preservesSourcePolicy = preservesSourcePolicy
        self.rulesetOptions = rulesetOptions
        self.outputMode = outputMode
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
        self.managedPresetID = managedPresetID
        self.managedPresetEntryID = managedPresetEntryID
    }

    public var hostDisplayName: String {
        if isManual { return "手工规则 · 随管理配置同步" }
        if embeddedContent != nil { return "Profile 内嵌规则" }
        return URL(string: url)?.host ?? url
    }

    public var isEmbedded: Bool {
        embeddedContent != nil
    }

    public var isManual: Bool {
        contentOrigin == .manual
    }

    public static func manual(
        name: String = "",
        content: String = "",
        policy: String = "PROXY"
    ) -> Self {
        let id = UUID()
        return Self(
            id: id,
            name: name,
            url: "",
            embeddedContent: content,
            contentOrigin: .manual,
            manualPublicationMode: .inline,
            detachedFileName: defaultDetachedFileName(for: id),
            format: .surgeRuleList,
            policy: policy,
            preservesSourcePolicy: true,
            outputMode: .inlineMerged,
            updateIntervalMinutes: 0
        )
    }

    public var resolvedManualPublicationMode: ManualRulePublicationMode {
        manualPublicationMode ?? .inline
    }

    public var publishesDetachedProfile: Bool {
        isManual && resolvedManualPublicationMode == .detachedProfile
    }

    public var resolvedDetachedFileName: String {
        Self.sanitizedDetachedFileName(
            detachedFileName ?? Self.defaultDetachedFileName(for: id),
            sourceID: id
        )
    }

    public static func defaultDetachedFileName(for sourceID: UUID) -> String {
        "Manual-Rules-\(sourceID.uuidString.prefix(8).lowercased()).dconf"
    }

    public static func sanitizedDetachedFileName(_ value: String, sourceID: UUID) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
            .union(.newlines)
        let parts = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        var base = parts
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        if base.lowercased().hasSuffix(".dconf") {
            base.removeLast(6)
        }
        base = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".- "))
        if base.isEmpty {
            base = "Manual-Rules-\(sourceID.uuidString.prefix(8).lowercased())"
        }
        if base.count > 120 {
            base = String(base.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(base).dconf"
    }

    public var resolvedOutputMode: RuleSourceOutputMode {
        // Surge Rulesets are native URL references. Surge itself owns retrieval and
        // refresh behavior; Surge Shallow only needs the URL, policy, and options.
        if !isEmbedded && format == .surgeRuleset { return .remoteReference }
        return outputMode ?? .inlineMerged
    }

    public var supportsRemoteRulesetReference: Bool {
        !isEmbedded && (format == .automatic || format == .surgeRuleset)
    }

    public var remoteRulesetDirective: String? {
        guard resolvedOutputMode == .remoteReference,
              supportsRemoteRulesetReference else { return nil }
        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPolicy = policy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteRulesetReference.isRemoteURL(normalizedURL),
              !normalizedURL.contains(","),
              !normalizedURL.contains("\n"),
              !normalizedURL.contains("\r"),
              !normalizedPolicy.isEmpty,
              !normalizedPolicy.contains(","),
              !normalizedPolicy.contains("\n"),
              !normalizedPolicy.contains("\r") else { return nil }
        let optionTokens = RuleSourceRulesetOption.allCases.compactMap { option in
            rulesetOptions?.contains(option) == true ? option.rawValue : nil
        }
        return (["RULE-SET", normalizedURL, normalizedPolicy] + optionTokens)
            .joined(separator: ",")
    }

    public func isDue(globalIntervalMinutes: Int, now: Date = .now) -> Bool {
        guard resolvedOutputMode == .inlineMerged else { return false }
        let minutes = updateIntervalMinutes > 0 ? updateIntervalMinutes : globalIntervalMinutes
        guard minutes > 0, let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= Double(minutes * 60)
    }
}
