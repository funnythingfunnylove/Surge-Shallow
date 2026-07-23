import AppKit
import Observation
import ServiceManagement
import SurgeModuleManagement
import SurgeProfileRelayCore

enum SidebarDestination: String, CaseIterable, Identifiable {
    case dashboard
    case sources
    case proxy
    case profiles
    case modules
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "总览"
        case .sources: "规则源"
        case .proxy: "Proxy"
        case .profiles: "Profiles"
        case .modules: "模块"
        case .history: "更新记录"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .sources: "link"
        case .proxy: "point.3.connected.trianglepath.dotted"
        case .profiles: "doc.on.doc"
        case .modules: "shippingbox"
        case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .settings: "gearshape"
        }
    }
}

enum SidebarUpdateStatus: Equatable {
    case refreshing(String)
    case current
    case warning
    case failed
    case pending
    case empty

    var title: String {
        switch self {
        case .refreshing(let message): message
        case .current: "规则已是最新"
        case .warning: "已更新，有提示"
        case .failed: "规则更新失败"
        case .pending: "等待更新规则"
        case .empty: "尚未添加规则源"
        }
    }

    static func resolve(
        isRefreshing: Bool,
        statusMessage: String,
        enabledSourceStates: [RuleSourceState],
        latestOutcome: UpdateRecord.Outcome?,
        hasSuccessfulUpdate: Bool
    ) -> Self {
        if isRefreshing {
            return .refreshing(statusMessage)
        }
        guard !enabledSourceStates.isEmpty else {
            return .empty
        }
        if latestOutcome == .failure || enabledSourceStates.contains(.failed) {
            return .failed
        }
        if latestOutcome == .warning || enabledSourceStates.contains(.staleCache) {
            return .warning
        }
        if latestOutcome == .success, hasSuccessfulUpdate {
            return .current
        }
        if enabledSourceStates.contains(.never) {
            return .pending
        }
        return hasSuccessfulUpdate ? .current : .pending
    }
}

@MainActor
@Observable
final class AppModel {
    /// Module management is a feature of this application and shares the
    /// application's lifetime; it is not a second embedded app instance.
    let moduleManagement: ModuleManagementController
    let softwareUpdate: SoftwareUpdateController
    var document: RelayDocument
    var selection: SidebarDestination = .dashboard
    var selectedSourceID: UUID?
    var isRefreshing = false
    var progressFraction = 0.0
    var statusMessage = "准备就绪"
    var lastResult: RelayRefreshResult?
    var presentedError: String?
    var previewTitle = ""
    var previewContent: String?
    var isChoosingProfileImport = false
    var isParsingProfileImport = false
    var pendingProfileImport: ProfileImportDraft?
    var isStarted = false

    private let engine = RelayEngine()
    private var schedulerTask: Task<Void, Never>?
    private var softwareUpdateSchedulerTask: Task<Void, Never>?

    init() {
        moduleManagement = ModuleManagementController()
        softwareUpdate = SoftwareUpdateController()
        let persistence = RelayPersistence()
        do {
            var loaded = try persistence.loadDocument()
            loaded.settings.outputDirectory = persistence.outputDirectory.path
            document = loaded
        } catch {
            var fallback = RelayDocument()
            fallback.settings.outputDirectory = persistence.outputDirectory.path
            document = fallback
            presentedError = error.localizedDescription
        }
    }

    var enabledSourceCount: Int {
        document.sources.filter(\.isEnabled).count
    }

    var currentRuleCount: Int {
        document.targets.filter(\.isEnabled).map(\.lastRuleCount).reduce(0, +)
    }

    var lastSuccessfulUpdate: Date? {
        document.history.first(where: { $0.outcome != .failure })?.date
    }

    var sidebarUpdateStatus: SidebarUpdateStatus {
        SidebarUpdateStatus.resolve(
            isRefreshing: isRefreshing,
            statusMessage: statusMessage,
            enabledSourceStates: document.sources.filter(\.isEnabled).map(\.state),
            latestOutcome: document.history.first?.outcome,
            hasSuccessfulUpdate: lastSuccessfulUpdate != nil
        )
    }

