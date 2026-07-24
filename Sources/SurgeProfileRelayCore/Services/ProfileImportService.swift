import Foundation

public enum ProfileImportError: LocalizedError, Sendable {
    case invalidEncoding
    case emptyProfile
    case noSections

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: "Profile 不是有效的 UTF-8 文本。"
        case .emptyProfile: "Profile 内容为空。"
        case .noSections: "没有找到 Surge Profile 配置段。"
        }
    }
}

public struct ProfileImportSummary: Sendable, Hashable {
    public var generalOptionCount: Int
    public var proxyCount: Int
    public var proxyGroupCount: Int
    public var ruleCount: Int
    public var rulesetCount: Int
    public var advancedSectionNames: [String]
    public var finalPolicy: String?
    public var includeDirectiveCount: Int

    public init(
        generalOptionCount: Int,
        proxyCount: Int,
        proxyGroupCount: Int,
        ruleCount: Int,
        rulesetCount: Int,
        advancedSectionNames: [String],
        finalPolicy: String?,
        includeDirectiveCount: Int
    ) {
        self.generalOptionCount = generalOptionCount
        self.proxyCount = proxyCount
        self.proxyGroupCount = proxyGroupCount
        self.ruleCount = ruleCount
        self.rulesetCount = rulesetCount
        self.advancedSectionNames = advancedSectionNames
        self.finalPolicy = finalPolicy
        self.includeDirectiveCount = includeDirectiveCount
    }
}

public struct ProfileImportDraft: Identifiable, Sendable {
    public var id: UUID
    public var fileName: String
    public var sharedProfile: SharedProfile
    public var platformDifferences: [RelayPlatform: [ProfileDifferenceItem]]
    /// Rule sources in their original Profile order. Consecutive inline rules become an
    /// embedded source, while every remote RULE-SET directive becomes its own URL source.
    public var importedSources: [RuleSource]
    public var finalPolicy: String?
    public var warnings: [String]
    public var summary: ProfileImportSummary

    /// Compatibility view used by callers that only need the imported inline rule text.
    public var importedRules: String {
        importedSources.compactMap(\.embeddedContent).joined(separator: "\n")
    }

    public init(
        id: UUID = UUID(),
        fileName: String,
        sharedProfile: SharedProfile,
        platformDifferences: [RelayPlatform: [ProfileDifferenceItem]],
        importedSources: [RuleSource],
        finalPolicy: String?,
        warnings: [String],
        summary: ProfileImportSummary
    ) {
        self.id = id
        self.fileName = fileName
        self.sharedProfile = sharedProfile
        self.platformDifferences = platformDifferences
        self.importedSources = importedSources
        self.finalPolicy = finalPolicy
        self.warnings = warnings
        self.summary = summary
    }
}

