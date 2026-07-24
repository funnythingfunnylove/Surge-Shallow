import SwiftUI
import SurgeProfileRelayCore

struct SourcesView: View {
    @Environment(AppModel.self) private var model
    @State private var editedSource: RuleSource?
    @State private var showsGitHubImporter = false
    @State private var showsRulePresets = false

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
                        VStack(spacing: SurgeSpacing.sm) {
                            HStack {
                                Button("添加远程规则源", action: addSource)
                                    .buttonStyle(.glassProminent)
                                Button("添加手工规则", action: addManualSource)
                            }
                            HStack {
                                Button("GitHub 批量添加") {
                                    showsGitHubImporter = true
                                }
                                Button("一键规则集") {
                                    showsRulePresets = true
                                }
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
            .frame(width: 360)

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
                        description: Text("在左侧选择一个 URL 查看引用方式和合并策略。")
                    )
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("规则源")
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Menu {
                    Button("远程规则源", systemImage: "link.badge.plus", action: addSource)
                    Button("手工规则", systemImage: "text.badge.plus", action: addManualSource)
                } label: {
                    Label("添加", systemImage: "plus")
                }
                Button {
                    showsGitHubImporter = true
                } label: {
                    Label("从 GitHub 批量添加", systemImage: "shippingbox.and.arrow.backward")
                }
                Button {
                    showsRulePresets = true
                } label: {
                    Label("一键规则集", systemImage: "wand.and.stars")
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
        .sheet(isPresented: $showsRulePresets) {
            RulePresetInstallView()
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
        editedSource = RuleSource(name: "", url: "", format: .surgeRuleset)
    }

    private func addManualSource() {
        editedSource = RuleSource.manual()
    }

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let id = model.selectedSourceID,
              let index = model.document.sources.firstIndex(where: { $0.id == id }) else { return false }
        return model.document.sources.indices.contains(index + offset)
    }
}

private struct RulePresetInstallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var selectedPreset: RuleRoutingPreset = .comprehensiveWhitelist
    @State private var proxyPolicy = ""

