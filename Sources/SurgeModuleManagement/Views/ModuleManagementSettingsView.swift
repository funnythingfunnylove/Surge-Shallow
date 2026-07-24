import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct ModuleManagementSettingsView: View {
    @Environment(ModuleManagementModel.self) private var model
    @State private var isCheckingUpdate = false
    @State private var isTesting = false
    @State private var connectionResult: ConnectionResult?
    @State private var ponteServerAddressInput = ""
    @State private var showsWebQRCode = false
    @State private var pendingStorageMode: StorageMode?
    @State private var selectedPane: SettingsPane = .general
    @State private var githubRepositoryInput = ""
    @State private var githubCloudflareInput = ""
    @State private var originalGitHubRepositoryInput = ""
    @State private var originalGitHubCloudflareInput = ""
    @State private var originalGitHubToken = ""
    @State private var didLoadGitHubDraft = false

    private enum ConnectionResult {
        case success(String)
        case failure(String)
        var message: String {
            switch self {
            case let .success(text), let .failure(text): return text
            }
        }
        var isError: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general
        case web
        case ponte
        case scriptHub
        case synchronization
        case diagnostics

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "通用"
            case .web: "Web 管理"
            case .ponte: "Surge Ponte"
            case .scriptHub: "Script Hub"
            case .synchronization: "同步"
            case .diagnostics: "诊断"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .web: "network"
            case .ponte: "dot.radiowaves.left.and.right"
            case .scriptHub: "arrow.triangle.branch"
            case .synchronization: "arrow.trianglehead.2.clockwise.rotate.90"
            case .diagnostics: "stethoscope"
            }
        }
    }

    var body: some View {
        Section("模块管理") {
            Picker("设置分类", selection: $selectedPane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.symbol)
                        .tag(pane)
                }
            }
            .pickerStyle(.menu)

            detailView(for: selectedPane)
        }
        .onAppear {
            loadGitHubDraftIfNeeded()
            ponteServerAddressInput = model.ponteServerAddress
        }
        .sheet(isPresented: $showsWebQRCode) {
            if let url = model.webManagementURL {
                VStack(spacing: 18) {
                    Text("Web 管理").font(.title2.bold())
                    if let image = qrCodeImage(for: url.absoluteString) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 240, height: 240)
                    }
                    Text(url.absoluteString)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Button("完成") { showsWebQRCode = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(28)
                .frame(minWidth: 330)
            }
        }
    }

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: generalSettings
        case .web: webSettings
        case .ponte: ponteSettings
        case .scriptHub: scriptHubSettings
        case .synchronization: synchronizationSettings
        case .diagnostics: diagnosticsSettings
        }
    }

    @ViewBuilder
    private var generalSettings: some View {
        LabeledContent(
            "来源模块",
            value: "\(model.modules.filter(\.isEnabled).count) / \(model.modules.count) 已启用"
        )

        LabeledContent("配置与同步目录") {
            HStack(spacing: 8) {
                Text("iCloud/Surge/Surge Relay")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    model.openConfigurationDirectory()
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help("在 Finder 中显示模块配置目录")
            }
        }

        Picker("模块检查频率", selection: Binding(
            get: { model.settings.refreshIntervalMinutes },
            set: {
                model.settings.refreshIntervalMinutes = $0
                model.saveSettings()
                model.restartScheduler()
            }
        )) {
            Text("手动").tag(0)
            Text("每 15 分钟").tag(15)
            Text("每小时").tag(60)
            Text("每 6 小时").tag(360)
            Text("每 12 小时").tag(720)
        }

        Toggle("自动同步模块", isOn: Binding(
            get: { model.settings.automaticallyPublish },
            set: { model.settings.automaticallyPublish = $0; model.saveSettings() }
        ))

        ForEach(RelayPlatform.allCases) { platform in
            Toggle("生成模块汇总（\(platform.summaryDisplayName)）", isOn: Binding(
                get: { model.settings.platformSettings[platform.rawValue]?.isEnabled ?? false },
                set: { model.setPlatformEnabled(platform: platform, isEnabled: $0) }
            ))
        }

        Text(model.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var webSettings: some View {
        if model.deviceMode == .client {
            Label(
                "客户端模式下无法再次开启 Web 服务，请前往 Surge Shallow 服务器端进行模块管理。",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Toggle("启用 Web 管理", isOn: Binding(
                get: { model.settings.webServerEnabled },
                set: {
                    model.settings.webServerEnabled = $0
                    model.applyWebServerSettings()
                }
            ))
            TextField("端口", value: Binding(
                get: { model.settings.webServerPort },
                set: { model.settings.webServerPort = $0 }
            ), format: .number.grouping(.never))
            .onChange(of: model.settings.webServerPort) { _, _ in
                if model.settings.webServerEnabled {
                    model.applyWebServerSettings()
                }
            }
            if let url = model.webManagementURL {
                LabeledContent("Bonjour 地址") {
                    Text(url.absoluteString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("打开", systemImage: "safari") { NSWorkspace.shared.open(url) }
                    Button("二维码", systemImage: "qrcode") { showsWebQRCode = true }
                }
            }
        }
    }

    @ViewBuilder
    private var ponteSettings: some View {
        Picker("此 Mac 用作", selection: Binding(
            get: { model.deviceMode },
            set: { mode in Task { await model.setDeviceMode(mode) } }
        )) {
            Text("服务器模式").tag(RelayDeviceMode.server)
            Text("客户端模式").tag(RelayDeviceMode.client)
        }
        .pickerStyle(.segmented)

        if model.deviceMode == .client {
            Text("输入服务器 Mac 的 Surge Ponte 地址，以远程管理模块。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("服务器地址")
                TextField("", text: $ponteServerAddressInput, prompt: Text("johnsmac.sgponte"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: ponteServerAddressInput) { _, _ in connectionResult = nil }
                Button("测试连接") {
                    Task {
                        isTesting = true
                        defer { isTesting = false }
                        do {
                            try await model.testPonteServer(address: ponteServerAddressInput)
                            ponteServerAddressInput = model.ponteServerAddress
                            connectionResult = .success("Ponte 服务器连接成功，地址已生效。")
                        } catch {
                            connectionResult = .failure(error.localizedDescription)
                        }
                    }
                }
                .disabled(isTesting || candidatePonteManagementURL == nil)
            }
            if let result = connectionResult {
                Label(
                    result.message,
                    systemImage: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(result.isError ? .red : .green)
            }
        } else if model.settings.webServerEnabled, model.webManagementURL != nil {
            Label("服务器已就绪", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            LabeledContent("Web 管理端口") { Text(String(model.settings.webServerPort)) }
            Text("其他 Mac 可通过此 Mac 的 Ponte 名称和该端口建立连接。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("需要启用 Web 管理服务", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("请先在“Web 管理”分类中启用服务，客户端才能通过 Surge Ponte 连接此 Mac。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var candidatePonteManagementURL: URL? {
        RelayDeviceConfiguration.managementURL(
            address: ponteServerAddressInput,
            defaultPort: model.settings.webServerPort
        )
    }

    @ViewBuilder
    private var scriptHubSettings: some View {
        LabeledContent("版本") {
            Text(model.upstreamState.revision.map { String($0.prefix(7)) } ?? "—")
                .monospaced()
        }
        LabeledContent("上次检查") {
            Text(model.upstreamState.lastCheckedAt?.formatted(Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: Locale(identifier: "zh_CN")
            )) ?? "尚未检查")
                .foregroundStyle(.secondary)
        }
        TextField("上游模块", text: Binding(
            get: { model.settings.scriptHubModuleURL },
            set: {
                model.settings.scriptHubModuleURL = $0
                if model.isClientMode {
                    Task { await model.pushRemoteScriptHubSettings() }
                } else {
                    model.saveSettings()
                }
            }
        ))
        Toggle("自动更新", isOn: Binding(
            get: { model.settings.automaticallyUpdateScriptHub },
            set: {
                model.settings.automaticallyUpdateScriptHub = $0
                if model.isClientMode {
                    Task { await model.pushRemoteScriptHubSettings() }
                } else {
                    model.saveSettings()
                }
            }
        ))
        HStack(spacing: 8) {
            Button("检查更新", systemImage: "arrow.clockwise") {
                Task {
                    isCheckingUpdate = true
                    await model.refreshScriptHub(showProgress: false)
                    isCheckingUpdate = false
                }
            }
            .disabled(isCheckingUpdate)
            if isCheckingUpdate {
                ProgressView().controlSize(.small)
                Text("正在检查…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if let error = model.upstreamState.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var synchronizationSettings: some View {
        Picker("同步方式", selection: storageModeBinding) {
            Text("iCloud 云盘").tag(StorageMode.local)
            Text("GitHub 私有仓库").tag(StorageMode.gitHub)
        }
        .pickerStyle(.segmented)
        .transaction { transaction in transaction.animation = nil }

        if effectiveStorageMode == .local {
            storageProviderSummary(
                assetName: "iCloudIcon",
                title: "通过 iCloud 保持模块同步",
                detail: "汇总模块保存在 iCloud 云盘的 Surge 文件夹中，配置与同步状态由 Surge Shallow 管理。"
            )
            if showsStableICloudStatus {
                Label(
                    "当前通过 iCloud 云盘同步，汇总模块已在 Surge 文件夹中生成，请在 Surge 中启用对应模块。",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
        } else {
            storageProviderSummary(
                assetName: "GitHubIcon",
                title: "通过私有仓库同步",
                detail: "模块管理功能会验证仓库权限，并通过 Cloudflare 提供设备可访问的稳定订阅。"
            )
            TextField("仓库地址", text: $githubRepositoryInput)
                .onChange(of: githubRepositoryInput) { _, _ in connectionResult = nil }
            SecureField("GitHub Token", text: Binding(
                get: { model.githubToken },
                set: { model.githubToken = $0 }
            ))
            .onChange(of: model.githubToken) { _, _ in connectionResult = nil }
            TextField("公共地址", text: $githubCloudflareInput)
                .onChange(of: githubCloudflareInput) { _, _ in connectionResult = nil }
            Text("用于生成可在 Surge 中长期使用的稳定订阅地址。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if showsVerifiedGitHubStatus {
                Label(
                    "GitHub 与 Cloudflare 已验证，汇总模块将通过 GitHub 私有仓库同步并通过 Cloudflare Worker 分发。",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
        }

        if let result = connectionResult {
            Label(
                result.message,
                systemImage: result.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(result.isError ? .red : .green)
            .textSelection(.enabled)
        }
        if let storageActionTitle {
            HStack(spacing: 8) {
                Spacer()
                if isTesting { ProgressView().controlSize(.small) }
                Button(storageActionTitle) { performStorageAction() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(storageActionDisabled)
            }
        }
    }

    private func storageProviderSummary(
        assetName: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var diagnosticsSettings: some View {
        if model.updateHistory.isEmpty {
            Label("暂无更新记录", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            Text("完成一次同步后，结果会显示在这里。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("最近 \(min(model.updateHistory.count, 20)) 条更新")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(model.updateHistory.prefix(20)) { entry in
                diagnosticRow(entry)
            }
        }
        HStack {
            Button("导出诊断…", systemImage: "square.and.arrow.up") { exportDiagnostics() }
            Button("清除历史", role: .destructive) { model.clearUpdateHistory() }
                .disabled(model.updateHistory.isEmpty)
        }
    }

    private func diagnosticRow(_ entry: UpdateHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.moduleName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(entry.outcome.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(diagnosticColor(for: entry.outcome))
                Text(entry.date.formatted(Date.FormatStyle(
                    date: .omitted,
                    time: .shortened,
                    locale: Locale(identifier: "zh_CN")
                )))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .frame(minWidth: 76, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private var formattedGitHubRepository: String {
        let owner = model.settings.github.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = model.settings.github.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return "" }
        return "https://github.com/\(owner)/\(repository)"
    }

    private var hasGitHubConfigurationChanges: Bool {
        githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines) != originalGitHubRepositoryInput ||
            githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines) != originalGitHubCloudflareInput ||
            model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines) != originalGitHubToken
    }

    private var showsVerifiedGitHubStatus: Bool {
        model.settings.storageMode == .gitHub &&
            pendingStorageMode == nil &&
            !hasGitHubConfigurationChanges &&
            model.settings.github.repositoryIsPrivate == true &&
            model.settings.github.hasValidCloudflarePublicBaseURL
    }

    private var showsStableICloudStatus: Bool {
        model.settings.storageMode == .local && pendingStorageMode == nil
    }

    private var storageActionTitle: String? {
        if let pendingStorageMode {
            return pendingStorageMode == .gitHub
                ? "验证并切换到 GitHub"
                : "切换到 iCloud 云盘"
        }
        guard model.settings.storageMode == .gitHub else { return nil }
        return hasGitHubConfigurationChanges || model.settings.github.repositoryIsPrivate != true
            ? "验证并保存配置"
            : nil
    }

    private func loadGitHubDraftIfNeeded() {
        guard !didLoadGitHubDraft else { return }
        githubRepositoryInput = formattedGitHubRepository
        githubCloudflareInput = model.settings.github.publicBaseURL
        originalGitHubRepositoryInput = githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubCloudflareInput = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubToken = model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        didLoadGitHubDraft = true
    }

    private func markGitHubDraftAsSaved() {
        originalGitHubRepositoryInput = githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubCloudflareInput = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        originalGitHubToken = model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var storageActionDisabled: Bool {
        if isTesting { return true }
        let targetMode = pendingStorageMode ?? model.settings.storageMode
        guard targetMode == .gitHub else { return false }
        return parsedGitHubRepository == nil ||
            model.githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !hasValidCloudflareInput
    }

    private var hasValidCloudflareInput: Bool {
        let value = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return false
        }
        return true
    }

    private var parsedGitHubRepository: (owner: String, repository: String)? {
        let value = githubRepositoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let path: String
        if let components = URLComponents(string: value),
           let host = components.host?.lowercased(),
           host == "github.com" || host == "www.github.com" {
            path = components.path
        } else {
            path = value
        }

        let parts = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count == 2 else { return nil }
        let owner = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = parts[1]
            .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return nil }
        return (owner, repository)
    }

    private func applyGitHubInputs() -> Bool {
        guard let repository = parsedGitHubRepository else {
            connectionResult = .failure("请输入有效的 GitHub 仓库地址，例如 https://github.com/owner/repository。")
            return false
        }
        guard hasValidCloudflareInput else {
            connectionResult = .failure("请输入有效的 Cloudflare 公共地址。")
            return false
        }
        model.settings.github.owner = repository.owner
        model.settings.github.repository = repository.repository
        if model.settings.github.branch.isEmpty { model.settings.github.branch = "main" }
        if model.settings.github.directory.isEmpty { model.settings.github.directory = "modules" }
        model.settings.github.publicBaseURL = githubCloudflareInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isClientMode {
            Task { await model.pushRemoteSyncSettings() }
        } else {
            model.saveSettings()
        }
        return true
    }

    private func performStorageAction() {
        let targetMode = pendingStorageMode ?? model.settings.storageMode
        if targetMode == .gitHub, !applyGitHubInputs() { return }

        if let pendingStorageMode {
            confirmStorageSwitch(to: pendingStorageMode)
        } else {
            testGitHubConnection()
        }
    }

    private func testGitHubConnection() {
        Task {
            isTesting = true
            connectionResult = nil
            model.presentedError = nil
            await model.testGitHub(showProgress: false)
            isTesting = false
            if let error = model.presentedError {
                connectionResult = .failure(error)
                model.presentedError = nil
            } else {
                model.saveGitHubToken()
                markGitHubDraftAsSaved()
                connectionResult = nil
            }
        }
    }

    private var storageModeBinding: Binding<StorageMode> {
        Binding(
            get: { effectiveStorageMode },
            set: { mode in
                connectionResult = nil
                if mode == model.settings.storageMode {
                    pendingStorageMode = nil
                } else {
                    pendingStorageMode = mode
                }
            }
        )
    }

    private var effectiveStorageMode: StorageMode {
        pendingStorageMode ?? model.settings.storageMode
    }

    private func confirmStorageSwitch(to mode: StorageMode) {
        Task {
            isTesting = true
            connectionResult = nil
            model.presentedError = nil
            let switched = await model.setStorageMode(mode)
            isTesting = false
            if switched {
                pendingStorageMode = nil
                if mode == .gitHub {
                    markGitHubDraftAsSaved()
                    connectionResult = nil
                } else {
                    connectionResult = nil
                }
            } else {
                connectionResult = .failure(model.presentedError ?? "切换失败")
                model.presentedError = nil
            }
        }
    }

    private func diagnosticColor(for outcome: UpdateHistoryOutcome) -> Color {
        switch outcome {
        case .updated, .published: .green
        case .unchanged: .secondary
        case .cachedAfterFailure: .orange
        case .failed: .red
        }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                model.settings[keyPath: keyPath] = $0
                model.saveSettings()
            }
        )
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Surge-Relay-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.diagnosticsData().write(to: url, options: .atomic)
        } catch {
            model.presentedError = "无法导出诊断：\(error.localizedDescription)"
        }
    }

    private func qrCodeImage(for value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
