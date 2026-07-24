import Foundation

public struct AssembledProfile: Sendable {
    public var content: String
    public var warnings: [String]
    public var ruleCount: Int

    public init(content: String, warnings: [String], ruleCount: Int) {
        self.content = content
        self.warnings = warnings
        self.ruleCount = ruleCount
    }
}

public struct AssembledSharedProfile: Sendable {
    public var content: String
    public var warnings: [String]
    public var ruleCount: Int
    public var sections: [String]

    public init(content: String, warnings: [String], ruleCount: Int, sections: [String]) {
        self.content = content
        self.warnings = warnings
        self.ruleCount = ruleCount
        self.sections = sections
    }
}

public struct ProfileLintResult: Sendable {
    public var errors: [String]
    public var warnings: [String]

    public var isValid: Bool { errors.isEmpty }

    public init(errors: [String] = [], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }
}

public enum ProfileAssembler {
    public static let ownershipMarker = "# surge-profile-relay:managed"

    public static func manualSourceMarker(for sourceID: UUID) -> String {
        "# surge-profile-relay:manual-source=\(sourceID.uuidString.lowercased())"
    }

    public static func assembleDetachedRuleFile(
        _ file: DetachedRuleFile,
        generatedAt: Date = .now
    ) throws -> String {
        guard !file.rules.isEmpty else {
            throw RelayEngineError.invalidConfiguration(
                "独立规则文件 \(file.fileName) 没有可发布的规则。"
            )
        }
        let hasFinal = file.rules.contains { rule in
            RuleParser.splitTopLevelCSV(rule).first?.caseInsensitiveCompare("FINAL") == .orderedSame
        }
        guard !hasFinal else {
            throw RelayEngineError.invalidConfiguration(
                "独立规则文件 \(file.fileName) 不能包含 FINAL；FINAL 由目标 Profile 统一管理。"
            )
        }
        let stamp = ISO8601DateFormatter().string(from: generatedAt)
        return ([
            ownershipMarker,
            manualSourceMarker(for: file.sourceID),
            "# 手工规则：\(file.sourceName)",
            "# 生成时间：\(stamp)",
            "[Rule]"
        ] + file.rules).joined(separator: "\n") + "\n"
    }

    public static func assemble(
        baseProfile: String,
        mergedRules: MergedRules,
        finalPolicy: String,
        generatedAt: Date = .now
    ) throws -> AssembledProfile {
        let normalized = normalize(baseProfile)
        var lines = normalized.components(separatedBy: "\n")
        var warnings = mergedRules.warnings

        let managedCount = lines.filter {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#!MANAGED-CONFIG")
        }.count
        if managedCount > 0 {
            lines.removeAll {
                $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#!MANAGED-CONFIG")
            }
            warnings.append("已移除基础配置中的 #!MANAGED-CONFIG，避免生成文件被远端覆盖。")
        }

        let final = finalPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty,
              !final.contains(","),
              !final.contains("\n"),
              !final.contains("\r") else {
            throw RelayEngineError.invalidConfiguration("FINAL 策略不能为空，也不能包含逗号或换行。")
        }

        let stamp = ISO8601DateFormatter().string(from: generatedAt)
        let generatedRuleSection = [
            "[Rule]",
            ownershipMarker,
            "# 此段由 Surge Shallow 自动生成，请在应用中修改规则源。",
            "# 生成时间：\(stamp)"
        ] + mergedRules.lines + ["", "FINAL,\(final)"]

        if let start = lines.firstIndex(where: { sectionName(of: $0) == "rule" }) {
            let contentStart = lines.index(after: start)
            let end = lines[contentStart...].firstIndex(where: { sectionName(of: $0) != nil }) ?? lines.endIndex
            lines.replaceSubrange(start..<end, with: generatedRuleSection)
        } else {
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                lines.removeLast()
            }
            if !lines.isEmpty { lines.append("") }
            lines.append(contentsOf: generatedRuleSection)
            warnings.append("基础配置没有 [Rule] 段，已自动创建。")
        }