    var outputDirectoryURL: URL {
        URL(filePath: document.settings.outputDirectory, directoryHint: .isDirectory)
    }

    var isSurgeICloudAvailable: Bool {
        FileManager.default.fileExists(atPath: RelayPaths.defaultSurgeICloudDirectory.path)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        if ProcessInfo.processInfo.arguments.contains("--verification-mode") {
            statusMessage = "验证模式：未启动自动刷新"
            if let releasePath = ProcessInfo.processInfo.environment[
                "SURGE_SHALLOW_VERIFICATION_RELEASE_JSON"
            ], !releasePath.isEmpty {
                do {
                    let data = try Data(contentsOf: URL(filePath: releasePath))
                    let release = try GitHubReleaseDecoder().decode(data)
                    softwareUpdate.presentForVerification(release)
                } catch {
                    presentedError = "更新弹窗验证数据无效：\(error.localizedDescription)"
                }
            }
            if let previewPath = ProcessInfo.processInfo.environment[
                "SURGE_SHALLOW_VERIFICATION_IMPORT_PROFILE"
            ], !previewPath.isEmpty {
                prepareFullProfileImport(from: URL(filePath: previewPath))
            }
            return
        }

        Task { await moduleManagement.startConfiguredRuntime() }
        startSoftwareUpdateScheduler()
        restartScheduler()
        if document.settings.refreshOnLaunch && document.sources.contains(where: { $0.isEnabled }) {
            Task { await refresh(force: false) }
        }
    }

    func refresh(force: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        progressFraction = 0
        statusMessage = force ? "正在检查所有上游…" : "正在检查到期上游…"
        defer { isRefreshing = false }

        let persistence = RelayPersistence(outputDirectory: outputDirectoryURL)
        let result = await engine.refresh(
            document: document,
            persistence: persistence,
            force: force
        ) { [weak self] progress in
            await MainActor.run {
                self?.progressFraction = progress.fraction
                self?.statusMessage = progress.message
            }
        }
        document = result.document
        lastResult = result
        statusMessage = result.title
        do {
            try persistence.saveDocument(document)
        } catch {
            presentedError = "结果已生成，但管理配置保存失败：\(error.localizedDescription)"
        }
        if !result.succeeded {
            presentedError = result.details
        }
    }

    func checkForSoftwareUpdates(userInitiated: Bool = true) async {
        do {
            let result = try await softwareUpdate.checkForUpdates()
            switch result {
            case .upToDate(let release):
                if userInitiated {
                    presentedError = "当前已是最新版本 \(softwareUpdate.currentVersion)。GitHub 最新正式版本为 \(release.version)。"
                }
            case .updateAvailable:
                break
            }
        } catch {
            if userInitiated {
                presentedError = "检查软件更新失败：\(error.localizedDescription)"
            }
        }
    }

    func presentAvailableSoftwareUpdateOrCheck() {
        if softwareUpdate.availableUpdate != nil {
            softwareUpdate.presentAvailableUpdate()
        } else {
            Task { await checkForSoftwareUpdates() }
        }
    }

    func installSoftwareUpdate(_ release: SoftwareRelease) async {
        do {
            try await softwareUpdate.install(
                release,
                currentApplicationURL: Bundle.main.bundleURL,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            )
            NSApp.terminate(nil)
        } catch {
            presentedError = "更新安装失败：\(error.localizedDescription)"
        }
    }

    func save() {
        guard canMutateConfiguration() else { return }
        let persistence = RelayPersistence(outputDirectory: outputDirectoryURL)
        do {
            try persistence.saveDocument(document)
            RelayPersistence.rememberOutputDirectory(outputDirectoryURL)
        } catch {
            presentedError = error.localizedDescription
        }
        restartScheduler()
    }

