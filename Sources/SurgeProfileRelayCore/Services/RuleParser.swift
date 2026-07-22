import Foundation

public enum RuleParsingError: LocalizedError, Sendable {
    case emptySource
    case missingRuleSection
    case noUsableRules
    case invalidPolicy(String)

    public var errorDescription: String? {
        switch self {
        case .emptySource: "规则源内容为空。"
        case .missingRuleSection: "没有找到 [Rule] 段。"
        case .noUsableRules: "没有解析到可用规则。"
        case .invalidPolicy(let policy): "策略名称包含逗号或换行，无法安全写入 Surge 规则：\(policy)"
        }
    }
}

public struct ParsedRuleSource: Sendable {
    public var sourceID: UUID
    public var sourceName: String
    public var detectedFormat: RuleSourceFormat
    public var rules: [String]
    public var warnings: [String]

    public init(
        sourceID: UUID,
        sourceName: String,
        detectedFormat: RuleSourceFormat,
        rules: [String],
        warnings: [String]
    ) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.detectedFormat = detectedFormat
        self.rules = rules
        self.warnings = warnings
    }
}

public struct MergedRules: Sendable {
    public var lines: [String]
    public var ruleCount: Int
    public var duplicateCount: Int
    public var warnings: [String]

    public init(lines: [String], ruleCount: Int, duplicateCount: Int, warnings: [String]) {
        self.lines = lines
        self.ruleCount = ruleCount
        self.duplicateCount = duplicateCount
        self.warnings = warnings
    }
}

public enum RuleParser {
    private static let policylessOptions: Set<String> = [
        "no-resolve",
        "extended-matching"
    ]

    private static let hostnamePattern = try! NSRegularExpression(
        pattern: #"^(?:\*\.)?(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$"#
    )

    public static func parse(_ content: String, for source: RuleSource) throws -> ParsedRuleSource {
        let normalized = normalize(content)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleParsingError.emptySource
        }
        guard isSafePolicyName(source.policy) else {
            throw RuleParsingError.invalidPolicy(source.policy)
        }

        let format = source.format == .automatic ? detectFormat(normalized) : source.format
        let candidates: [String]
        switch format {
        case .automatic, .surgeRuleList:
            candidates = normalized.components(separatedBy: "\n")
        case .surgeProfile:
            candidates = try extractRuleSection(from: normalized)
        case .domainList:
            candidates = normalized.components(separatedBy: "\n")
        case .clashPayload:
            candidates = extractClashPayload(from: normalized)
        }

        var warnings: [String] = []
        var rules: [String] = []
        for (offset, candidate) in candidates.enumerated() {
            let lineNumber = offset + 1
            guard let rule = normalizedRule(
                candidate,
                format: format,
                source: source,
                lineNumber: lineNumber,
                warnings: &warnings
            ) else { continue }
            rules.append(rule)
        }