        let content = lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        let lint = lint(content)
        guard lint.isValid else {
            throw RelayEngineError.invalidProfile(lint.errors.joined(separator: "；"))
        }
        warnings.append(contentsOf: lint.warnings)
        return AssembledProfile(content: content, warnings: warnings, ruleCount: mergedRules.ruleCount)
    }

    public static func assembleShared(
        baseProfile: String,
        sharedRules: MergedRules?,
        finalPolicy: String?,
        generatedAt: Date = .now
    ) throws -> AssembledSharedProfile {
        let sanitized = sanitizeImportedProfile(baseProfile)
        var parsed = ParsedProfile(sanitized.content)
        var warnings = sanitized.warnings
        let removedRules = parsed.sections.filter { $0.normalizedName == "rule" }
        parsed.sections.removeAll { $0.normalizedName == "rule" }
        if removedRules.count > 1 {
            warnings.append("公共配置包含多个 [Rule] 段，已统一替换为自动生成段。")
        }

        var ruleCount = 0
        if let sharedRules {
            guard let finalPolicy else {
                throw RelayEngineError.invalidConfiguration("共享 [Rule] 缺少 FINAL 策略。")
            }
            let ruleSection = try generatedRuleSection(
                mergedRules: sharedRules,
                finalPolicy: finalPolicy,
                generatedAt: generatedAt
            )
            parsed.sections.append(ParsedSection(
                header: "[Rule]",
                normalizedName: "rule",
                lines: Array(ruleSection.dropFirst())
            ))
            ruleCount = sharedRules.ruleCount
            warnings.append(contentsOf: sharedRules.warnings)
        } else {
            parsed.preamble.removeAll { $0.trimmingCharacters(in: .whitespaces) == ownershipMarker }
            parsed.preamble.insert(ownershipMarker, at: 0)
        }

        let content = parsed.rendered()
        return AssembledSharedProfile(
            content: content,
            warnings: warnings,
            ruleCount: ruleCount,
            sections: parsed.sections.map(\.displayName)
        )
    }

    public static func assemblePlatform(
        platformProfile: String,
        sharedFileName: String,
        sharedSections: [String],
        mergedRules: MergedRules,
        finalPolicy: String,
        generatedAt: Date = .now
    ) throws -> AssembledProfile {
        let includeFileName = SharedProfile.sanitizedFileName(sharedFileName)
        let sanitized = sanitizeImportedProfile(platformProfile)
        let parsed = ParsedProfile(sanitized.content)
        var warnings = sanitized.warnings + mergedRules.warnings
        let grouped = Dictionary(grouping: parsed.sections, by: \.normalizedName)
        let duplicates = grouped.filter { $0.value.count > 1 }.keys.sorted()
        guard duplicates.isEmpty else {
            throw RelayEngineError.invalidProfile(
                "平台差异配置包含重复段：\(duplicates.joined(separator: "、"))"
            )
        }
        if grouped["rule"] != nil {
            warnings.append("平台差异中的 [Rule] 已忽略；规则由规则源和 FINAL 策略统一生成。")
        }

        let localByName = grouped.compactMapValues(\.first)
        let shared = sharedSections.map { SharedSectionReference(displayName: $0) }
        let sharedNames = Set(shared.map(\.normalizedName))
        let sharesRule = sharedNames.contains("rule")
        var outputSections: [ParsedSection] = []

        for reference in shared where reference.normalizedName != "rule" {
            let local = localByName[reference.normalizedName]
            var lines = ["#!include \(includeFileName)"]
            if let local {
                lines.append(contentsOf: local.lines.filter {
                    $0.trimmingCharacters(in: .whitespaces) != "#!include \(includeFileName)"
                })
            }
            outputSections.append(ParsedSection(
                header: local?.header ?? "[\(reference.displayName)]",
                normalizedName: reference.normalizedName,
                lines: lines
            ))
        }

        outputSections.append(contentsOf: parsed.sections.filter {
            $0.normalizedName != "rule" && !sharedNames.contains($0.normalizedName)
        })

        if sharesRule {
            outputSections.append(ParsedSection(
                header: "[Rule]",
                normalizedName: "rule",
                lines: ["#!include \(includeFileName)"]
            ))
        } else {
            let ruleSection = try generatedRuleSection(
                mergedRules: mergedRules,
                finalPolicy: finalPolicy,
                generatedAt: generatedAt
            )
            outputSections.append(ParsedSection(
                header: "[Rule]",
                normalizedName: "rule",
                lines: Array(ruleSection.dropFirst())
            ))
        }

        var preamble = parsed.preamble.filter {
            $0.trimmingCharacters(in: .whitespaces) != ownershipMarker
        }
        if sharesRule { preamble.insert(ownershipMarker, at: 0) }
        let output = ParsedProfile(preamble: preamble, sections: outputSections).rendered()
        let lint = lint(output)
        guard lint.isValid else {
            throw RelayEngineError.invalidProfile(lint.errors.joined(separator: "；"))
        }
        warnings.append(contentsOf: lint.warnings)
        return AssembledProfile(content: output, warnings: warnings, ruleCount: mergedRules.ruleCount)
    }

    public static func lint(_ profile: String) -> ProfileLintResult {
        let lines = normalize(profile).components(separatedBy: "\n")
        var errors: [String] = []
        var warnings: [String] = []
        let sections = lines.compactMap(sectionName)
        if !sections.contains("general") { warnings.append("Profile 没有 [General] 段。") }
        guard let start = lines.firstIndex(where: { sectionName(of: $0) == "rule" }) else {
            return ProfileLintResult(errors: ["Profile 没有 [Rule] 段。"], warnings: warnings)
        }
        let contentStart = lines.index(after: start)
        let end = lines[contentStart...].firstIndex(where: { sectionName(of: $0) != nil }) ?? lines.endIndex
        let rawRules = lines[contentStart..<end]
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let includesDetachedRule = rawRules.contains {
            $0.lowercased().hasPrefix("#!include ")
        }
        let rules = rawRules
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") && !$0.hasPrefix("//") }
        if includesDetachedRule && rules.isEmpty {
            if !profile.contains(ownershipMarker) {
                warnings.append("生成文件缺少 Surge Shallow 所有权标记。")
            }
            return ProfileLintResult(errors: errors, warnings: warnings)
        }
        let finalIndices = rules.indices.filter {
            RuleParser.splitTopLevelCSV(rules[$0]).first?.uppercased() == "FINAL"
        }
        if finalIndices.count != 1 {
            errors.append("[Rule] 必须且只能包含一条 FINAL，当前为 \(finalIndices.count) 条。")
        } else if finalIndices[0] != rules.index(before: rules.endIndex) {
            errors.append("FINAL 必须是 [Rule] 的最后一条有效规则。")
        }
        if !profile.contains(ownershipMarker) {
            warnings.append("生成文件缺少 Surge Shallow 所有权标记。")
        }
        return ProfileLintResult(errors: errors, warnings: warnings)
    }

    private static func sectionName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count >= 3 else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func generatedRuleSection(
        mergedRules: MergedRules,
        finalPolicy: String,
        generatedAt: Date
    ) throws -> [String] {
        let final = finalPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty,
              !final.contains(","),
              !final.contains("\n"),
              !final.contains("\r") else {
            throw RelayEngineError.invalidConfiguration("FINAL 策略不能为空，也不能包含逗号或换行。")
        }
        let stamp = ISO8601DateFormatter().string(from: generatedAt)
        return [
            "[Rule]",
            ownershipMarker,
            "# 此段由 Surge Shallow 自动生成，请在应用中修改规则源。",
            "# 生成时间：\(stamp)"
        ] + mergedRules.lines + ["", "FINAL,\(final)"]
    }

    private static func sanitizeImportedProfile(_ value: String) -> (content: String, warnings: [String]) {
        var warnings: [String] = []
        var lines = normalize(value).components(separatedBy: "\n")
        let managedCount = lines.filter {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#!MANAGED-CONFIG")
        }.count
        if managedCount > 0 {
            lines.removeAll {
                $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#!MANAGED-CONFIG")
            }
            warnings.append("已移除配置中的 #!MANAGED-CONFIG，避免生成文件被远端覆盖。")
        }
        return (lines.joined(separator: "\n"), warnings)
    }
}

