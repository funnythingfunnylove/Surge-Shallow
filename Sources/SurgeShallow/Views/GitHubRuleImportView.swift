import SwiftUI
import SurgeProfileRelayCore

struct GitHubRuleImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var repositoryURL = ""
    @State private var snapshot: GitHubRuleRepositorySnapshot?
    @State private var selectedPaths: Set<String> = []
    @State private var searchText = ""
    @State private var policy = "PROXY"
    @State private var preservesSourcePolicy = false
    @State private var outputMode: RuleSourceOutputMode = .remoteReference
    @State private var platforms = Set(RelayPlatform.allCases)
    @State private var updateIntervalMinutes = 0
    @State private var isEnabled = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onAdd: ([RuleSource]) -> Void
    private let client = GitHubRuleRepositoryClient()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let snapshot {
                repositoryContent(snapshot)
            } else if isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在读取 GitHub 仓库文件树…")
                        .font(.headline)
                    Text("公开仓库无需 Token；大型仓库可能需要几秒钟。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("解析 GitHub 规则库", systemImage: "shippingbox")
                } description: {
                    Text("支持仓库首页、tree 子目录和 blob 文件 URL。解析后可以搜索、多选并一次添加多个规则源。")
                }
            }

            Divider()
            footer
        }
        .frame(width: 980, height: 720)
        .onAppear {
            if !RelayPolicyCatalog.allNames(in: model.document.sharedProfile).contains(policy) {
                policy = RelayPolicyCatalog.groupNames(in: model.document.sharedProfile).first ?? "DIRECT"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("从 GitHub 批量添加")
                        .font(.title2.weight(.semibold))
                    Text("粘贴公开仓库 URL，Relay 会递归发现常见 Surge、Clash 和域名规则文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link(
                    "GitHub Contents API",
                    destination: URL(string: "https://docs.github.com/en/rest/repos/contents")!
                )
                    .font(.caption)
            }

            HStack(spacing: 10) {
                TextField(
                    "https://github.com/owner/rules 或 …/tree/main/Surge",
                    text: $repositoryURL
                )
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                .onSubmit { Task { await discover() } }

                Button {
                    Task { await discover() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("解析仓库", systemImage: "arrow.triangle.branch")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isLoading || repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private func repositoryContent(_ snapshot: GitHubRuleRepositorySnapshot) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(snapshot.owner)/\(snapshot.repository)")
                                .font(.headline)
                            Text("\(snapshot.reference) · \(snapshot.files.count) 个候选文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("全选") {
                            selectedPaths.formUnion(selectableFiles.map(\.path))
                        }
                        .disabled(selectableFiles.isEmpty)
                        Button("清空") { selectedPaths.removeAll() }
                            .disabled(selectedPaths.isEmpty)
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索文件名或路径", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.primary.opacity(0.1))
                    }
                }
                .padding(14)

                List {
                    ForEach(filteredFiles) { file in
                        let duplicate = existingURLs.contains(file.downloadURL.lowercased())
                        Toggle(
                            isOn: Binding(
                                get: { selectedPaths.contains(file.path) },
                                set: { selected in
                                    if selected { selectedPaths.insert(file.path) }
                                    else { selectedPaths.remove(file.path) }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 7) {
                                    Text(file.fileName)
                                        .font(.subheadline.weight(.medium))
                                    if duplicate {
                                        Text("已添加")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                Text(file.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(file.suggestedFormat.displayName)
                                    if let size = file.size {
                                        Text("· \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(duplicate)
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 500, idealWidth: 610)

            Form {
                Section("批量设置") {
                    RelayPolicyPicker(
                        title: "目标策略",
                        selection: $policy,
                        sharedProfile: model.document.sharedProfile
                    )
                    Toggle("保留上游策略", isOn: $preservesSourcePolicy)
                    Picker("生成方式", selection: $outputMode) {
                        ForEach(RuleSourceOutputMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("启用新规则源", isOn: $isEnabled)
                }

                Section("适用平台") {
                    ForEach(RelayPlatform.allCases) { platform in
                        Toggle(
                            platform.displayName,
                            isOn: Binding(
                                get: { platforms.contains(platform) },
                                set: { enabled in
                                    if enabled { platforms.insert(platform) }
                                    else { platforms.remove(platform) }
                                }
                            )
                        )
                    }
                }

                if outputMode == .inlineMerged {
                    Section("本地处理") {
                        Picker("处理频率", selection: $updateIntervalMinutes) {
                            Text("使用全局设置").tag(0)
                            Text("每 15 分钟").tag(15)
                            Text("每小时").tag(60)
                            Text("每 6 小时").tag(360)
                            Text("每天").tag(1_440)
                        }
                    }
                }

                Section("格式识别") {
                    Text(outputMode == .remoteReference
                         ? "普通规则文本会作为 Surge Ruleset 外部引用；只记录链接，不下载或更新正文。Clash payload 与完整 Profile 仍会在本地转换后输出。"
                         : "已识别为 Surge Ruleset 的文件仍只保留链接；.yaml/.yml 与完整 Profile 等其他格式会在合并生成时执行本地转换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 300, idealWidth: 340)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerMessage)
                .font(.caption)
                .foregroundStyle(canAdd ? Color.secondary : Color.red)
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("添加 \(selectedPaths.count) 个规则源") {
                onAdd(makeSources())
                dismiss()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdd)
        }
        .padding(16)
    }

    private var filteredFiles: [GitHubRuleFile] {
        guard let snapshot else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return snapshot.files }
        return snapshot.files.filter {
            $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectableFiles: [GitHubRuleFile] {
        snapshot?.files.filter { !existingURLs.contains($0.downloadURL.lowercased()) } ?? []
    }

    private var existingURLs: Set<String> {
        Set(model.document.sources.map {
            $0.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
    }

    private var canAdd: Bool {
        !selectedPaths.isEmpty
            && !policy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !platforms.isEmpty
            && !model.isRefreshing
    }

    private var footerMessage: String {
        if platforms.isEmpty { return "请至少选择一个平台。" }
        if selectedPaths.isEmpty { return "请选择至少一个尚未添加的规则文件。" }
        return "将创建独立规则源；Surge Ruleset 只保存链接，其他格式可分别调整本地处理频率。"
    }

    @MainActor
    private func discover() async {
        isLoading = true
        errorMessage = nil
        snapshot = nil
        selectedPaths.removeAll()
        defer { isLoading = false }
        do {
            let result = try await client.discover(repositoryURL: repositoryURL)
            snapshot = result
            selectedPaths = Set(
                result.files
                    .filter { !existingURLs.contains($0.downloadURL.lowercased()) }
                    .map(\.path)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeSources() -> [RuleSource] {
        guard let snapshot else { return [] }
        var usedNames = Set(model.document.sources.map { $0.name.lowercased() })
        return snapshot.files.filter { selectedPaths.contains($0.path) }.map { file in
            let name = uniqueName(base: file.sourceName, path: file.path, usedNames: &usedNames)
            let canReference = file.suggestedFormat == .automatic || file.suggestedFormat == .surgeRuleset
            let mustReference = file.suggestedFormat == .surgeRuleset
            let selectedOutputMode: RuleSourceOutputMode = (mustReference || outputMode == .remoteReference) && canReference
                ? .remoteReference
                : .inlineMerged
            return RuleSource(
                name: name,
                url: file.downloadURL,
                format: selectedOutputMode == .remoteReference ? .surgeRuleset : file.suggestedFormat,
                policy: policy,
                preservesSourcePolicy: selectedOutputMode == .inlineMerged && preservesSourcePolicy,
                outputMode: selectedOutputMode,
                isEnabled: isEnabled,
                platforms: platforms,
                updateIntervalMinutes: selectedOutputMode == .remoteReference ? 0 : updateIntervalMinutes
            )
        }
    }

    private func uniqueName(base: String, path: String, usedNames: inout Set<String>) -> String {
        if usedNames.insert(base.lowercased()).inserted { return base }
        let parent = URL(filePath: path).deletingLastPathComponent().lastPathComponent
        let qualified = parent.isEmpty ? base : "\(parent) · \(base)"
        if usedNames.insert(qualified.lowercased()).inserted { return qualified }
        var suffix = 2
        while !usedNames.insert("\(qualified) \(suffix)".lowercased()).inserted {
            suffix += 1
        }
        return "\(qualified) \(suffix)"
    }
}
