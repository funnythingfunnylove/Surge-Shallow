import SwiftUI
import SurgeProfileRelayCore

struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var editedSource: RuleSource?
    @State private var showsGitHubImporter = false

    var body: some View {
        @Bindable var model = model

        HSplitView {
            VStack(spacing: 0) {
                if model.document.sources.isEmpty {
                    ContentUnavailableView {
                        Label("添加第一个规则源", systemImage: "link.badge.plus")
                    } description: {
                        Text("支持 Surge 规则列表、完整 Profile、域名列表和 Clash payload。")
                    } actions: {
                        HStack {
                            Button("添加规则源", action: addSource)
                                .buttonStyle(.glassProminent)
                            Button("解析 GitHub 规则库") {
                                showsGitHubImporter = true
                            }
                        }
                    }
                } else {
                    List(selection: $model.selectedSourceID) {
                        ForEach(model.document.sources) { source in
                            SourceRow(source: source)
                                .tag(source.id)
                                .contextMenu {
                                    Button("编辑") { editedSource = source }
                                    Button("删除", role: .destructive) { model.deleteSource(source.id) }
                                }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(minWidth: 360, idealWidth: 460)

            Group {
                if let source = selectedSource {
                    SourceDetailView(
                        source: source,
                        editAction: { editedSource = source },
                        deleteAction: { model.deleteSource(source.id) }
                    )
                } else {
                    ContentUnavailableView(
                        "选择规则源",
                        systemImage: "sidebar.right",
                        description: Text("在左侧选择一个 URL 查看更新状态和合并策略。")
                    )
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("规则源")
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button(action: addSource) {
                    Label("添加", systemImage: "plus")
                }
                Button {
                    showsGitHubImporter = true
                } label: {
                    Label("从 GitHub 批量添加", systemImage: "shippingbox.and.arrow.backward")
                }
                Button {
                    if let selectedSource { editedSource = selectedSource }
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(selectedSource == nil)
                Button {
                    if let id = model.selectedSourceID { model.moveSource(id, offset: -1) }
                } label: {
                    Label("上移", systemImage: "arrow.up")
                }
                .disabled(!canMoveSelected(by: -1))
                Button {
                    if let id = model.selectedSourceID { model.moveSource(id, offset: 1) }
                } label: {
                    Label("下移", systemImage: "arrow.down")
                }
                .disabled(!canMoveSelected(by: 1))
            }
        }
        .sheet(item: $editedSource) { source in
            SourceEditorView(
                source: source,
                isNew: !model.document.sources.contains(where: { $0.id == source.id }),
                onSave: { model.upsertSource($0) }
            )
        }
        .sheet(isPresented: $showsGitHubImporter) {
            GitHubRuleImportView { sources in
                model.addSources(sources)
            }
        }
        .onAppear {
            if model.selectedSourceID == nil {
                model.selectedSourceID = model.document.sources.first?.id
            }
        }
    }

    private var selectedSource: RuleSource? {
        guard let id = model.selectedSourceID else { return nil }
        return model.document.sources.first(where: { $0.id == id })
    }

    private func addSource() {
        editedSource = RuleSource(name: "", url: "")
    }

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let id = model.selectedSourceID,
              let index = model.document.sources.firstIndex(where: { $0.id == id }) else { return false }
        return model.document.sources.indices.contains(index + offset)
    }
}

private struct SourceRow: View {
    @Environment(AppModel.self) private var model
    let source: RuleSource

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { source.isEnabled },
                    set: { model.setSourceEnabled(source.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(source.hostDisplayName)
                        .lineLimit(1)
                    if source.lastRuleCount > 0 {
                        Text("· \(source.lastRuleCount) 条")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusPill(state: source.state)
        }
        .padding(.vertical, 5)
        .opacity(source.isEnabled ? 1 : 0.55)
    }
}

private struct SourceDetailView: View {
    @Environment(AppModel.self) private var model
    let source: RuleSource
    let editAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(source.name)
                            .font(.largeTitle.weight(.semibold))
                        Text(source.isEmbedded ? "由已导入 Profile 内嵌并随 iCloud 管理配置同步" : source.url)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    StatusPill(state: source.state)
                }

                RelayCard {
                    Grid(alignment: .leading, horizontalSpacing: 34, verticalSpacing: 12) {
                        detailRow("格式", source.format.displayName)
                        detailRow("合并策略", source.preservesSourcePolicy ? "保留上游策略（缺失时用 \(source.policy)）" : "统一改写为 \(source.policy)")
                        if source.format == .surgeRuleset {
                            detailRow(
                                "Ruleset 参数",
                                (source.rulesetOptions ?? []).isEmpty
                                    ? "无"
                                    : (source.rulesetOptions ?? [])
                                        .map(\.rawValue)
                                        .sorted()
                                        .joined(separator: "、")
                            )
                        }
                        detailRow("平台", source.platforms.map(\.displayName).sorted().joined(separator: "、"))
                        detailRow("更新频率", source.updateIntervalMinutes == 0 ? "使用全局设置" : "每 \(source.updateIntervalMinutes) 分钟")
                        detailRow("缓存标识", source.etag ?? source.contentHash?.prefix(12).description ?? "尚无")
                    }
                }

                if let date = source.lastCheckedAt {
                    Label("上次检查：\(date.formatted(date: .abbreviated, time: .standard))", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }

                if let error = source.lastError {
                    RelayCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("最近一次上游错误", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(error)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Button("编辑规则源", action: editAction)
                        .buttonStyle(.glassProminent)
                    Button("删除", role: .destructive, action: deleteAction)
                    Spacer()
                    Button("检查全部上游") {
                        Task { await model.refresh(force: true) }
                    }
                    .disabled(model.isRefreshing)
                }
            }
            .padding(26)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct SourceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var draft: RuleSource
    let isNew: Bool
    let onSave: (RuleSource) -> Void

    init(source: RuleSource, isNew: Bool, onSave: @escaping (RuleSource) -> Void) {
        _draft = State(initialValue: source)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var isValid: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let policy = draft.policy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !policy.isEmpty,
              !policy.contains(","),
              !policy.contains("\n"),
              !policy.contains("\r") else { return false }
        if !draft.isEmbedded {
            guard RemoteRulesetReference.parse(draft.url) != nil
                    || RemoteRulesetReference.isRemoteURL(draft.url) else { return false }
        }
        return !draft.platforms.isEmpty && (draft.embeddedContent?.isEmpty == false || !draft.isEmbedded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("规则源") {
                    TextField("名称", text: $draft.name, prompt: Text("例如：广告拦截"))
                    if draft.isEmbedded {
                        LabeledContent("内容") {
                            Text("内嵌规则 · \(draft.embeddedContent?.split(separator: "\n").count ?? 0) 行")
                                .foregroundStyle(.secondary)
                        }
                        Text("内嵌内容来自 Profile 迁移，会随 relay.json 同步到其他 Mac；如需替换，请重新执行完整 Profile 导入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("URL", text: $draft.url, prompt: Text("https://example.com/rules.list"))
                            .textContentType(.URL)
                        Text("可直接粘贴远端 URL，或完整的 RULE-SET,URL,策略,no-resolve,extended-matching 指令。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("内容格式", selection: $draft.format) {
                        ForEach(RuleSourceFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }

                Section("合并") {
                    RelayPolicyPicker(
                        title: "目标策略",
                        selection: $draft.policy,
                        sharedProfile: model.document.sharedProfile
                    )
                    if draft.format == .surgeRuleset {
                        Text("Surge 外部 Ruleset 的每一行不包含策略；Relay 下载、缓存并展开后统一使用上面的目标策略。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(RuleSourceRulesetOption.allCases) { option in
                            Toggle(isOn: rulesetOptionBinding(option)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Toggle("保留上游规则中的策略", isOn: $draft.preservesSourcePolicy)
                        Text(draft.preservesSourcePolicy
                             ? "只有缺少策略的行才会使用上面的目标策略。"
                             : "每条上游规则的策略都会统一改写，便于集中管理。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("适用平台") {
                    ForEach(RelayPlatform.allCases) { platform in
                        Toggle(
                            platform.displayName,
                            isOn: Binding(
                                get: { draft.platforms.contains(platform) },
                                set: { enabled in
                                    if enabled { draft.platforms.insert(platform) }
                                    else { draft.platforms.remove(platform) }
                                }
                            )
                        )
                    }
                }

                Section("更新") {
                    Picker("检查频率", selection: $draft.updateIntervalMinutes) {
                        Text("使用全局设置").tag(0)
                        Text("每 15 分钟").tag(15)
                        Text("每小时").tag(60)
                        Text("每 6 小时").tag(360)
                        Text("每天").tag(1_440)
                    }
                    Toggle("启用此规则源", isOn: $draft.isEnabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(isValid
                     ? "保存后可立即执行首次检查。"
                     : (draft.isEmbedded ? "请填写名称、策略并至少选择一个平台。" : "请填写有效的 HTTP(S) URL、名称、策略和至少一个平台。"))
                    .font(.caption)
                    .foregroundStyle(isValid ? Color.secondary : Color.red)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") {
                    if let reference = RemoteRulesetReference.parse(draft.url) {
                        draft.url = reference.url
                        draft.policy = reference.policy
                        draft.format = .surgeRuleset
                        draft.rulesetOptions = reference.options
                    }
                    if draft.format == .surgeRuleset {
                        draft.preservesSourcePolicy = false
                    }
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.policy = draft.policy.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || model.isRefreshing)
            }
            .padding(16)
        }
        .frame(width: 620, height: 630)
        .navigationTitle(isNew ? "添加规则源" : "编辑规则源")
        .onChange(of: draft.url) { _, newValue in
            guard let reference = RemoteRulesetReference.parse(newValue) else { return }
            draft.url = reference.url
            draft.policy = reference.policy
            draft.format = .surgeRuleset
            draft.preservesSourcePolicy = false
            draft.rulesetOptions = reference.options
        }
    }

    private func rulesetOptionBinding(_ option: RuleSourceRulesetOption) -> Binding<Bool> {
        Binding(
            get: { draft.rulesetOptions?.contains(option) == true },
            set: { enabled in
                var options = draft.rulesetOptions ?? []
                if enabled { options.insert(option) } else { options.remove(option) }
                draft.rulesetOptions = options
            }
        )
    }
}