private struct SharedSectionReference {
    var displayName: String
    var normalizedName: String

    init(displayName: String) {
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedName = self.displayName.lowercased()
    }
}

private struct ParsedSection {
    var header: String
    var normalizedName: String
    var lines: [String]

    var displayName: String {
        String(header.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    var rendered: String {
        ([header] + lines).joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

private struct ParsedProfile {
    var preamble: [String]
    var sections: [ParsedSection]

    init(preamble: [String], sections: [ParsedSection]) {
        self.preamble = preamble
        self.sections = sections
    }

    init(_ content: String) {
        let lines = content.components(separatedBy: "\n")
        var preamble: [String] = []
        var sections: [ParsedSection] = []
        var currentHeader: String?
        var currentName: String?
        var currentLines: [String] = []

        func finishSection() {
            guard let currentHeader, let currentName else { return }
            sections.append(ParsedSection(
                header: currentHeader,
                normalizedName: currentName,
                lines: currentLines
            ))
        }

        for line in lines {
            if let name = Self.sectionName(of: line) {
                finishSection()
                currentHeader = line.trimmingCharacters(in: .whitespaces)
                currentName = name
                currentLines = []
            } else if currentHeader == nil {
                preamble.append(line)
            } else {
                currentLines.append(line)
            }
        }
        finishSection()
        self.preamble = preamble
        self.sections = sections
    }

    func rendered() -> String {
        let cleanPreamble = preamble
            .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .reversed()
            .drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .reversed()
        let blocks = [Array(cleanPreamble).joined(separator: "\n")] + sections.map(\.rendered)
        return blocks
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .newlines) + "\n"
    }

    private static func sectionName(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count >= 3 else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces).lowercased()
    }
}