    func upsertSource(_ source: RuleSource) {
        guard canMutateConfiguration() else { return }
        var source = source
        if let reference = RemoteRulesetReference.parse(source.url) {
            source.url = reference.url
            source.policy = reference.policy
            source.format = .surgeRuleset
            source.preservesSourcePolicy = false
            source.rulesetOptions = reference.options
            source.outputMode = .remoteReference
        } else if source.format == .surgeRuleset {
            source.preservesSourcePolicy = false
        }
        if let index = document.sources.firstIndex(where: { $0.id == source.id }) {
            let old = document.sources[index]
            document.sources[index] = source
            if old.url != source.url
                || old.embeddedContent != source.embeddedContent
                || old.format != source.format
                || old.policy != source.policy
                || old.rulesetOptions != source.rulesetOptions
                || old.outputMode != source.outputMode {
                document.sources[index].etag = nil
                document.sources[index].lastModified = nil
                document.sources[index].lastCheckedAt = nil
                document.sources[index].state = .never
            }
        } else {
            document.sources.append(source)
        }
        selectedSourceID = source.id
        save()
    }

    @discardableResult
    func addSources(_ sources: [RuleSource]) -> Int {
        guard canMutateConfiguration() else { return 0 }
        var existingURLs = Set(document.sources.map {
            $0.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        let additions = sources.filter { source in
            let url = source.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !url.isEmpty else { return false }
            return existingURLs.insert(url).inserted
        }
        guard !additions.isEmpty else { return 0 }
        document.sources.append(contentsOf: additions)
        selectedSourceID = additions.last?.id
        save()
        statusMessage = "已批量添加 \(additions.count) 个 GitHub 规则源"
        return additions.count
    }

    func setSourceEnabled(_ id: UUID, enabled: Bool) {
        guard canMutateConfiguration() else { return }
        guard let index = document.sources.firstIndex(where: { $0.id == id }) else { return }
        document.sources[index].isEnabled = enabled
        save()
    }

    func deleteSource(_ id: UUID) {
        guard canMutateConfiguration() else { return }
        document.sources.removeAll { $0.id == id }
        try? RelayPersistence(outputDirectory: outputDirectoryURL).removeCache(for: id)
        selectedSourceID = document.sources.first?.id
        save()
    }

    func moveSource(_ id: UUID, offset: Int) {
        guard canMutateConfiguration() else { return }
        guard let from = document.sources.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard document.sources.indices.contains(to) else { return }
        document.sources.swapAt(from, to)
        save()
    }

    func updateTarget(_ platform: RelayPlatform, mutate: (inout TargetProfile) -> Void) {
        guard canMutateConfiguration() else { return }
        guard let index = document.targets.firstIndex(where: { $0.platform == platform }) else { return }
        mutate(&document.targets[index])
        document.targets[index].outputFileName = TargetProfile.sanitizedFileName(
            document.targets[index].outputFileName,
            platform: platform
        )
        save()
    }

    func updateSharedProfile(_ mutate: (inout SharedProfile) -> Void) {
        guard canMutateConfiguration() else { return }
        let previous = document.sharedProfile
        mutate(&document.sharedProfile)
        reconcilePolicyRenames(from: previous, to: document.sharedProfile)
        document.sharedProfile.outputFileName = SharedProfile.sanitizedFileName(
            document.sharedProfile.outputFileName
        )
        save()
    }

    private func reconcilePolicyRenames(from previous: SharedProfile, to updated: SharedProfile) {
        let oldDefinitions = previous.proxies + previous.proxyGroups
        let newDefinitions = updated.proxies + updated.proxyGroups
        var renames: [String: String] = [:]
        for old in oldDefinitions where old.kind == .definition {
            guard let new = newDefinitions.first(where: { $0.id == old.id && $0.kind == .definition }) else {
                continue
            }
            let oldName = old.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let newName = new.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !oldName.isEmpty,
                  !newName.isEmpty,
                  oldName != newName else { continue }
            renames[oldName.lowercased()] = newName
        }
        guard !renames.isEmpty else { return }

        for index in document.sources.indices {
            let key = document.sources[index].policy.lowercased()
            if let replacement = renames[key] {
                document.sources[index].policy = replacement
            }
        }
        for index in document.targets.indices {
            let key = document.targets[index].finalPolicy.lowercased()
            if let replacement = renames[key] {
                document.targets[index].finalPolicy = replacement
            }
        }
        for index in document.sharedProfile.proxyGroups.indices {
            document.sharedProfile.proxyGroups[index].parameters = RelayPolicyCatalog.replacingMemberNames(
                in: document.sharedProfile.proxyGroups[index].parameters,
                renames: renames
            )
        }
    }

    func importSharedProfile() {
        importProfile(
            title: "选择公共 Surge Profile",
            importedMessage: "已导入公共配置",
            apply: { [weak self] content, fileName in
                self?.updateSharedProfile { shared in
                    shared.baseProfile = content
                    shared.lastValidationMessage = "已导入 \(fileName)：\(shared.generalOptions.count) 个 General 项、\(shared.proxies.count) 个 Proxy 项、\(shared.proxyGroups.count) 个策略组项，等待重新生成。"
                }
            }
        )
    }

    func importPlatformProfile(for platform: RelayPlatform) {
        importProfile(
            title: "选择 \(platform.displayName) 差异配置",
            importedMessage: "已导入平台差异",
            apply: { [weak self] content, fileName in
                self?.updateTarget(platform) { target in
                    target.platformProfile = content
                    target.lastValidationMessage = "已导入 \(fileName) 并转换为 \(target.platformDifferences.count) 个差异项，等待重新生成。"
                }
            }
        )
    }

    func beginFullProfileImport() {
        guard canMutateConfiguration() else { return }
        isChoosingProfileImport = true
    }

    func prepareFullProfileImport(from url: URL) {
        guard canMutateConfiguration() else { return }
        isParsingProfileImport = true
        statusMessage = "正在分析 \(url.lastPathComponent)…"
        Task {
            defer { isParsingProfileImport = false }
            do {
                let draft = try await Task.detached(priority: .userInitiated) {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    return try ProfileImportService.parse(data: data, fileName: url.lastPathComponent)
                }.value
                pendingProfileImport = draft
                statusMessage = "已完成迁移分析，等待确认"
            } catch {
                presentedError = "无法导入 Profile：\(error.localizedDescription)"
                statusMessage = "Profile 分析失败"
            }
        }
    }

    func applyFullProfileImport(platforms: Set<RelayPlatform>) {
        guard canMutateConfiguration(),
              !platforms.isEmpty,
              let draft = pendingProfileImport else { return }
        let previous = document
        document = ProfileImportService.applying(draft, to: document, platforms: platforms)
        let persistence = RelayPersistence(outputDirectory: outputDirectoryURL)
        do {
            try persistence.saveDocument(document)
            pendingProfileImport = nil
            selection = .profiles
            statusMessage = "已迁移 \(draft.fileName)，请检查后更新并合并"
        } catch {
            document = previous
            presentedError = "迁移配置未保存：\(error.localizedDescription)"
        }
    }

    func cancelFullProfileImport() {
        pendingProfileImport = nil
        statusMessage = "已取消 Profile 迁移"
    }

    private func importProfile(
        title: String,
        importedMessage: String,
        apply: (String, String) -> Void
    ) {
        guard canMutateConfiguration() else { return }
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            apply(content, url.lastPathComponent)
            statusMessage = importedMessage
        } catch {
            presentedError = "无法导入 Profile：\(error.localizedDescription)"
        }
    }

    func chooseOutputDirectory() {
        guard canMutateConfiguration() else { return }
        let panel = NSOpenPanel()
        panel.title = "选择 Surge Profile 输出目录"
        panel.message = "推荐选择 Surge 的 iCloud Drive 配置目录，生成文件会自动出现在其他设备。"
        panel.prompt = "使用此目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relocateConfiguration(to: url)
    }

    func useDefaultSurgeICloudDirectory() {
        guard canMutateConfiguration() else { return }
        relocateConfiguration(to: RelayPaths.defaultSurgeICloudDirectory)
    }

    func openOutputDirectory() {
        NSWorkspace.shared.open(outputDirectoryURL)
    }

    func openOutput(for platform: RelayPlatform) {
        guard let target = document.targets.first(where: { $0.platform == platform }) else { return }
        let url = outputDirectoryURL.appending(path: target.outputFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            presentedError = "尚未生成 \(target.outputFileName)。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func showPreview(for platform: RelayPlatform) {
        if let generated = lastResult?.generatedProfiles.first(where: { $0.platform == platform }) {
            previewTitle = "\(platform.displayName) 生成预览"
            previewContent = generated.content
            return
        }
        let previewURL = RelayPersistence(outputDirectory: outputDirectoryURL).previewURL(for: platform)
        if let content = try? String(contentsOf: previewURL, encoding: .utf8) {
            previewTitle = "\(platform.displayName) 最近预览"
            previewContent = content
        } else {
            presentedError = "该平台还没有可预览的生成结果。"
        }
    }

    func showSharedPreview() {
        if let shared = lastResult?.generatedSharedProfile {
            previewTitle = "公共 Detached Profile 生成预览"
            previewContent = shared.content
            return
        }
        let persistence = RelayPersistence(outputDirectory: outputDirectoryURL)
        let url = persistence.sharedPreviewURL(fileName: document.sharedProfile.outputFileName)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            previewTitle = "公共 Detached Profile 最近预览"
            previewContent = content
        } else {
            presentedError = "公共配置还没有可预览的生成结果。"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard canMutateConfiguration() else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            document.settings.launchAtLogin = enabled
            save()
        } catch {
            document.settings.launchAtLogin = SMAppService.mainApp.status == .enabled
            presentedError = "无法修改登录项：\(error.localizedDescription)。请先使用打包后的 .app。"
        }
    }

    func dismissPreview() {
        previewContent = nil
    }

    private func relocateConfiguration(to url: URL) {
        guard canMutateConfiguration() else { return }
        let destination = url.standardizedFileURL
        var moved = document
        moved.settings.outputDirectory = destination.path
        do {
            let persistence = RelayPersistence(outputDirectory: destination)
            if persistence.configurationExists {
                var existing = try persistence.loadDocument()
                existing.settings.outputDirectory = destination.path
                document = existing
                statusMessage = "已读取此目录中的现有管理配置"
            } else {
                try persistence.saveDocument(moved)
                document = moved
                statusMessage = "输出目录已切换"
            }
            RelayPersistence.rememberOutputDirectory(destination)
            restartScheduler()
        } catch {
            presentedError = "无法切换输出目录：\(error.localizedDescription)"
        }
    }

    private func restartScheduler() {
        schedulerTask?.cancel()
        guard document.settings.automaticallyRefresh else { return }
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                let shouldRefresh = self.document.sources.contains {
                    $0.isEnabled && $0.isDue(globalIntervalMinutes: self.document.settings.refreshIntervalMinutes)
                }
                if shouldRefresh { await self.refresh(force: false) }
            }
        }
    }

    private func startSoftwareUpdateScheduler() {
        softwareUpdateSchedulerTask?.cancel()
        softwareUpdateSchedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.softwareUpdate.shouldCheckAutomatically {
                    await self.checkForSoftwareUpdates(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(1_800))
            }
        }

        if let result = SoftwareUpdateInstallationResultStore.consume() {
            switch result {
            case .pendingConfirmation(let version):
                Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(5))
                        try SoftwareUpdateInstallationResultStore.confirmInstallation()
                        self?.presentedError = "Surge Shallow 已成功更新到 \(version)。"
                    } catch is CancellationError {
                        return
                    } catch {
                        self?.presentedError = "新版本启动确认失败，安装器将自动恢复原版本。"
                    }
                }
            case .restoredPreviousVersion:
                presentedError = "软件更新未完成，已自动恢复并重新打开原版本。"
            case .installationFailed:
                presentedError = "软件更新未完成，安装器无法恢复原版本。请从 GitHub Release 重新下载安装。"
            }
        }
    }

    private func canMutateConfiguration() -> Bool {
        guard !isRefreshing else {
            presentedError = "正在生成 Profile。为避免发布时配置发生变化，请等待本次更新完成后再编辑。"
            return false
        }
        return true
    }
}
