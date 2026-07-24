import Foundation

public enum RelayEngineError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidProfile(String)
    case sourceUnavailable(String)
    case validationFailed(String)
    case publishingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail): "配置无效：\(detail)"
        case .invalidProfile(let detail): "生成的 Profile 无效：\(detail)"
        case .sourceUnavailable(let detail): "规则源不可用：\(detail)"
        case .validationFailed(let detail): "Surge 校验失败：\(detail)"
        case .publishingFailed(let detail): "发布失败：\(detail)"
        }
    }
}

public struct RelayProgress: Sendable {
    public var fraction: Double
    public var message: String

    public init(fraction: Double, message: String) {
        self.fraction = fraction
        self.message = message
    }
}

public struct GeneratedProfileInfo: Identifiable, Sendable {
    public var platform: RelayPlatform
    public var outputURL: URL
    public var previewURL: URL
    public var content: String
    public var ruleCount: Int
    public var validationMessage: String

    public var id: RelayPlatform { platform }
}

public struct GeneratedSharedProfileInfo: Sendable {
    public var outputURL: URL
    public var previewURL: URL
    public var content: String
    public var sections: [String]
}

public struct GeneratedDetachedRuleFileInfo: Sendable {
    public var sourceID: UUID
    public var fileName: String
    public var outputURL: URL
    public var previewURL: URL
    public var content: String
    public var ruleCount: Int
}

public struct RelayRefreshResult: Sendable {
    public var document: RelayDocument
    public var outcome: UpdateRecord.Outcome
    public var title: String
    public var details: String
    public var warnings: [String]
    public var generatedSharedProfile: GeneratedSharedProfileInfo?
    public var generatedDetachedRuleFiles: [GeneratedDetachedRuleFileInfo]
    public var generatedProfiles: [GeneratedProfileInfo]
    public var totalRuleCount: Int
    public var duplicateCount: Int

    public var succeeded: Bool { outcome != .failure }

    public init(
        document: RelayDocument,
        outcome: UpdateRecord.Outcome,
        title: String,
        details: String,
        warnings: [String] = [],
        generatedSharedProfile: GeneratedSharedProfileInfo? = nil,
        generatedDetachedRuleFiles: [GeneratedDetachedRuleFileInfo] = [],
        generatedProfiles: [GeneratedProfileInfo] = [],
        totalRuleCount: Int = 0,
        duplicateCount: Int = 0
    ) {
        self.document = document
        self.outcome = outcome
        self.title = title
        self.details = details
        self.warnings = warnings
        self.generatedSharedProfile = generatedSharedProfile
        self.generatedDetachedRuleFiles = generatedDetachedRuleFiles
        self.generatedProfiles = generatedProfiles
        self.totalRuleCount = totalRuleCount
        self.duplicateCount = duplicateCount
    }
}

