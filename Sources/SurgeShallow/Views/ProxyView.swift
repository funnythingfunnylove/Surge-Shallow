import SwiftUI
import SurgeProfileRelayCore

struct ProxyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProxyConfigurationEditor(profile: model.document.sharedProfile)
            .id(model.document.sharedProfile.hashValue)
            .navigationTitle("Proxy")
    }
}

private enum ManagedPolicyKind: String, Hashable {
    case proxy
    case group

    var title: String { self == .proxy ? "Proxy" : "Proxy Group" }
    var symbol: String {
        self == .proxy ? "server.rack" : "point.3.filled.connected.trianglepath.dotted"
    }
    var typeLabel: String { self == .proxy ? "协议" : "组类型" }
    var descriptors: [ProxyTypeDescriptor] {
        self == .proxy ? ProxyDefinitionCatalog.proxyTypes : ProxyDefinitionCatalog.groupTypes
    }

    func descriptor(for item: ProxyDefinition) -> ProxyTypeDescriptor? {
        switch self {
        case .proxy: ProxyDefinitionCatalog.proxyDescriptor(for: item)
        case .group: ProxyDefinitionCatalog.groupDescriptor(for: item.type)
        }
    }

    func descriptor(forSelectionID id: String) -> ProxyTypeDescriptor? {
        descriptors.first { $0.id == id }
    }

    func selectionID(for item: ProxyDefinition) -> String {
        descriptor(for: item)?.id ?? "custom:\(item.type)"
    }

    func apply(selectionID: String, to item: inout ProxyDefinition) {
        guard let descriptor = descriptor(forSelectionID: selectionID) else { return }
        let previousType = item.type
        item.type = descriptor.type
        item.presetID = descriptor.id == descriptor.type ? nil : descriptor.id

        guard descriptor.type == "snell", !item.parameters.isEmpty else { return }
        let targetVersion = descriptor.id == "snell-v6" ? "6" : "4"
        item.parameters = replacingParameter(
            named: "version",
            with: targetVersion,
            in: item.parameters,
            appendIfMissing: previousType.caseInsensitiveCompare("snell") == .orderedSame
        )
    }

    private func replacingParameter(
        named name: String,
        with value: String,
        in parameters: String,
        appendIfMissing: Bool
    ) -> String {
        var tokens = RuleParser.splitTopLevelCSV(parameters)
        if let index = tokens.firstIndex(where: { token in
            token.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }) {
            tokens[index] = "\(name)=\(value)"
        } else if appendIfMissing {
            tokens.append("\(name)=\(value)")
        }
        return tokens.joined(separator: ", ")
    }
}

private struct ManagedPolicySelection: Hashable {
    var kind: ManagedPolicyKind
    var id: UUID
}

private struct ProxyConfigurationEditor: View {
    @Environment(AppModel.self) private var model
    @State private var draft: SharedProfile
    @State private var selection: ManagedPolicySelection?
    @State private var searchText = ""