        guard !rules.isEmpty else { throw RuleParsingError.noUsableRules }
        return ParsedRuleSource(
            sourceID: source.id,
            sourceName: source.name,
            detectedFormat: format,
            rules: rules,
            warnings: warnings
        )
    }

    public static func detectFormat(_ content: String) -> RuleSourceFormat {
        let normalized = normalize(content)
        if normalized.range(
            of: #"(?im)^\s*\[Rule\]\s*$"#,
            options: .regularExpression
        ) != nil {
            return .surgeProfile
        }
        if normalized.range(
            of: #"(?im)^\s*payload\s*:\s*$"#,
            options: .regularExpression
        ) != nil {
            return .clashPayload
        }

        let meaningful = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isComment($0) }
        guard !meaningful.isEmpty else { return .surgeRuleList }
        let hostnameCount = meaningful.filter { isHostname(stripYAMLDecoration($0)) }.count
        return hostnameCount * 2 >= meaningful.count ? .domainList : .surgeRuleList
    }

    public static func extractRuleSection(from profile: String) throws -> [String] {
        let lines = normalize(profile).components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { sectionName(of: $0) == "rule" }) else {
            throw RuleParsingError.missingRuleSection
        }
        let remainderStart = lines.index(after: start)
        let end = lines[remainderStart...].firstIndex(where: { sectionName(of: $0) != nil }) ?? lines.endIndex
        return Array(lines[remainderStart..<end])
    }

    public static func canonicalKey(for rule: String) -> String {
        let split = splitInlineComment(rule)
        let tokens = splitTopLevelCSV(split.body)
        guard !tokens.isEmpty else { return split.body.lowercased() }
        let type = tokens[0].uppercased()
        if type == "FINAL" { return "FINAL" }
        guard tokens.count > 1 else { return split.body.lowercased() }
        return "\(type),\(tokens[1].trimmingCharacters(in: .whitespaces).lowercased())"
    }

    public static func splitTopLevelCSV(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var escaped = false

        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "(" {
                depth += 1
                current.append(character)
            } else if character == ")" {
                depth = max(0, depth - 1)
                current.append(character)
            } else if character == "," && depth == 0 {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    private static func normalizedRule(
        _ rawLine: String,
        format: RuleSourceFormat,
        source: RuleSource,
        lineNumber: Int,
        warnings: inout [String]
    ) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !isComment(line) else { return nil }
        if format == .clashPayload {
            guard !line.lowercased().hasPrefix("payload:") else { return nil }
            line = stripYAMLDecoration(line)
        }
        if line.hasPrefix("[") && line.hasSuffix("]") { return nil }
        if line.hasPrefix("#!") { return nil }

        let comment = splitInlineComment(line)
        var body = comment.body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        if format == .domainList || (format == .clashPayload && isHostname(body)) {
            let domain = body.hasPrefix("*.") ? String(body.dropFirst(2)) : body
            body = "DOMAIN-SUFFIX,\(domain)"
        }

        var tokens = splitTopLevelCSV(body)
        guard tokens.count >= 2 else {
            warnings.append("第 \(lineNumber) 行不是有效的 Surge 规则，已忽略：\(body)")
            return nil
        }
        tokens[0] = tokens[0].uppercased()
        if tokens[0] == "FINAL" {
            warnings.append("上游 FINAL 规则已忽略；最终策略由目标 Profile 统一管理。")
            return nil
        }

        let fallbackPolicy = source.policy.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.preservesSourcePolicy {
            if tokens.count == 2 {
                guard !fallbackPolicy.isEmpty else {
                    warnings.append("第 \(lineNumber) 行缺少策略且规则源未设置回退策略，已忽略。")
                    return nil
                }
                tokens.append(fallbackPolicy)
            } else if policylessOptions.contains(tokens[2].lowercased()) {
                guard !fallbackPolicy.isEmpty else {
                    warnings.append("第 \(lineNumber) 行缺少策略且规则源未设置回退策略，已忽略。")
                    return nil
                }
                tokens.insert(fallbackPolicy, at: 2)
            }
        } else {
            guard !fallbackPolicy.isEmpty else {
                warnings.append("规则源策略为空，第 \(lineNumber) 行已忽略。")
                return nil
            }
            if tokens.count == 2 {
                tokens.append(fallbackPolicy)
            } else if policylessOptions.contains(tokens[2].lowercased()) {
                tokens.insert(fallbackPolicy, at: 2)
            } else {
                tokens[2] = fallbackPolicy
            }
        }

        let suffix = comment.suffix.map { " \($0)" } ?? ""
        return tokens.joined(separator: ",") + suffix
    }

    private static func extractClashPayload(from content: String) -> [String] {
        let lines = normalize(content).components(separatedBy: "\n")
        guard let payloadIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("payload:")
        }) else { return lines }
        return Array(lines.dropFirst(payloadIndex + 1))
    }

    private static func sectionName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count >= 3 else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func splitInlineComment(_ line: String) -> (body: String, suffix: String?) {
        let characters = Array(line)
        var quote: Character?
        var escaped = false
        for index in characters.indices {
            let character = characters[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            guard index > characters.startIndex, characters[index - 1].isWhitespace else { continue }
            let isSlashComment = character == "/"
                && index + 1 < characters.endIndex
                && characters[index + 1] == "/"
            if character == "#" || character == ";" || isSlashComment {
                let body = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
                let suffix = String(characters[index...]).trimmingCharacters(in: .whitespaces)
                return (body, suffix)
            }
        }
        return (line, nil)
    }

    private static func isComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("#") || trimmed.hasPrefix(";") || trimmed.hasPrefix("//")
    }

    private static func stripYAMLDecoration(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("-") {
            value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if value.count >= 2,
           let first = value.first,
           let last = value.last,
           (first == "'" && last == "'") || (first == "\"" && last == "\"") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func isHostname(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespaces)
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        return hostnamePattern.firstMatch(in: candidate, range: range) != nil
    }

    private static func isSafePolicyName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.contains(",")
            && !trimmed.contains("\n")
            && !trimmed.contains("\r")
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

public enum RuleMerger {
    public static func merge(
        _ parsedSources: [(source: RuleSource, parsed: ParsedRuleSource)],
        for platform: RelayPlatform
    ) -> MergedRules {
        var seen = Set<String>()
        var output: [String] = []
        var warnings: [String] = []
        var duplicates = 0
        var count = 0

        for item in parsedSources where item.source.isEnabled && item.source.platforms.contains(platform) {
            var sourceRules: [String] = []
            for rule in item.parsed.rules {
                let key = RuleParser.canonicalKey(for: rule)
                guard seen.insert(key).inserted else {
                    duplicates += 1
                    continue
                }
                sourceRules.append(rule)
            }
            guard !sourceRules.isEmpty else { continue }
            if !output.isEmpty { output.append("") }
            let safeName = item.source.name
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            output.append("# --- \(safeName) · \(sourceRules.count) 条 ---")
            output.append(contentsOf: sourceRules)
            count += sourceRules.count
            warnings.append(contentsOf: item.parsed.warnings.map { "\(item.source.name)：\($0)" })
        }

        return MergedRules(lines: output, ruleCount: count, duplicateCount: duplicates, warnings: warnings)
    }
}