    private let columns = [
        GridItem(.flexible(), spacing: SurgeSpacing.sm),
        GridItem(.flexible(), spacing: SurgeSpacing.sm),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: SurgeSpacing.md) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(SurgePalette.accent)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("一键规则集")
                        .font(.title2.weight(.semibold))
                    Text("组合 Loyalsoldier/surge-rules 与 ruleset.skk.moe，并按 Surge 匹配顺序安装。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let activePreset {
                    Label("当前：\(activePreset.title)", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SurgePalette.accent)
                }
            }
            .padding(SurgeSpacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: SurgeSpacing.md) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: SurgeSpacing.sm) {
                        ForEach(RuleRoutingPreset.allCases) { preset in
                            presetButton(preset)
                        }
                    }

                    RelayCard {
                        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
                            HStack {
                                Label(selectedPreset.title, systemImage: symbol(for: selectedPreset))
                                    .font(.headline)
                                Spacer()
                                Text("\(selectedPreset.sourceDefinitions.count) 个远端 Ruleset")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(selectedPreset.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            LabeledContent("规则顺序") {
                                Text("手工规则 → non_ip → ip → FINAL")
                            }
                            LabeledContent("兜底行为") {
                                Text(selectedPreset.finalPolicyDescription)
                                    .fontWeight(.semibold)
                            }
                            LabeledContent("规则来源") {
                                HStack(spacing: SurgeSpacing.sm) {
                                    Link("Loyalsoldier", destination: URL(string: "https://github.com/Loyalsoldier/surge-rules")!)
                                    Link("Sukka", destination: URL(string: "https://ruleset.skk.moe")!)
                                }
                            }
                        }
                    }

                    RelayCard {
                        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
                            Text("代理策略")
                                .font(.headline)
                            if availablePolicies.isEmpty {
                                Label(
                                    "还没有可用的 Proxy 或 Proxy Group。请先创建代理策略，再使用一键规则集。",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.callout)
                                .foregroundStyle(.orange)
                                Button("前往 Proxy") {
                                    dismiss()
                                    model.selection = .proxy
                                }
                            } else {
                                Picker("命中代理规则时", selection: $proxyPolicy) {
                                    if !groupNames.isEmpty {
                                        Section("Proxy Group") {
                                            ForEach(groupNames, id: \.self) { Text($0).tag($0) }
                                        }
                                    }
                                    if !proxyNames.isEmpty {
                                        Section("Proxy") {
                                            ForEach(proxyNames, id: \.self) { Text($0).tag($0) }
                                        }
                                    }
                                }
                                Text("预设不会创建或修改 Proxy。命中代理规则以及白名单模式的 FINAL 会使用这里选择的现有策略。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Label(
                        "应用时只替换此前由“一键规则集”管理的来源；手工添加的规则源会保留在最前面并继续拥有更高优先级。",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(SurgeSpacing.lg)
            }

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("应用 \(selectedPreset.title)") {
                    if model.applyRulePreset(selectedPreset, proxyPolicy: proxyPolicy) {
                        dismiss()
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canApply)
                .accessibilityIdentifier("apply-rule-preset")
            }
            .padding(SurgeSpacing.md)
        }
        .frame(width: 700, height: 720)
        .background(SurgeBackground())
        .onAppear(perform: selectInitialPolicy)
    }

    private var activePreset: RuleRoutingPreset? {
        RuleRoutingPreset.active(in: model.document)
    }

    private var proxyNames: [String] {
        RelayPolicyCatalog.proxyNames(in: model.document.sharedProfile)
    }

    private var groupNames: [String] {
        RelayPolicyCatalog.groupNames(in: model.document.sharedProfile)
    }

    private var availablePolicies: [String] {
        groupNames + proxyNames
    }

    private var canApply: Bool {
        availablePolicies.contains { $0.caseInsensitiveCompare(proxyPolicy) == .orderedSame }
    }

    private func selectInitialPolicy() {
        if let activePreset {
            selectedPreset = activePreset
        }
        guard !canApply else { return }
        let managedPolicy = model.document.sources
            .filter { $0.managedPresetID != nil }
            .map(\.policy)
            .first { candidate in
                availablePolicies.contains {
                    $0.caseInsensitiveCompare(candidate) == .orderedSame
                }
            }
        proxyPolicy = managedPolicy
            ?? groupNames.first { $0.caseInsensitiveCompare("PROXY") == .orderedSame }
            ?? groupNames.first
            ?? proxyNames.first
            ?? ""
    }

    private func symbol(for preset: RuleRoutingPreset) -> String {
        switch preset {
        case .comprehensiveWhitelist: "globe.asia.australia.fill"
        case .comprehensiveBlacklist: "globe.asia.australia"
        case .domesticWhitelist: "checkmark.shield.fill"
        case .domesticBlacklist: "shield.lefthalf.filled"
        }
    }

    private func presetButton(_ preset: RuleRoutingPreset) -> some View {
        Button {
            selectedPreset = preset
        } label: {
            HStack(alignment: .top, spacing: SurgeSpacing.sm) {
                Image(systemName: symbol(for: preset))
                    .font(.title3)
                    .foregroundStyle(selectedPreset == preset ? SurgePalette.accent : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(.headline)
                    Text(preset.shortDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selectedPreset == preset {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SurgePalette.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .padding(SurgeSpacing.md)
            .background(
                .primary.opacity(selectedPreset == preset ? 0.075 : 0.035),
                in: RoundedRectangle(cornerRadius: SurgeRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SurgeRadius.control, style: .continuous)
                    .strokeBorder(
                        selectedPreset == preset ? SurgePalette.accent.opacity(0.8) : .primary.opacity(0.07),
                        lineWidth: selectedPreset == preset ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rule-preset-\(preset.id)")
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
                HStack(spacing: 5) {
                    Text(source.name)
                        .font(.headline)
                        .lineLimit(1)
                    if source.managedPresetID != nil {
                        Image(systemName: "wand.and.stars")
                            .font(.caption2)
                            .foregroundStyle(SurgePalette.accent)
                            .help("由一键规则集管理")
                    }
                }
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
            SourceModePill(source: source)
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
                        Text(source.isManual
                             ? "手工维护，内容存储在 relay.json 并随管理配置同步"
                             : (source.isEmbedded ? "由已导入 Profile 内嵌并随 iCloud 管理配置同步" : source.url))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    SourceModePill(source: source)
                }

                RelayCard {
                    Grid(alignment: .leading, horizontalSpacing: 34, verticalSpacing: 12) {
                        detailRow("格式", source.format.displayName)
                        detailRow(
                            "输出方式",
                            source.isManual
                                ? source.resolvedManualPublicationMode.displayName
                                : source.resolvedOutputMode.displayName
                        )
                        if source.publishesDetachedProfile {
                            detailRow("独立文件", source.resolvedDetachedFileName)
                        }
                        if source.resolvedOutputMode == .remoteReference {
                            detailRow("目标策略", source.policy)
                        } else {
                            detailRow("合并策略", source.preservesSourcePolicy ? "保留上游策略（缺失时用 \(source.policy)）" : "统一改写为 \(source.policy)")
                        }
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
                        if let presetID = source.managedPresetID,
                           let preset = RuleRoutingPreset(rawValue: presetID) {
                            detailRow("一键预设", preset.title)
                        }
                        detailRow("平台", source.platforms.map(\.displayName).sorted().joined(separator: "、"))
                        if source.isManual {
                            detailRow("存储", "规则正文保存在 relay.json，不访问远端网络")
                        } else if source.resolvedOutputMode == .remoteReference {
                            detailRow("加载方式", "由 Surge 直接加载，不写入规则正文")
                        } else {
                            detailRow("本地处理频率", source.updateIntervalMinutes == 0 ? "使用全局设置" : "每 \(source.updateIntervalMinutes) 分钟")
                            detailRow("缓存标识", source.etag ?? source.contentHash?.prefix(12).description ?? "尚无")
                        }
                    }
                }

                if !source.isManual,
                   source.resolvedOutputMode == .inlineMerged,
                   let date = source.lastCheckedAt {
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
                    Button("合并生成") {
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
        if draft.isManual {
            return !draft.platforms.isEmpty && manualAnalysis.error == nil
        }
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
                    if draft.isManual {
                        TextEditor(text: manualContentBinding)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 190)
                            .accessibilityIdentifier("manual-rule-content")
                        Text("每行一条 Surge 规则；支持同时粘贴多条。注释、空行会忽略，FINAL 由目标 Profile 统一管理。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("示例：DOMAIN,example.com,DIRECT\nDOMAIN-SUFFIX,example.org\nIP-CIDR,192.0.2.0/24,no-resolve")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if draft.isEmbedded {
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
                    if !draft.isManual {
                        Picker("内容格式", selection: $draft.format) {
                            ForEach(RuleSourceFormat.allCases) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                    }
                }

                if draft.isManual {
                    Section("发布方式") {
                        Picker("生成方式", selection: manualPublicationModeBinding) {
                            ForEach(ManualRulePublicationMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        Text(draft.resolvedManualPublicationMode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if draft.publishesDetachedProfile {
                            TextField("独立文件名", text: detachedFileNameBinding)
                                .accessibilityIdentifier("manual-rule-dconf-name")
                            Text("保存时会清理路径符号并确保使用 .dconf 后缀；生成文件包含 [Rule]，主 Profile 在当前规则顺序位置通过 #!include 引用。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !draft.isEmbedded && draft.format == .surgeRuleset {
                    Section("引用方式") {
                        LabeledContent("生成方式", value: "外部 Ruleset 引用")
                        Text("只保存 Ruleset 链接、策略与参数，并输出 RULE-SET 指令；正文由 Surge 自行加载，Surge Shallow 不下载、缓存或更新规则集。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !draft.isEmbedded {
                    Section("输出方式") {
                        Picker("生成方式", selection: outputModeBinding) {
                            ForEach(RuleSourceOutputMode.allCases) { mode in
                                Text(mode.displayName)
                                    .tag(mode)
                                    .disabled(mode == .remoteReference && !draft.supportsRemoteRulesetReference)
                            }
                        }
                        Text(draft.resolvedOutputMode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(draft.resolvedOutputMode == .remoteReference ? "规则策略" : "合并") {
                    RelayPolicyPicker(
                        title: "目标策略",
                        selection: $draft.policy,
                        sharedProfile: model.document.sharedProfile
                    )
                    if draft.format == .surgeRuleset {
                        Text(draft.resolvedOutputMode == .remoteReference
                             ? "最终只写入一条 RULE-SET 指令；Surge 直接加载 URL，并应用上面的策略与参数。"
                             : "Surge 外部 Ruleset 的每一行不包含策略；Surge Shallow 下载、缓存并展开后统一使用上面的目标策略。")
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
                    if draft.isManual {
                        Picker("生效范围", selection: manualIncludesIOSBinding) {
                            Text("仅 macOS").tag(false)
                            Text("macOS + iOS / iPadOS").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text(draft.platforms.contains(.iOS)
                             ? "macOS 与 iOS/iPadOS 生成配置都会在相同规则顺序位置应用这组规则。"
                             : "仅 macOS 生成配置会应用这组规则；iOS/iPadOS 不会引用或内联它。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
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
                }

                if draft.isManual {
                    Section("解析检查") {
                        if let error = manualAnalysis.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else {
                            Label("已解析 \(manualAnalysis.ruleCount) 条可用规则", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        ForEach(Array(manualAnalysis.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Text("手工内容同样受全局 \(max(1, model.document.settings.maximumSourceSizeMB)) MB 规则源安全上限约束。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(draft.resolvedOutputMode == .remoteReference ? "引用" : "本地处理") {
                    if draft.isManual {
                        Text("手工规则正文保存在 relay.json，并通过管理配置同步；不访问远端网络，也不需要设置检查频率。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if draft.resolvedOutputMode == .remoteReference {
                        Text("外部 Ruleset 仅记录链接，由 Surge 加载；Surge Shallow 不下载、缓存或更新正文。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("检查频率", selection: $draft.updateIntervalMinutes) {
                            Text("使用全局设置").tag(0)
                            Text("每 15 分钟").tag(15)
                            Text("每小时").tag(60)
                            Text("每 6 小时").tag(360)
                            Text("每天").tag(1_440)
                        }
                    }
                    Toggle("启用此规则源", isOn: $draft.isEnabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(isValid
                     ? (draft.isManual
                        ? (draft.publishesDetachedProfile ? "保存后会生成并引用独立 .dconf。" : "保存后会按顺序内联合并手工规则。")
                        : (draft.resolvedOutputMode == .remoteReference ? "保存后将以紧凑 RULE-SET 引用输出。" : "保存后可立即执行首次检查。"))
                     : (draft.isManual
                        ? "请填写名称、有效策略和至少一条可用规则。"
                        : (draft.isEmbedded ? "请填写名称、策略并至少选择一个平台。" : "请填写有效的 HTTP(S) URL、名称、策略和至少一个平台。")))
                    .font(.caption)
                    .foregroundStyle(isValid ? Color.secondary : Color.red)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") {
                    if draft.isManual {
                        draft.url = ""
                        draft.format = .surgeRuleList
                        draft.outputMode = .inlineMerged
                        draft.platforms = draft.platforms.contains(.iOS)
                            ? Set(RelayPlatform.allCases)
                            : [.macOS]
                        draft.detachedFileName = draft.resolvedDetachedFileName
                    } else if let reference = RemoteRulesetReference.parse(draft.url) {
                        draft.url = reference.url
                        draft.policy = reference.policy
                        draft.format = .surgeRuleset
                        draft.rulesetOptions = reference.options
                        draft.outputMode = .remoteReference
                    }
                    if !draft.isManual,
                       draft.resolvedOutputMode == .remoteReference,
                       draft.format == .automatic {
                        draft.format = .surgeRuleset
                    }
                    if !draft.isManual, draft.format == .surgeRuleset {
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
        .frame(width: 620, height: 700)
        .navigationTitle(
            draft.isManual
                ? (isNew ? "添加手工规则" : "编辑手工规则")
                : (isNew ? "添加规则源" : "编辑规则源")
        )
        .onChange(of: draft.url) { _, newValue in
            guard !draft.isManual else { return }
            guard let reference = RemoteRulesetReference.parse(newValue) else { return }
            draft.url = reference.url
            draft.policy = reference.policy
            draft.format = .surgeRuleset
            draft.preservesSourcePolicy = false
            draft.rulesetOptions = reference.options
            draft.outputMode = .remoteReference
        }
        .onChange(of: draft.format) { _, _ in
            guard !draft.isManual else { return }
            if !draft.isEmbedded && draft.format == .surgeRuleset {
                draft.outputMode = .remoteReference
                draft.updateIntervalMinutes = 0
            } else if draft.resolvedOutputMode == .remoteReference && !draft.supportsRemoteRulesetReference {
                draft.outputMode = .inlineMerged
            }
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

    private var outputModeBinding: Binding<RuleSourceOutputMode> {
        Binding(
            get: { draft.resolvedOutputMode },
            set: { draft.outputMode = $0 }
        )
    }

    private var manualPublicationModeBinding: Binding<ManualRulePublicationMode> {
        Binding(
            get: { draft.resolvedManualPublicationMode },
            set: { draft.manualPublicationMode = $0 }
        )
    }

    private var manualIncludesIOSBinding: Binding<Bool> {
        Binding(
            get: { draft.platforms.contains(.iOS) },
            set: { includesIOS in
                draft.platforms = includesIOS ? Set(RelayPlatform.allCases) : [.macOS]
            }
        )
    }

    private var manualContentBinding: Binding<String> {
        Binding(
            get: { draft.embeddedContent ?? "" },
            set: { draft.embeddedContent = $0 }
        )
    }

    private var detachedFileNameBinding: Binding<String> {
        Binding(
            get: { draft.detachedFileName ?? draft.resolvedDetachedFileName },
            set: { draft.detachedFileName = $0 }
        )
    }

    private var manualAnalysis: (ruleCount: Int, warnings: [String], error: String?) {
        let content = draft.embeddedContent ?? ""
        let maximumMB = max(1, model.document.settings.maximumSourceSizeMB)
        guard Data(content.utf8).count <= maximumMB * 1_024 * 1_024 else {
            return (0, [], "规则内容超过 \(maximumMB) MB 安全上限。")
        }
        do {
            let parsed = try RuleParser.parse(content, for: draft)
            return (parsed.rules.filter { !$0.hasPrefix("#!") }.count, parsed.warnings, nil)
        } catch {
            return (0, [], error.localizedDescription)
        }
    }
}

private struct SourceModePill: View {
    let source: RuleSource

    var body: some View {
        if source.isManual {
            Text(source.publishesDetachedProfile ? "手工 · dconf" : "手工")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SurgePalette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SurgePalette.accent.opacity(0.11), in: Capsule())
        } else if source.resolvedOutputMode == .remoteReference {
            Text("外部引用")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SurgePalette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SurgePalette.accent.opacity(0.11), in: Capsule())
        } else {
            StatusPill(state: source.state)
        }
    }
}