public actor RelayEngine {
    private let fetcher: any RuleSourceFetching
    private let publisher: ProfilePublisher

    public init(
        fetcher: any RuleSourceFetching = URLSessionRuleSourceFetcher(),
        publisher: ProfilePublisher = ProfilePublisher()
    ) {
        self.fetcher = fetcher
        self.publisher = publisher
    }

    public func refresh(
        document input: RelayDocument,
        persistence: RelayPersistence,
        force: Bool,
        progress: (@Sendable (RelayProgress) async -> Void)? = nil
    ) async -> RelayRefreshResult {
        var document = input
        let enabledSources = document.sources.filter(\.isEnabled)
        let inlineSources = enabledSources.filter { $0.resolvedOutputMode == .inlineMerged }
        await progress?(RelayProgress(fraction: 0.02, message: "正在准备规则源…"))

        let sharedIssues = document.sharedProfile.configurationIssues
        guard sharedIssues.isEmpty else {
            return failureResult(
                document: document,
                title: "公共配置无效，未生成 Profile",
                details: sharedIssues.joined(separator: "\n"),
                warnings: []
            )
        }

        let allowedManualPlatforms: Set<Set<RelayPlatform>> = [
            [.macOS],
            Set(RelayPlatform.allCases)
        ]
        let invalidManualSources = enabledSources.compactMap { source -> String? in
            guard source.isManual else { return nil }
            guard source.embeddedContent != nil else {
                return "\(source.name)：手工规则内容缺失"
            }
            guard allowedManualPlatforms.contains(source.platforms) else {
                return "\(source.name)：手工规则仅支持“仅 macOS”或“macOS + iOS”"
            }
            return nil
        }
        guard invalidManualSources.isEmpty else {
            return failureResult(
                document: document,
                title: "手工规则配置无效，未生成 Profile",
                details: invalidManualSources.joined(separator: "\n"),
                warnings: []
            )
        }

        let invalidReferences = enabledSources.compactMap { source -> String? in
            guard source.resolvedOutputMode == .remoteReference,
                  source.remoteRulesetDirective == nil else { return nil }
            return "\(source.name)：外部引用需要 HTTP(S) Surge Ruleset URL、有效策略和兼容格式"
        }
        guard invalidReferences.isEmpty else {
            return failureResult(
                document: document,
                title: "规则源配置无效，未生成 Profile",
                details: invalidReferences.joined(separator: "\n"),
                warnings: []
            )
        }

        let fetcher = self.fetcher
        let settings = document.settings
        var materials: [UUID: SourceMaterial] = [:]
        await withTaskGroup(of: SourceMaterial.self) { group in
            for source in inlineSources {
                group.addTask {
                    await Self.loadMaterial(
                        for: source,
                        persistence: persistence,
                        fetcher: fetcher,
                        settings: settings,
                        force: force
                    )
                }
            }
            var completed = 0
            for await material in group {
                materials[material.sourceID] = material
                completed += 1
                let denominator = max(1, inlineSources.count)
                let fraction = 0.05 + (Double(completed) / Double(denominator)) * 0.5
                await progress?(RelayProgress(fraction: fraction, message: material.progressMessage))
            }
        }

        var sourceWarnings: [String] = []
        for index in document.sources.indices where document.sources[index].isEnabled {
            if document.sources[index].resolvedOutputMode == .remoteReference {
                document.sources[index].lastRuleCount = 0
                document.sources[index].lastError = nil
                continue
            }
            guard let material = materials[document.sources[index].id] else { continue }
            document.sources[index].state = material.state
            document.sources[index].lastError = material.errorMessage
            document.sources[index].lastRuleCount = material.parsed?.rules.filter {
                !$0.hasPrefix("#!")
            }.count ?? 0
            if let checkedAt = material.checkedAt { document.sources[index].lastCheckedAt = checkedAt }
            if let updatedAt = material.updatedAt { document.sources[index].lastUpdatedAt = updatedAt }
            if material.receivedMetadata {
                document.sources[index].etag = material.etag
                document.sources[index].lastModified = material.lastModified
                document.sources[index].contentHash = material.contentHash
            }
            sourceWarnings.append(contentsOf: material.warnings)
        }

        let unusable = inlineSources.compactMap { source -> String? in
            guard materials[source.id]?.parsed == nil else { return nil }
            let reason = materials[source.id]?.errorMessage ?? "没有可用内容或缓存"
            return "\(source.name)：\(reason)"
        }
        guard unusable.isEmpty else {
            let detail = unusable.joined(separator: "\n")
            let record = UpdateRecord(
                outcome: .failure,
                title: "未发布，保留最后成功版本",
                details: detail
            )
            document.appendHistory(record)
            return RelayRefreshResult(
                document: document,
                outcome: .failure,
                title: record.title,
                details: detail,
                warnings: sourceWarnings
            )
        }

        await progress?(RelayProgress(fraction: 0.6, message: "正在组装规则…"))
        let enabledTargets = document.targets.filter(\.isEnabled)
        let targetNames = enabledTargets.map {
            TargetProfile.sanitizedFileName($0.outputFileName, platform: $0.platform).lowercased()
        }
        let sharedName = SharedProfile.sanitizedFileName(document.sharedProfile.outputFileName)
        let enabledTargetPlatforms = Set(enabledTargets.map(\.platform))
        let detachedNames = enabledSources.compactMap { source -> String? in
            guard source.publishesDetachedProfile,
                  !source.platforms.isDisjoint(with: enabledTargetPlatforms) else { return nil }
            return source.resolvedDetachedFileName.lowercased()
        }
        let outputNames = enabledTargets.isEmpty
            ? targetNames
            : targetNames + [sharedName.lowercased()] + detachedNames
        let duplicateNames = Dictionary(grouping: outputNames, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
        guard duplicateNames.isEmpty else {
            return failureResult(
                document: document,
                title: "输出文件名重复",
                details: "每个 Profile 与独立 .dconf 必须使用不同的文件名：\(duplicateNames.sorted().joined(separator: ", "))",
                warnings: sourceWarnings
            )
        }

        var mergedByPlatform: [RelayPlatform: MergedRules] = [:]
        for target in enabledTargets {
            let sources = document.sources.compactMap { source -> (source: RuleSource, parsed: ParsedRuleSource?)? in
                guard source.isEnabled,
                      source.platforms.contains(target.platform) else { return nil }
                return (source, materials[source.id]?.parsed)
            }
            mergedByPlatform[target.platform] = RuleMerger.merge(sources, for: target.platform)
        }

        let sharedRuleConfiguration: (rules: MergedRules, finalPolicy: String)? = {
            guard let firstTarget = enabledTargets.first,
                  let firstRules = mergedByPlatform[firstTarget.platform] else { return nil }
            let final = firstTarget.finalPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
            let canShare = enabledTargets.dropFirst().allSatisfy { target in
                guard let rules = mergedByPlatform[target.platform] else { return false }
                return rules.lines == firstRules.lines
                    && target.finalPolicy.trimmingCharacters(in: .whitespacesAndNewlines) == final
            }
            return canShare ? (firstRules, final) : nil
        }()

        var stagedShared: StagedSharedProfile?
        var stagedDetached: [StagedDetachedRuleFile] = []
        var staged: [StagedProfile] = []
        var allWarnings = sourceWarnings
        var totalRules = 0
        var totalDuplicates = 0
        let generatedAt = Date()
        do {
            var detachedBySource: [UUID: DetachedRuleFile] = [:]
            for merged in mergedByPlatform.values {
                for file in merged.detachedRuleFiles {
                    if let existing = detachedBySource[file.sourceID], existing != file {
                        throw RelayEngineError.invalidConfiguration(
                            "独立规则文件 \(file.fileName) 在不同平台产生了不一致内容。"
                        )
                    }
                    detachedBySource[file.sourceID] = file
                }
            }
            for source in document.sources {
                guard let file = detachedBySource[source.id] else { continue }
                let content = try ProfileAssembler.assembleDetachedRuleFile(
                    file,
                    generatedAt: generatedAt
                )
                let preview = try persistence.writeDetachedPreview(
                    content,
                    fileName: file.fileName
                )
                try publisher.validateDetachedDestination(
                    fileName: file.fileName,
                    sourceID: file.sourceID,
                    directory: URL(
                        filePath: document.settings.outputDirectory,
                        directoryHint: .isDirectory
                    )
                )
                stagedDetached.append(StagedDetachedRuleFile(
                    file: file,
                    content: content,
                    previewURL: preview
                ))
            }

            var sharedSections: [String] = []
            if !enabledTargets.isEmpty {
                let shared = try ProfileAssembler.assembleShared(
                    baseProfile: document.sharedProfile.baseProfile,
                    sharedRules: sharedRuleConfiguration?.rules,
                    finalPolicy: sharedRuleConfiguration?.finalPolicy,
                    generatedAt: generatedAt
                )
                sharedSections = shared.sections
                allWarnings.append(contentsOf: shared.warnings)
                if !shared.sections.isEmpty {
                    let preview = try persistence.writeSharedPreview(
                        shared.content,
                        fileName: document.sharedProfile.outputFileName
                    )
                    try publisher.validateDestination(
                        for: document.sharedProfile,
                        directory: URL(filePath: document.settings.outputDirectory, directoryHint: .isDirectory)
                    )
                    stagedShared = StagedSharedProfile(
                        profile: document.sharedProfile,
                        assembled: shared,
                        previewURL: preview
                    )
                }
            }

            for target in enabledTargets {
                guard let merged = mergedByPlatform[target.platform] else { continue }
                let assembled = try ProfileAssembler.assemblePlatform(
                    platformProfile: target.platformProfile,
                    sharedFileName: document.sharedProfile.outputFileName,
                    sharedSections: sharedSections,
                    mergedRules: merged,
                    finalPolicy: target.finalPolicy,
                    generatedAt: generatedAt
                )
                let preview = try persistence.writePreview(assembled.content, for: target.platform)
                let validation: SurgeValidationResult
                if document.settings.validateWithSurgeCLI {
                    validation = await SurgeCLIValidator.validate(profileAt: preview)
                } else {
                    validation = SurgeValidationResult(
                        isAvailable: SurgeCLIValidator.executableURL != nil,
                        isValid: true,
                        message: "已执行内置结构检查；Surge CLI 校验已关闭。"
                    )
                }
                guard validation.isValid else {
                    throw RelayEngineError.validationFailed(
                        "\(target.platform.displayName)：\(validation.message)"
                    )
                }
                try publisher.validateDestination(
                    for: target,
                    directory: URL(filePath: document.settings.outputDirectory, directoryHint: .isDirectory)
                )
                staged.append(StagedProfile(
                    target: target,
                    assembled: assembled,
                    previewURL: preview,
                    duplicateCount: merged.duplicateCount,
                    validationMessage: validation.message
                ))
                allWarnings.append(contentsOf: assembled.warnings)
                totalRules += assembled.ruleCount
                totalDuplicates += merged.duplicateCount
            }
        } catch {
            return failureResult(
                document: document,
                title: "校验未通过，未覆盖现有 Profile",
                details: error.localizedDescription,
                warnings: allWarnings
            )
        }

        await progress?(RelayProgress(fraction: 0.82, message: "正在原子写入 iCloud…"))
        var generatedShared: GeneratedSharedProfileInfo?
        var generatedDetached: [GeneratedDetachedRuleFileInfo] = []
        var generated: [GeneratedProfileInfo] = []
        do {
            let directory = URL(filePath: document.settings.outputDirectory, directoryHint: .isDirectory)
            for item in stagedDetached {
                let output = try publisher.publishDetachedRuleFile(
                    content: item.content,
                    fileName: item.file.fileName,
                    sourceID: item.file.sourceID,
                    directory: directory
                )
                generatedDetached.append(GeneratedDetachedRuleFileInfo(
                    sourceID: item.file.sourceID,
                    fileName: item.file.fileName,
                    outputURL: output,
                    previewURL: item.previewURL,
                    content: item.content,
                    ruleCount: item.file.rules.count
                ))
            }
            if let item = stagedShared {
                let output = try publisher.publish(
                    content: item.assembled.content,
                    sharedProfile: item.profile,
                    directory: directory
                )
                generatedShared = GeneratedSharedProfileInfo(
                    outputURL: output,
                    previewURL: item.previewURL,
                    content: item.assembled.content,
                    sections: item.assembled.sections
                )
                document.sharedProfile.lastGeneratedAt = .now
                document.sharedProfile.lastValidationMessage = "已作为 Detached Profile 由启用的平台共同引用。"
            }
            for item in staged {
                let output = try publisher.publish(
                    content: item.assembled.content,
                    target: item.target,
                    directory: directory
                )
                generated.append(GeneratedProfileInfo(
                    platform: item.target.platform,
                    outputURL: output,
                    previewURL: item.previewURL,
                    content: item.assembled.content,
                    ruleCount: item.assembled.ruleCount,
                    validationMessage: item.validationMessage
                ))
                if let index = document.targets.firstIndex(where: { $0.platform == item.target.platform }) {
                    document.targets[index].lastGeneratedAt = .now
                    document.targets[index].lastRuleCount = item.assembled.ruleCount
                    document.targets[index].lastValidationMessage = item.validationMessage
                }
            }
        } catch {
            return failureResult(
                document: document,
                title: "iCloud 发布失败",
                details: error.localizedDescription,
                warnings: allWarnings
            )
        }

        await progress?(RelayProgress(fraction: 0.98, message: "正在保存生成记录…"))
        let usedStaleCache = materials.values.contains { $0.state == .staleCache }
        let uniqueWarnings = Array(Set(allWarnings)).sorted()
        let outcome: UpdateRecord.Outcome = (usedStaleCache || !uniqueWarnings.isEmpty) ? .warning : .success
        let title = outcome == .success ? "Profile 已生成" : "Profile 已生成（有提示）"
        let details = generated.isEmpty
            ? "没有启用的目标 Profile。"
            : generated.map { "\($0.platform.displayName)：\($0.ruleCount) 条规则" }.joined(separator: " · ")
        document.appendHistory(UpdateRecord(
            outcome: outcome,
            title: title,
            details: details,
            ruleCount: totalRules,
            duplicateCount: totalDuplicates
        ))
        await progress?(RelayProgress(fraction: 1, message: title))
        return RelayRefreshResult(
            document: document,
            outcome: outcome,
            title: title,
            details: details,
            warnings: uniqueWarnings,
            generatedSharedProfile: generatedShared,
            generatedDetachedRuleFiles: generatedDetached,
            generatedProfiles: generated,
            totalRuleCount: totalRules,
            duplicateCount: totalDuplicates
        )
    }

    private func failureResult(
        document input: RelayDocument,
        title: String,
        details: String,
        warnings: [String]
    ) -> RelayRefreshResult {
        var document = input
        document.appendHistory(UpdateRecord(outcome: .failure, title: title, details: details))
        return RelayRefreshResult(
            document: document,
            outcome: .failure,
            title: title,
            details: details,
            warnings: warnings
        )
    }

    private static func loadMaterial(
        for source: RuleSource,
        persistence: RelayPersistence,
        fetcher: any RuleSourceFetching,
        settings: RelaySettings,
        force: Bool
    ) async -> SourceMaterial {
        let cached = try? persistence.cachedContent(for: source.id)
        let mustFetch = source.isEmbedded
            || force
            || source.isDue(globalIntervalMinutes: settings.refreshIntervalMinutes)
            || cached == nil

        if !mustFetch, let cached {
            do {
                let parsed = try RuleParser.parse(cached, for: source)
                return SourceMaterial(
                    sourceID: source.id,
                    parsed: parsed,
                    state: .current,
                    progressMessage: "\(source.name) 使用本地缓存",
                    errorMessage: nil,
                    warnings: [],
                    checkedAt: nil,
                    updatedAt: nil,
                    receivedMetadata: false,
                    etag: source.etag,
                    lastModified: source.lastModified,
                    contentHash: source.contentHash
                )
            } catch {
                // A corrupt cache should trigger a network repair immediately.
            }
        }

        do {
            let response = try await fetcher.fetch(
                source: source,
                timeoutSeconds: settings.requestTimeoutSeconds,
                maximumSizeMB: settings.maximumSourceSizeMB
            )
            switch response {
            case .notModified(let checkedAt):
                if let cached, let parsed = try? RuleParser.parse(cached, for: source) {
                    return SourceMaterial(
                        sourceID: source.id,
                        parsed: parsed,
                        state: .current,
                        progressMessage: "\(source.name) 已是最新",
                        errorMessage: nil,
                        warnings: [],
                        checkedAt: checkedAt,
                        updatedAt: nil,
                        receivedMetadata: false,
                        etag: source.etag,
                        lastModified: source.lastModified,
                        contentHash: source.contentHash
                    )
                }
                // A 304 without a usable cache can happen after cache cleanup.
                // Retry once without validators so the source can self-repair.
                var unconditional = source
                unconditional.etag = nil
                unconditional.lastModified = nil
                let retry = try await fetcher.fetch(
                    source: unconditional,
                    timeoutSeconds: settings.requestTimeoutSeconds,
                    maximumSizeMB: settings.maximumSourceSizeMB
                )
                guard case let .modified(content, etag, lastModified, hash, retryCheckedAt) = retry else {
                    throw RelayEngineError.sourceUnavailable("服务器连续返回 304，但本地缓存不可用。")
                }
                return try modifiedMaterial(
                    content: content,
                    etag: etag,
                    lastModified: lastModified,
                    hash: hash,
                    checkedAt: retryCheckedAt,
                    source: source,
                    persistence: persistence
                )
            case .modified(let content, let etag, let lastModified, let hash, let checkedAt):
                return try modifiedMaterial(
                    content: content,
                    etag: etag,
                    lastModified: lastModified,
                    hash: hash,
                    checkedAt: checkedAt,
                    source: source,
                    persistence: persistence
                )
            }
        } catch {
            if let cached, let parsed = try? RuleParser.parse(cached, for: source) {
                let message = error.localizedDescription
                return SourceMaterial(
                    sourceID: source.id,
                    parsed: parsed,
                    state: .staleCache,
                    progressMessage: "\(source.name) 上游失败，使用缓存",
                    errorMessage: message,
                    warnings: ["\(source.name)：上游更新失败，已使用最后成功缓存。\(message)"],
                    checkedAt: .now,
                    updatedAt: nil,
                    receivedMetadata: false,
                    etag: source.etag,
                    lastModified: source.lastModified,
                    contentHash: source.contentHash
                )
            }
            return SourceMaterial(
                sourceID: source.id,
                parsed: nil,
                state: .failed,
                progressMessage: "\(source.name) 更新失败",
                errorMessage: error.localizedDescription,
                warnings: [],
                checkedAt: .now,
                updatedAt: nil,
                receivedMetadata: false,
                etag: source.etag,
                lastModified: source.lastModified,
                contentHash: source.contentHash
            )
        }
    }

    private static func modifiedMaterial(
        content: String,
        etag: String?,
        lastModified: String?,
        hash: String,
        checkedAt: Date,
        source: RuleSource,
        persistence: RelayPersistence
    ) throws -> SourceMaterial {
        let parsed = try RuleParser.parse(content, for: source)
        var warnings: [String] = []
        if !source.isEmbedded {
            do {
                try persistence.saveCachedContent(content, for: source.id)
            } catch {
                warnings.append("\(source.name)：新内容已使用，但缓存写入失败：\(error.localizedDescription)")
            }
        }
        let changed = source.contentHash != hash
        return SourceMaterial(
            sourceID: source.id,
            parsed: parsed,
            state: changed ? .updated : .current,
            progressMessage: changed ? "\(source.name) 已更新" : "\(source.name) 内容未变化",
            errorMessage: nil,
            warnings: warnings,
            checkedAt: checkedAt,
            updatedAt: changed ? checkedAt : nil,
            receivedMetadata: true,
            etag: etag,
            lastModified: lastModified,
            contentHash: hash
        )
    }
}

private struct SourceMaterial: Sendable {
    var sourceID: UUID
    var parsed: ParsedRuleSource?
    var state: RuleSourceState
    var progressMessage: String
    var errorMessage: String?
    var warnings: [String]
    var checkedAt: Date?
    var updatedAt: Date?
    var receivedMetadata: Bool
    var etag: String?
    var lastModified: String?
    var contentHash: String?
}

private struct StagedProfile: Sendable {
    var target: TargetProfile
    var assembled: AssembledProfile
    var previewURL: URL
    var duplicateCount: Int
    var validationMessage: String
}

private struct StagedSharedProfile: Sendable {
    var profile: SharedProfile
    var assembled: AssembledSharedProfile
    var previewURL: URL
}

private struct StagedDetachedRuleFile: Sendable {
    var file: DetachedRuleFile
    var content: String
    var previewURL: URL
}