public enum ProfileImportService {
    public static func parse(data: Data, fileName: String) throws -> ProfileImportDraft {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ProfileImportError.invalidEncoding
        }
        return try parse(content: content, fileName: fileName)
    }

    public static func parse(content: String, fileName: String) throws -> ProfileImportDraft {
        let normalized = normalize(content)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProfileImportError.emptyProfile
        }

        let parsed = ParsedProfile(normalized)
        guard !parsed.sections.isEmpty else { throw ProfileImportError.noSections }

        var warnings: [String] = []
        let managedDirectives = parsed.preamble.filter {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("#!managed-config")
        }
        if !managedDirectives.isEmpty {
            warnings.append("已移除 #!MANAGED-CONFIG 指令；迁移后的文件改由 Surge Shallow 管理。")
        }
        let safePreamble = parsed.preamble.filter {
            !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("#!managed-config")
        }

        let generalProfile = parsed.renderedSections(named: "general")
        let generalItems = ProfileDifferenceCodec.parse(generalProfile)
        var commonGeneral: [ProfileDifferenceItem] = []
        var platformDifferences = Dictionary(
            uniqueKeysWithValues: RelayPlatform.allCases.map { ($0, [ProfileDifferenceItem]()) }
        )
        for item in generalItems {
            guard item.kind == .keyValue,
                  let descriptor = ProfileOptionCatalog.descriptor(
                    section: item.normalizedSection,
                    key: item.key
                  ) else {
                commonGeneral.append(item)
                if item.kind == .keyValue {
                    warnings.append("General 中的未知选项 \(item.key) 已作为通用项保留，请确认两端均支持。")
                }
                continue
            }
            switch descriptor.scope {
            case .common:
                commonGeneral.append(item)
            case .macOS:
                platformDifferences[.macOS, default: []].append(item)
            case .iOS:
                platformDifferences[.iOS, default: []].append(item)
            }
        }

        let parsedProxies = ProxyDefinitionCodec.parse(profile: normalized, section: "Proxy")
        let parsedProxyGroups = ProxyDefinitionCodec.parse(profile: normalized, section: "Proxy Group")
        let proxies = preservingInvalidDefinitionsAsRawLines(parsedProxies)
        let proxyGroups = preservingInvalidDefinitionsAsRawLines(parsedProxyGroups)
        if parsedProxies.contains(where: { !$0.isValid }) {
            warnings.append("Proxy 中存在无法结构化验证的行，已按原文保留；应用前请检查。")
        }
        if parsedProxyGroups.contains(where: { !$0.isValid }) {
            warnings.append("Proxy Group 中存在无法结构化验证的行，已按原文保留；应用前请检查。")
        }

        var sharedAdvancedBlocks: [String] = []
        var unknownSectionNames: [String] = []
        for section in parsed.sections where !Self.managedSectionNames.contains(section.normalizedName) {
            if SharedProfile.reusableSections.contains(where: {
                $0.caseInsensitiveCompare(section.name) == .orderedSame
            }) {
                sharedAdvancedBlocks.append(section.rendered)
            } else {
                unknownSectionNames.append(section.name)
                let items = ProfileDifferenceCodec.parse(section.rendered)
                for platform in RelayPlatform.allCases {
                    platformDifferences[platform, default: []].append(contentsOf: items)
                }
            }
        }
        if !unknownSectionNames.isEmpty {
            warnings.append("未识别段已分别保留到平台差异：\(unique(unknownSectionNames).joined(separator: "、"))。")
        }

        let ruleLines = parsed.sections
            .filter { $0.normalizedName == "rule" }
            .flatMap(\.lines)
        var finalPolicies: [String] = []
        var importedSources: [RuleSource] = []
        var embeddedRuleLines: [String] = []
        var sourceNameCounts: [String: Int] = [:]
        var unsupportedRulesetParameters = Set<String>()
        var actualRuleCount = 0
        var rulesetCount = 0
        var includeDirectiveCount = safePreamble.filter(isIncludeDirective).count

        func uniqueSourceName(_ proposedName: String) -> String {
            let key = proposedName.lowercased()
            let count = (sourceNameCounts[key] ?? 0) + 1
            sourceNameCounts[key] = count
            return count == 1 ? proposedName : "\(proposedName) · \(count)"
        }

        func flushEmbeddedRules() {
            defer { embeddedRuleLines.removeAll(keepingCapacity: true) }
            let hasUsableContent = embeddedRuleLines.contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return Self.isIncludeDirective(trimmed) || Self.isRuleLine(trimmed)
            }
            guard hasUsableContent else { return }
            let content = embeddedRuleLines.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            guard !content.isEmpty else { return }
            importedSources.append(RuleSource(
                name: uniqueSourceName("导入规则 · \(fileName)"),
                url: "embedded://imported-profile/\(importedSources.count + 1)",
                embeddedContent: content,
                contentOrigin: .importedProfile,
                format: .surgeRuleList,
                policy: "DIRECT",
                preservesSourcePolicy: true,
                outputMode: .inlineMerged,
                state: .never
            ))
        }

        for rawLine in ruleLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if isIncludeDirective(trimmed) {
                includeDirectiveCount += 1
                embeddedRuleLines.append(trimmed)
                continue
            }
            if let policy = finalPolicy(in: trimmed) {
                finalPolicies.append(policy)
                continue
            }
            let ruleBody = stripInlineComment(trimmed)
            if let reference = RemoteRulesetReference.parse(ruleBody) {
                flushEmbeddedRules()
                let parameters = RuleParser.splitTopLevelCSV(ruleBody).dropFirst(3)
                unsupportedRulesetParameters.formUnion(parameters.compactMap { parameter in
                    let normalized = parameter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !normalized.isEmpty,
                          RuleSourceRulesetOption(rawValue: normalized) == nil else { return nil }
                    return normalized
                })
                importedSources.append(RuleSource(
                    name: uniqueSourceName(rulesetSourceName(for: reference.url)),
                    url: reference.url,
                    format: .surgeRuleset,
                    policy: reference.policy,
                    preservesSourcePolicy: false,
                    rulesetOptions: reference.options,
                    outputMode: .remoteReference,
                    state: .never
                ))
                rulesetCount += 1
                continue
            }
            embeddedRuleLines.append(rawLine)
            if isRuleLine(trimmed) { actualRuleCount += 1 }
        }
        flushEmbeddedRules()
        if finalPolicies.count > 1 {
            warnings.append("发现 \(finalPolicies.count) 条 FINAL 规则，将使用最后一条的策略 \(finalPolicies.last ?? "DIRECT")。")
        }
        if parsed.sections.filter({ $0.normalizedName == "rule" }).isEmpty {
            warnings.append("Profile 中没有 [Rule] 段；迁移后不会创建内嵌规则源。")
        }
        if includeDirectiveCount > 0 {
            warnings.append("保留了 \(includeDirectiveCount) 条 #!include 指令；请确保引用文件也存在于各设备的 Surge 目录。")
        }
        if !unsupportedRulesetParameters.isEmpty {
            warnings.append(
                "远端 Ruleset 使用了当前官方文档未定义的参数：\(unsupportedRulesetParameters.sorted().joined(separator: "、"))；规则源已拆分，但这些未知参数未应用。"
            )
        }

        let fallbackPolicy = finalPolicies.last?.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in importedSources.indices where importedSources[index].isEmbedded {
            importedSources[index].policy = (fallbackPolicy?.isEmpty == false ? fallbackPolicy : nil) ?? "DIRECT"
        }

        let advancedNames = parsed.sections
            .filter { !Self.managedSectionNames.contains($0.normalizedName) }
            .map(\.name)
        let shared = SharedProfile(
            preamble: safePreamble.joined(separator: "\n").trimmingCharacters(in: .newlines),
            generalOptions: commonGeneral,
            proxies: proxies,
            proxyGroups: proxyGroups,
            advancedProfile: sharedAdvancedBlocks.joined(separator: "\n\n")
        )
        let final = finalPolicies.last
        let summary = ProfileImportSummary(
            generalOptionCount: generalItems.filter { $0.kind == .keyValue }.count,
            proxyCount: proxies.filter { $0.kind == .definition }.count,
            proxyGroupCount: proxyGroups.filter { $0.kind == .definition }.count,
            ruleCount: actualRuleCount,
            rulesetCount: rulesetCount,
            advancedSectionNames: unique(advancedNames),
            finalPolicy: final,
            includeDirectiveCount: includeDirectiveCount
        )
        return ProfileImportDraft(
            fileName: fileName,
            sharedProfile: shared,
            platformDifferences: platformDifferences,
            importedSources: importedSources,
            finalPolicy: final,
            warnings: unique(warnings),
            summary: summary
        )
    }

    public static func applying(
        _ draft: ProfileImportDraft,
        to input: RelayDocument,
        platforms: Set<RelayPlatform>
    ) -> RelayDocument {
        var document = input
        var shared = draft.sharedProfile
        shared.outputFileName = input.sharedProfile.outputFileName
        shared.lastGeneratedAt = nil
        shared.lastValidationMessage = "已从 \(draft.fileName) 迁移，等待首次生成。"
        document.sharedProfile = shared

        document.sources = draft.importedSources.map { importedSource in
            var source = importedSource
            source.platforms = platforms
            source.lastCheckedAt = nil
            source.lastUpdatedAt = nil
            source.etag = nil
            source.lastModified = nil
            source.contentHash = nil
            source.lastRuleCount = 0
            source.state = .never
            source.lastError = nil
            return source
        }

        for index in document.targets.indices where platforms.contains(document.targets[index].platform) {
            let platform = document.targets[index].platform
            document.targets[index].platformDifferences = draft.platformDifferences[platform] ?? []
            if let final = draft.finalPolicy, !final.isEmpty {
                document.targets[index].finalPolicy = final
            }
            document.targets[index].lastGeneratedAt = nil
            document.targets[index].lastRuleCount = 0
            document.targets[index].lastValidationMessage = "已从 \(draft.fileName) 迁移，等待首次生成。"
        }
        return document
    }

    private static let managedSectionNames: Set<String> = ["general", "proxy", "proxy group", "rule"]

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func finalPolicy(in line: String) -> String? {
        let body = stripInlineComment(line)
        let tokens = RuleParser.splitTopLevelCSV(body)
        guard tokens.count >= 2, tokens[0].caseInsensitiveCompare("FINAL") == .orderedSame else {
            return nil
        }
        let policy = tokens[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return policy.isEmpty ? nil : policy
    }

    private static func isRuleLine(_ line: String) -> Bool {
        guard !line.isEmpty,
              !line.hasPrefix("#"),
              !line.hasPrefix(";"),
              !line.hasPrefix("//") else { return false }
        return RuleParser.splitTopLevelCSV(stripInlineComment(line)).count >= 2
    }

    private static func isIncludeDirective(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("#!include")
    }

    private static func stripInlineComment(_ line: String) -> String {
        var quote: Character?
        let characters = Array(line)
        for index in characters.indices {
            let character = characters[index]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            guard index > characters.startIndex, characters[index - 1].isWhitespace else { continue }
            if character == "#" || character == ";" {
                return String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            }
            if character == "/", index + 1 < characters.endIndex, characters[index + 1] == "/" {
                return String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func rulesetSourceName(for value: String) -> String {
        guard let url = URL(string: value) else { return "远端 Ruleset" }
        let components = url.pathComponents.filter { $0 != "/" }
        let rawLabel = components.suffix(2).joined(separator: "/")
        let label = rawLabel.removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let label, !label.isEmpty { return "Ruleset · \(label)" }
        if let host = url.host, !host.isEmpty { return "Ruleset · \(host)" }
        return "远端 Ruleset"
    }

    private static func preservingInvalidDefinitionsAsRawLines(
        _ definitions: [ProxyDefinition]
    ) -> [ProxyDefinition] {
        definitions.map { item in
            guard item.kind == .definition, !item.isValid else { return item }
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = item.type.trimmingCharacters(in: .whitespacesAndNewlines)
            let parameters = item.parameters.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = type + (parameters.isEmpty ? "" : ", \(parameters)")
            return .rawLine("\(name) = \(value)")
        }
    }
}

private struct ImportedProfileSection: Sendable {
    var name: String
    var lines: [String]

    var normalizedName: String { name.lowercased() }
    var rendered: String { (["[\(name)]"] + lines).joined(separator: "\n") }
}

private struct ParsedProfile: Sendable {
    var preamble: [String]
    var sections: [ImportedProfileSection]

    init(_ content: String) {
        var preamble: [String] = []
        var sections: [ImportedProfileSection] = []
        var current: ImportedProfileSection?

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = Self.sectionName(trimmed) {
                if let current { sections.append(current) }
                current = ImportedProfileSection(name: name, lines: [])
            } else if current != nil {
                current?.lines.append(line)
            } else {
                preamble.append(line)
            }
        }
        if let current { sections.append(current) }
        self.preamble = preamble
        self.sections = sections
    }

    func renderedSections(named normalizedName: String) -> String {
        sections
            .filter { $0.normalizedName == normalizedName }
            .map(\.rendered)
            .joined(separator: "\n\n")
    }

    private static func sectionName(_ line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]"), line.count >= 3 else { return nil }
        let value = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
