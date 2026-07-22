import Foundation

public struct SharedProfile: Codable, Hashable, Sendable {
    public var outputFileName: String
    public var preamble: String
    public var generalOptions: [ProfileDifferenceItem]
    public var proxies: [ProxyDefinition]
    public var proxyGroups: [ProxyDefinition]
    public var advancedProfile: String
    public var lastGeneratedAt: Date?
    public var lastValidationMessage: String?

    public var baseProfile: String {
        get {
            let generalItems = generalOptions.filter {
                $0.normalizedSection.caseInsensitiveCompare("General") == .orderedSame
            }
            let renderedGeneral = ProfileDifferenceCodec.render(generalItems)
            let advanced = LegacyProfileParts(advancedProfile).removingSections(
                named: ["general", "proxy", "proxy group", "rule"]
            )
            let blocks = [
                preamble.trimmingCharacters(in: .whitespacesAndNewlines),
                renderedGeneral.isEmpty ? "[General]" : renderedGeneral.trimmingCharacters(in: .newlines),
                ProxyDefinitionCodec.render(section: "Proxy", items: proxies)
                    .trimmingCharacters(in: .newlines),
                ProxyDefinitionCodec.render(section: "Proxy Group", items: proxyGroups)
                    .trimmingCharacters(in: .newlines),
                advanced.trimmingCharacters(in: .whitespacesAndNewlines),
                "[Rule]\n# 此段由 Surge Shallow 自动生成。"
            ]
            return blocks
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .newlines) + "\n"
        }
        set { importLegacyBaseProfile(newValue) }
    }

    public init(
        outputFileName: String = "Surge-Profile-Relay-Shared.dconf",
        baseProfile: String,
        lastGeneratedAt: Date? = nil,
        lastValidationMessage: String? = nil
    ) {
        self.outputFileName = Self.sanitizedFileName(outputFileName)
        preamble = ""
        generalOptions = []
        proxies = []
        proxyGroups = []
        advancedProfile = ""
        self.lastGeneratedAt = lastGeneratedAt
        self.lastValidationMessage = lastValidationMessage
        importLegacyBaseProfile(baseProfile)
    }

    public init(
        outputFileName: String = "Surge-Profile-Relay-Shared.dconf",
        preamble: String,
        generalOptions: [ProfileDifferenceItem],
        proxies: [ProxyDefinition],
        proxyGroups: [ProxyDefinition],
        advancedProfile: String,
        lastGeneratedAt: Date? = nil,
        lastValidationMessage: String? = nil
    ) {
        self.outputFileName = Self.sanitizedFileName(outputFileName)
        self.preamble = preamble
        self.generalOptions = generalOptions
        self.proxies = proxies
        self.proxyGroups = proxyGroups
        self.advancedProfile = advancedProfile
        self.lastGeneratedAt = lastGeneratedAt
        self.lastValidationMessage = lastValidationMessage
    }

    public static var defaults: SharedProfile {
        SharedProfile(
            preamble: commonOptionsCommentTemplate,
            generalOptions: [
                ProfileDifferenceItem(section: "General", key: "loglevel", value: "notify"),
                ProfileDifferenceItem(
                    section: "General",
                    key: "dns-server",
                    value: "system, 1.1.1.1, 8.8.8.8"
                )
            ],
            proxies: [],
            proxyGroups: [
                ProxyDefinition(name: "PROXY", type: "select", parameters: "DIRECT")
            ],
            advancedProfile: ""
        )
    }

    public static let reusableSections = [
        "Host", "MITM", "Script", "URL Rewrite", "Header Rewrite",
        "Body Rewrite", "Map Local", "SSID Setting", "Panel"
    ]

    public static var commonOptionsCommentTemplate: String {
        """
        # Surge Shallow 公共配置
        # 根据 Surge 官方 Detached Profile Section 机制，由 macOS 与 iOS Profile 共同引用。
        # [General]、[Proxy] 与 [Proxy Group] 由应用中的结构化表单生成。
        # [Rule] 由 Relay 自动生成，请勿在此手工维护规则。
        """
    }

    public static var editorPlaceholder: String {
        """
        # 在这里填写 General、Proxy、Proxy Group 和 Rule 以外的高级公共段。
        # 可用段：\(reusableSections.map { "[\($0)]" }.joined(separator: "、"))
        # 例如：
        [Host]
        example.internal = 192.0.2.1

        [MITM]
        hostname = example.com
        """
    }

    private enum CodingKeys: String, CodingKey {
        case outputFileName
        case preamble
        case generalOptions
        case proxies
        case proxyGroups
        case advancedProfile
        case baseProfile
        case lastGeneratedAt
        case lastValidationMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputFileName = Self.sanitizedFileName(
            try container.decodeIfPresent(String.self, forKey: .outputFileName)
                ?? "Surge-Profile-Relay-Shared.dconf"
        )
        lastGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .lastGeneratedAt)
        lastValidationMessage = try container.decodeIfPresent(String.self, forKey: .lastValidationMessage)
        preamble = ""
        generalOptions = []
        proxies = []
        proxyGroups = []
        advancedProfile = ""

        if container.contains(.generalOptions)
            || container.contains(.proxies)
            || container.contains(.proxyGroups)
            || container.contains(.advancedProfile) {
            preamble = try container.decodeIfPresent(String.self, forKey: .preamble) ?? ""
            generalOptions = try container.decodeIfPresent(
                [ProfileDifferenceItem].self,
                forKey: .generalOptions
            ) ?? []
            proxies = try container.decodeIfPresent([ProxyDefinition].self, forKey: .proxies) ?? []
            proxyGroups = try container.decodeIfPresent(
                [ProxyDefinition].self,
                forKey: .proxyGroups
            ) ?? []
            advancedProfile = try container.decodeIfPresent(String.self, forKey: .advancedProfile) ?? ""
        } else {
            importLegacyBaseProfile(
                try container.decodeIfPresent(String.self, forKey: .baseProfile) ?? ""
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputFileName, forKey: .outputFileName)
        try container.encode(preamble, forKey: .preamble)
        try container.encode(generalOptions, forKey: .generalOptions)
        try container.encode(proxies, forKey: .proxies)
        try container.encode(proxyGroups, forKey: .proxyGroups)
        try container.encode(advancedProfile, forKey: .advancedProfile)
        try container.encodeIfPresent(lastGeneratedAt, forKey: .lastGeneratedAt)
        try container.encodeIfPresent(lastValidationMessage, forKey: .lastValidationMessage)
    }

    public static func sanitizedFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>,\n\r")
        let parts = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        let base = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "Surge-Profile-Relay-Shared" : base
        return name.lowercased().hasSuffix(".dconf") ? name : "\(name).dconf"
    }

    public var configurationIssues: [String] {
        var issues: [String] = []
        for item in generalOptions {
            guard item.isValid,
                  item.normalizedSection.caseInsensitiveCompare("General") == .orderedSame else {
                issues.append("General 中存在未填写完整或不安全的配置项。")
                continue
            }
            guard let descriptor = ProfileOptionCatalog.descriptor(
                section: "General",
                key: item.key
            ) else { continue }
            if descriptor.scope != .common {
                issues.append("General 公共配置不能使用平台专属项 \(descriptor.key)。")
            }
            if case .port = descriptor.valueKind,
               !(Int(item.value).map { (1...65_535).contains($0) } ?? false) {
                issues.append("\(descriptor.key) 必须是 1 到 65535 的端口。")
            }
            if case .number = descriptor.valueKind, Double(item.value) == nil {
                issues.append("\(descriptor.key) 必须是有效数字。")
            }
        }

        let generalKeys = generalOptions.compactMap { item -> String? in
            guard item.kind == .keyValue else { return nil }
            return item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if Set(generalKeys).count != generalKeys.count {
            issues.append("General 配置键不能重复。")
        }

        let definitions = proxies + proxyGroups
        if definitions.contains(where: { !$0.isValid }) {
            issues.append("Proxy 或策略组中存在未填写完整或不安全的定义。")
        }
        if definitions.contains(where: {
            $0.kind == .definition
                && $0.parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            issues.append("Proxy 与策略组的参数不能为空。")
        }
        let names = definitions.compactMap { item -> String? in
            guard item.kind == .definition else { return nil }
            return item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if Set(names).count != names.count {
            issues.append("Proxy 与策略组名称不能重复。")
        }

        for section in ["General", "Proxy", "Proxy Group", "Rule"] {
            let escaped = NSRegularExpression.escapedPattern(for: section)
            if advancedProfile.range(
                of: "(?im)^\\s*\\[\(escaped)\\]\\s*$",
                options: .regularExpression
            ) != nil {
                issues.append("高级公共段不能再次包含 [\(section)]。")
            }
        }
        return Array(Set(issues)).sorted()
    }

    private mutating func importLegacyBaseProfile(_ profile: String) {
        let parsed = LegacyProfileParts(profile)
        preamble = parsed.renderedPreamble
        generalOptions = ProfileDifferenceCodec.parse(profile).filter {
            $0.normalizedSection.caseInsensitiveCompare("General") == .orderedSame
        }
        proxies = ProxyDefinitionCodec.parse(profile: profile, section: "Proxy")
        proxyGroups = ProxyDefinitionCodec.parse(profile: profile, section: "Proxy Group")
        advancedProfile = parsed.renderedSections(excluding: [
            "general", "proxy", "proxy group", "rule"
        ])
    }

    static func migratingLegacyTargets(_ targets: inout [TargetProfile]) -> SharedProfile {
        guard targets.count > 1 else {
            for index in targets.indices {
                targets[index].platformProfile = LegacyProfileParts(targets[index].platformProfile)
                    .removingSections(named: ["rule"])
            }
            return SharedProfile(baseProfile: "[Rule]\n")
        }

        let parsed = targets.map { LegacyProfileParts($0.platformProfile) }
        let first = parsed[0]
        let commonNames = first.sections.compactMap { section -> String? in
            guard section.normalizedName != "rule" else { return nil }
            let matching = parsed.compactMap { $0.uniqueSection(named: section.normalizedName) }
            guard matching.count == parsed.count,
                  matching.dropFirst().allSatisfy({ $0.normalizedContent == section.normalizedContent }) else {
                return nil
            }
            return section.normalizedName
        }
        let commonSet = Set(commonNames)
        var sharedBlocks = first.sections
            .filter { commonSet.contains($0.normalizedName) }
            .map(\.rawContent)
        sharedBlocks.append("[Rule]")

        for index in targets.indices {
            targets[index].platformProfile = parsed[index]
                .removingSections(named: commonSet.union(["rule"]))
        }
        return SharedProfile(baseProfile: sharedBlocks.joined(separator: "\n\n") + "\n")
    }
}

private struct LegacyProfileSection {
    var normalizedName: String
    var rawContent: String

    var normalizedContent: String {
        rawContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LegacyProfileParts {
    var preamble: [String]
    var sections: [LegacyProfileSection]

    init(_ content: String) {
        let lines = content
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var preamble: [String] = []
        var sections: [LegacyProfileSection] = []
        var currentName: String?
        var currentLines: [String] = []

        func finishSection() {
            guard let currentName else { return }
            sections.append(LegacyProfileSection(
                normalizedName: currentName,
                rawContent: currentLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            ))
        }

        for line in lines {
            if let name = Self.sectionName(of: line) {
                finishSection()
                currentName = name
                currentLines = [line]
            } else if currentName == nil {
                preamble.append(line)
            } else {
                currentLines.append(line)
            }
        }
        finishSection()
        self.preamble = preamble
        self.sections = sections
    }

    func uniqueSection(named name: String) -> LegacyProfileSection? {
        let matches = sections.filter { $0.normalizedName == name }
        return matches.count == 1 ? matches[0] : nil
    }

    var renderedPreamble: String {
        preamble
            .filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#!MANAGED-CONFIG") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func renderedSections(excluding names: Set<String>) -> String {
        sections
            .filter { !names.contains($0.normalizedName) }
            .map(\.rawContent)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingSections(named names: Set<String>) -> String {
        let retainedPreamble = preamble
            .filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#!MANAGED-CONFIG") }
        let blocks = retainedPreamble + sections
            .filter { !names.contains($0.normalizedName) }
            .flatMap { ["", $0.rawContent] }
        return blocks
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sectionName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count >= 3 else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
    }
}