    init(profile: SharedProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        VStack(spacing: 0) {
            overview
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            HSplitView {
                sidebar
                    .frame(minWidth: 300, idealWidth: 330, maxWidth: 390)

                detailPane
                    .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            saveBar
        }
        .disabled(model.isRefreshing)
        .onAppear { selectFirstIfNeeded() }
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(SurgePalette.accent)
                .frame(width: 42, height: 42)
                .background(SurgePalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text("Proxy 与策略组")
                    .font(.title3.weight(.semibold))
                Text("从左侧选择一个项目，在右侧集中编辑；常规策略组可直接选择、排序成员策略。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(definitionCount(draft.proxies)) 个 Proxy · \(definitionCount(draft.proxyGroups)) 个策略组")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Link("Proxy 文档", destination: URL(string: "https://manual.nssurge.com/policy/proxy.html")!)
                    Link("策略组文档", destination: URL(string: "https://manual.nssurge.com/policy-group/group.html")!)
                    Link("Smart Group", destination: URL(string: "https://kb.nssurge.com/surge-knowledge-base/guidelines/smart-group")!)
                }
                .font(.caption)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索名称、类型或参数", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                addMenu
            }
            .padding(12)

            List(selection: $selection) {
                Section("Proxy · \(definitionCount(draft.proxies))") {
                    ForEach(filtered(draft.proxies)) { item in
                        PolicyListRow(item: item, kind: .proxy)
                            .tag(ManagedPolicySelection(kind: .proxy, id: item.id))
                            .contextMenu {
                                Button("复制") { duplicate(.init(kind: .proxy, id: item.id)) }
                                Button("删除", role: .destructive) {
                                    delete(.init(kind: .proxy, id: item.id))
                                }
                            }
                    }
                }

                Section("Proxy Group · \(definitionCount(draft.proxyGroups))") {
                    ForEach(filtered(draft.proxyGroups)) { item in
                        PolicyListRow(item: item, kind: .group)
                            .tag(ManagedPolicySelection(kind: .group, id: item.id))
                            .contextMenu {
                                Button("复制") { duplicate(.init(kind: .group, id: item.id)) }
                                Button("删除", role: .destructive) {
                                    delete(.init(kind: .group, id: item.id))
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(spacing: 12) {
                Button { moveSelected(by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .help("上移")
                .disabled(!canMoveSelected(by: -1))

                Button { moveSelected(by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .help("下移")
                .disabled(!canMoveSelected(by: 1))

                Button {
                    if let selection { duplicate(selection) }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("复制")
                .disabled(selection == nil)

                Spacer()

                Button(role: .destructive) {
                    if let selection { delete(selection) }
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除")
                .disabled(selection == nil)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.16))
    }

    private var addMenu: some View {
        Menu {
            Menu("添加 Proxy") {
                ForEach(ProxyDefinitionCatalog.proxyTypes) { descriptor in
                    Button("\(descriptor.title) · \(descriptor.type)") {
                        add(descriptor, kind: .proxy)
                    }
                }
                Divider()
                Button("自定义类型") { addCustom(kind: .proxy) }
                Button("自定义原始行") { addRawLine(kind: .proxy) }
            }

            Menu("添加 Proxy Group") {
                ForEach(ProxyDefinitionCatalog.groupTypes) { descriptor in
                    Button("\(descriptor.title) · \(descriptor.type)") {
                        add(descriptor, kind: .group)
                    }
                }
                Divider()
                Button("自定义类型") { addCustom(kind: .group) }
                Button("自定义原始行") { addRawLine(kind: .group) }
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .help("添加 Proxy 或策略组")
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selection, let binding = binding(for: selection) {
            PolicyDefinitionDetailEditor(
                item: binding,
                kind: selection.kind,
                sharedProfile: draft
            )
        } else {
            ContentUnavailableView {
                Label("选择配置项", systemImage: "sidebar.right")
            } description: {
                Text("在左侧选择 Proxy 或 Proxy Group；也可以使用 + 新建配置。")
            }
        }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if hasChanges {
                Label("有尚未保存的 Proxy 配置。", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("所有 Proxy 与策略组配置已保存。", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.importSharedProfile()
            } label: {
                Label("导入完整公共 Profile", systemImage: "square.and.arrow.down")
            }
            Button("撤销未保存更改") {
                draft = model.document.sharedProfile
                selectFirstIfNeeded(force: true)
            }
            .disabled(!hasChanges)
            Button("保存 Proxy 配置") {
                model.updateSharedProfile { shared in
                    shared.proxies = draft.proxies
                    shared.proxyGroups = draft.proxyGroups
                    shared.lastValidationMessage = "Proxy 与策略组已保存，等待重新生成。"
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(validationMessage != nil || !hasChanges)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var validationMessage: String? {
        let all = draft.proxies + draft.proxyGroups
        if all.contains(where: {
            $0.kind == .definition
                && $0.parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return "Proxy 和策略组的参数不能为空。"
        }
        if let issue = all.compactMap(\.presetValidationIssue).first { return issue }
        if all.contains(where: { !$0.isValid }) {
            return "请补全所有名称、类型和参数，并移除换行、逗号名称或伪造段头。"
        }
        let names = all.compactMap { item -> String? in
            guard item.kind == .definition else { return nil }
            return item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if Set(names).count != names.count { return "Proxy 与策略组名称不能重复。" }
        return nil
    }

    private var hasChanges: Bool { draft != model.document.sharedProfile }

    private func binding(for selection: ManagedPolicySelection) -> Binding<ProxyDefinition>? {
        let exists = items(for: selection.kind).contains { $0.id == selection.id }
        guard exists else { return nil }
        return Binding(
            get: {
                items(for: selection.kind).first { $0.id == selection.id }
                    ?? ProxyDefinition.rawLine("")
            },
            set: { newValue in
                switch selection.kind {
                case .proxy:
                    guard let index = draft.proxies.firstIndex(where: { $0.id == selection.id }) else { return }
                    draft.proxies[index] = newValue
                case .group:
                    guard let index = draft.proxyGroups.firstIndex(where: { $0.id == selection.id }) else { return }
                    draft.proxyGroups[index] = newValue
                }
            }
        )
    }

    private func items(for kind: ManagedPolicyKind) -> [ProxyDefinition] {
        kind == .proxy ? draft.proxies : draft.proxyGroups
    }

    private func filtered(_ items: [ProxyDefinition]) -> [ProxyDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.type.localizedCaseInsensitiveContains(query)
                || $0.parameters.localizedCaseInsensitiveContains(query)
        }
    }

    private func add(_ descriptor: ProxyTypeDescriptor, kind: ManagedPolicyKind) {
        let base = kind == .proxy ? descriptor.title.replacingOccurrences(of: " ", with: "") : "PROXY"
        let item = ProxyDefinition(
            name: uniqueName(base: base),
            type: descriptor.type,
            parameters: defaultParameters(for: descriptor, kind: kind),
            presetID: descriptor.id == descriptor.type ? nil : descriptor.id
        )
        append(item, kind: kind)
    }

    private func addCustom(kind: ManagedPolicyKind) {
        append(
            ProxyDefinition(
                name: uniqueName(base: kind == .proxy ? "Proxy" : "Group"),
                type: "custom",
                parameters: ""
            ),
            kind: kind
        )
    }

    private func addRawLine(kind: ManagedPolicyKind) {
        append(.rawLine(""), kind: kind)
    }

    private func append(_ item: ProxyDefinition, kind: ManagedPolicyKind) {
        if kind == .proxy { draft.proxies.append(item) }
        else { draft.proxyGroups.append(item) }
        selection = .init(kind: kind, id: item.id)
        searchText = ""
    }

    private func defaultParameters(
        for descriptor: ProxyTypeDescriptor,
        kind: ManagedPolicyKind
    ) -> String {
        guard kind == .group else { return "" }
        let proxies = RelayPolicyCatalog.proxyNames(in: draft)
        switch descriptor.type {
        case "select":
            return ([proxies.first].compactMap { $0 } + ["DIRECT"]).joined(separator: ", ")
        case "subnet":
            return "default = DIRECT"
        default:
            return proxies.prefix(2).joined(separator: ", ")
        }
    }

    private func duplicate(_ selected: ManagedPolicySelection) {
        guard var copy = items(for: selected.kind).first(where: { $0.id == selected.id }) else { return }
        copy.id = UUID()
        if copy.kind == .definition {
            copy.name = uniqueName(base: copy.name + " Copy")
        }
        append(copy, kind: selected.kind)
    }

    private func delete(_ selected: ManagedPolicySelection) {
        switch selected.kind {
        case .proxy: draft.proxies.removeAll { $0.id == selected.id }
        case .group: draft.proxyGroups.removeAll { $0.id == selected.id }
        }
        selection = nil
        selectFirstIfNeeded()
    }

    private func moveSelected(by offset: Int) {
        guard let selection else { return }
        switch selection.kind {
        case .proxy:
            guard let from = draft.proxies.firstIndex(where: { $0.id == selection.id }) else { return }
            let to = from + offset
            guard draft.proxies.indices.contains(to) else { return }
            draft.proxies.swapAt(from, to)
        case .group:
            guard let from = draft.proxyGroups.firstIndex(where: { $0.id == selection.id }) else { return }
            let to = from + offset
            guard draft.proxyGroups.indices.contains(to) else { return }
            draft.proxyGroups.swapAt(from, to)
        }
    }

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let selection,
              let index = items(for: selection.kind).firstIndex(where: { $0.id == selection.id }) else {
            return false
        }
        return items(for: selection.kind).indices.contains(index + offset)
    }

    private func uniqueName(base: String) -> String {
        let existing = Set((draft.proxies + draft.proxyGroups).compactMap { item -> String? in
            guard item.kind == .definition else { return nil }
            return item.name.lowercased()
        })
        if !existing.contains(base.lowercased()) { return base }
        var suffix = 2
        while existing.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private func selectFirstIfNeeded(force: Bool = false) {
        if !force, let selection, items(for: selection.kind).contains(where: { $0.id == selection.id }) {
            return
        }
        if let first = draft.proxies.first {
            selection = .init(kind: .proxy, id: first.id)
        } else if let first = draft.proxyGroups.first {
            selection = .init(kind: .group, id: first.id)
        } else {
            selection = nil
        }
    }

    private func definitionCount(_ items: [ProxyDefinition]) -> Int {
        items.filter { $0.kind == .definition }.count
    }
}

private struct PolicyListRow: View {
    let item: ProxyDefinition
    let kind: ManagedPolicyKind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .rawLine ? "chevron.left.forwardslash.chevron.right" : kind.symbol)
                .foregroundStyle(item.isValid ? Color.accentColor : Color.red)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !item.isValid {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
    }

    private var displayName: String {
        if item.kind == .rawLine { return "自定义原始行" }
        return item.name.isEmpty ? "未命名定义" : item.name
    }

    private var detail: String {
        if item.kind == .rawLine { return item.parameters.isEmpty ? "尚未填写" : item.parameters }
        return kind.descriptor(for: item)?.title ?? item.type
    }
}

private struct PolicyDefinitionDetailEditor: View {
    @Binding var item: ProxyDefinition
    let kind: ManagedPolicyKind
    let sharedProfile: SharedProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: item.kind == .rawLine ? "chevron.left.forwardslash.chevron.right" : kind.symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 42, height: 42)
                        .background(.tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.kind == .rawLine ? "自定义原始行" : (item.name.isEmpty ? "未命名配置" : item.name))
                            .font(.title2.weight(.semibold))
                        Text(kind.descriptor(for: item)?.detail ?? "按原样生成到公共 [\(kind.title)] 段。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if item.kind == .definition {
                    RelayCard {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 13) {
                            GridRow {
                                Text("名称")
                                    .foregroundStyle(.secondary)
                                TextField("供策略组和规则引用", text: $item.name)
                            }
                            GridRow {
                                Text(kind.typeLabel)
                                    .foregroundStyle(.secondary)
                                typePicker
                            }
                        }
                    }

                    if kind == .group, item.type.caseInsensitiveCompare("subnet") != .orderedSame {
                        PolicyGroupMembersEditor(item: $item, sharedProfile: sharedProfile)
                    } else {
                        RelayCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(kind == .proxy ? "连接参数" : "策略组参数")
                                    .font(.headline)
                                TextField(parameterPlaceholder, text: $item.parameters)
                                    .textFieldStyle(.roundedBorder)
                                Text(kind == .proxy
                                     ? "填写协议类型之后的完整参数；服务器、端口和认证选项使用逗号分隔。"
                                     : "Subnet 使用网络条件映射，请按 Surge 原始语法填写。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    RelayCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("生成预览")
                                .font(.headline)
                            Text(item.renderedLine ?? "填写完整后显示最终配置行")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(item.isValid ? Color.secondary : Color.red)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    RelayCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("原始配置行")
                                .font(.headline)
                            TextField("# 注释、#!include 或其他安全配置行", text: $item.parameters)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            Text("不能包含换行或新的 [Section] 段头。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !item.isValid {
                    Label(validationDetail, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var typePicker: some View {
        Picker(
            kind.typeLabel,
            selection: Binding(
                get: { kind.selectionID(for: item) },
                set: { kind.apply(selectionID: $0, to: &item) }
            )
        ) {
            ForEach(kind.descriptors) { descriptor in
                Text("\(descriptor.title) · \(descriptor.type)").tag(descriptor.id)
            }
            if kind.descriptor(for: item) == nil {
                Text("自定义 · \(item.type)").tag("custom:\(item.type)")
            }
        }
        .labelsHidden()
    }

    private var parameterPlaceholder: String {
        kind.descriptor(for: item)?.placeholder ?? "类型之后的完整参数"
    }

    private var validationDetail: String {
        if let issue = item.presetValidationIssue { return issue }
        if item.kind == .definition, item.parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请添加连接参数或至少一个策略组成员。"
        }
        return "该项尚未填写完整，或包含不安全的名称、换行和段头。"
    }
}

private struct PolicyGroupMembersEditor: View {
    @Binding var item: ProxyDefinition
    let sharedProfile: SharedProfile

    var body: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("成员策略")
                            .font(.headline)
                        Text("成员顺序会写入 Surge；Smart Group 不允许直接嵌套其他策略组。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    memberMenu
                }

                if members.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("还没有显式成员；可添加策略，或使用下方 include/policy-path 参数。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    VStack(spacing: 7) {
                        ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                            HStack(spacing: 10) {
                                Image(systemName: symbol(for: member))
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)
                                Text(member)
                                    .font(.system(.body, design: .rounded).weight(.medium))
                                Spacer()
                                Button { moveMember(at: index, by: -1) } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                Button { moveMember(at: index, by: 1) } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == members.count - 1)
                                Button(role: .destructive) { removeMember(at: index) } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("高级参数")
                        .font(.subheadline.weight(.semibold))
                    TextField(
                        "例如：url=http://www.gstatic.com/generate_204, policy-priority=\"Premium:0.9\"",
                        text: advancedOptionsBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    Text("可填写 url、interval、tolerance、policy-path、include-all-proxies、policy-priority 等键值参数。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var memberMenu: some View {
        Menu {
            Section("Surge 内置策略") {
                ForEach(RelayPolicyCatalog.builtInPolicies) { policy in
                    Button("\(policy.title) · \(policy.name)") { addMember(policy.name) }
                        .disabled(containsMember(policy.name))
                }
            }

            let proxies = RelayPolicyCatalog.proxyNames(in: sharedProfile)
            if !proxies.isEmpty {
                Section("Proxy") {
                    ForEach(proxies, id: \.self) { name in
                        Button(name) { addMember(name) }
                            .disabled(containsMember(name))
                    }
                }
            }

            let groups = availableGroups
            if !groups.isEmpty {
                Section("Proxy Group") {
                    ForEach(groups, id: \.self) { name in
                        Button(name) { addMember(name) }
                            .disabled(containsMember(name))
                    }
                }
            }
        } label: {
            Label("添加成员", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
    }

    private var members: [String] {
        RuleParser.splitTopLevelCSV(item.parameters).filter { !isAdvancedOption($0) && !$0.isEmpty }
    }

    private var advancedOptions: [String] {
        RuleParser.splitTopLevelCSV(item.parameters).filter(isAdvancedOption)
    }

    private var advancedOptionsBinding: Binding<String> {
        Binding(
            get: { advancedOptions.joined(separator: ", ") },
            set: { value in
                let options = RuleParser.splitTopLevelCSV(value).filter { !$0.isEmpty }
                setComponents(members: members, options: options)
            }
        )
    }

    private var availableGroups: [String] {
        guard item.type.caseInsensitiveCompare("smart") != .orderedSame else { return [] }
        return RelayPolicyCatalog.groupNames(in: sharedProfile).filter {
            $0.caseInsensitiveCompare(item.name) != .orderedSame
        }
    }

    private func addMember(_ name: String) {
        guard !containsMember(name) else { return }
        setComponents(members: members + [name], options: advancedOptions)
    }

    private func removeMember(at index: Int) {
        var updated = members
        guard updated.indices.contains(index) else { return }
        updated.remove(at: index)
        setComponents(members: updated, options: advancedOptions)
    }

    private func moveMember(at index: Int, by offset: Int) {
        var updated = members
        let target = index + offset
        guard updated.indices.contains(index), updated.indices.contains(target) else { return }
        updated.swapAt(index, target)
        setComponents(members: updated, options: advancedOptions)
    }

    private func setComponents(members: [String], options: [String]) {
        item.parameters = (members + options).joined(separator: ", ")
    }

    private func containsMember(_ name: String) -> Bool {
        members.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func isAdvancedOption(_ token: String) -> Bool {
        token.contains("=")
    }

    private func symbol(for member: String) -> String {
        if RelayPolicyCatalog.builtInPolicies.contains(where: {
            $0.name.caseInsensitiveCompare(member) == .orderedSame
        }) {
            return "arrow.triangle.branch"
        }
        if RelayPolicyCatalog.groupNames(in: sharedProfile).contains(where: {
            $0.caseInsensitiveCompare(member) == .orderedSame
        }) {
            return "point.3.filled.connected.trianglepath.dotted"
        }
        return "server.rack"
    }
}
