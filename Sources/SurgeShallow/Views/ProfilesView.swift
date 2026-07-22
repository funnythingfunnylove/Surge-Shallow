import SwiftUI
import SurgeProfileRelayCore

struct ProfilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sharingOverview

                SharedProfileEditor(profile: model.document.sharedProfile)
                    .id(model.document.sharedProfile.hashValue)

                VStack(alignment: .leading, spacing: 8) {
                    Text("平台差异")
                        .font(.title2.weight(.semibold))
                    Text("这里只填写与公共配置不同或额外增加的项目。生成时，Relay 会在对应段先引用公共 .dconf，再叠加这些差异。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.document.targets) { target in
                    PlatformDifferenceEditor(target: target)
                        .id(target.hashValue)
                }
            }
            .padding(26)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .navigationTitle("Profiles")
    }

    private var sharingOverview: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("一份公共配置，两份平台差异")
                            .font(.headline)
                        Text("遵循 Surge 官方 Detached Profile Section：可复用段只写一次，macOS 与 iOS Profile 通过 #!include 引用。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(
                        "查看 Surge 文档",
                        destination: URL(string: "https://manual.nssurge.com/overview/configuration.html#detached-profile-section")!
                    )
                }

                HStack(spacing: 10) {
                    ProfileFlowStep(symbol: "square.stack.3d.up", title: "公共 .dconf", detail: "General、Proxy 与高级段")
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                    ProfileFlowStep(symbol: "macbook.and.iphone", title: "平台差异", detail: "仅填写不同项")
                    Image(systemName: "plus")
                        .foregroundStyle(.tertiary)
                    ProfileFlowStep(symbol: "line.3.horizontal.decrease.circle", title: "自动规则", detail: "按平台过滤与合并")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    ProfileFlowStep(symbol: "doc.badge.gearshape", title: "完整 Profile", detail: "macOS 与 iOS 各一份")
                }

                Label(
                    "两端规则完全一致且 FINAL 策略相同时，[Rule] 也放入公共文件；存在平台差异时则分别生成，避免改变规则优先级。",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileFlowStep: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SharedProfileEditor: View {
    @Environment(AppModel.self) private var model
    @State private var draft: SharedProfile
    @State private var showsEditor = false

    init(profile: SharedProfile) {
        _draft = State(initialValue: profile)
    }

    var body: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 40, height: 40)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("公共配置")
                            .font(.title3.weight(.semibold))
                        Text("管理 General 通用选项、文件名与其他高级公共段")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let date = draft.lastGeneratedAt {
                        Text("上次生成 \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("共享文件")
                            .foregroundStyle(.secondary)
                        TextField("Surge-Profile-Relay-Shared.dconf", text: $draft.outputFileName)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("General 通用选项")
                                .font(.headline)
                            Text("这里的值由两个平台共同继承；需要不同值时，再到对应平台 Profile 添加同名覆盖项。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(ProfileOptionCatalog.common) { option in
                                Button("\(option.title) · \(option.key)") {
                                    addGeneralOption(option)
                                }
                                .disabled(containsGeneralOption(option))
                            }
                            Divider()
                            Button {
                                draft.generalOptions.append(ProfileDifferenceItem(
                                    section: "General",
                                    key: "",
                                    value: ""
                                ))
                            } label: {
                                Label("自定义 General 键值", systemImage: "text.badge.plus")
                            }
                            Button {
                                draft.generalOptions.append(.rawLine(section: "General", line: ""))
                            } label: {
                                Label("自定义原始行", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                        } label: {
                            Label("添加通用选项", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                    }

                    if draft.generalOptions.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.secondary)
                            Text("还没有 General 通用选项。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        ForEach($draft.generalOptions) { $item in
                            ProfileDifferenceRow(
                                item: $item,
                                platform: nil,
                                locksSection: true,
                                onDelete: {
                                    draft.generalOptions.removeAll { $0.id == item.id }
                                }
                            )
                        }
                    }
                }

                DisclosureGroup(isExpanded: $showsEditor) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("这里只编辑 Host、MITM、Script、Rewrite 等高级公共段。General 请使用上方选项；Proxy 与策略组请使用侧栏 Proxy Tab；[Rule] 由 Relay 自动管理。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("可复用高级公共段")
                            .font(.caption.weight(.semibold))
                        Text(SharedProfile.reusableSections.map { "[\($0)]" }.joined(separator: "  "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if !draft.preamble.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("文件头注释与指令")
                                    .font(.caption.weight(.semibold))
                                TextEditor(text: $draft.preamble)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(minHeight: 74)
                                    .scrollContentBackground(.hidden)
                                    .padding(7)
                                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $draft.advancedProfile)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 330)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                            if draft.advancedProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(SharedProfile.editorPlaceholder)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.primary.opacity(0.12))
                        }

                        HStack {
                            Menu {
                                ForEach(SharedProfile.reusableSections, id: \.self) { section in
                                    Button("[\(section)]") { appendSection(section) }
                                }
                            } label: {
                                Label("插入提示或段模板", systemImage: "text.badge.plus")
                            }
                            Spacer()
                            Text("注释以 # 开头，不影响 Surge 解析。")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Label("编辑其他公共段", systemImage: "doc.text")
                }

                if let sharedEditorError {
                    Label(sharedEditorError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let validation = draft.lastValidationMessage {
                    ValidationLabel(message: validation)
                }

                HStack {
                    Button {
                        model.importSharedProfile()
                    } label: {
                        Label("导入公共 Profile", systemImage: "square.and.arrow.down")
                    }
                    Button("查看最近预览") { model.showSharedPreview() }
                        .accessibilityIdentifier("shared-profile-preview")
                        .disabled(draft.lastGeneratedAt == nil)
                    Spacer()
                    Button("保存 General 与公共配置") {
                        model.updateSharedProfile { shared in
                            shared.outputFileName = draft.outputFileName
                            shared.preamble = draft.preamble
                            shared.generalOptions = draft.generalOptions
                            shared.advancedProfile = draft.advancedProfile
                            shared.lastValidationMessage = "General 与其他公共段已保存，等待重新生成。"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
        }
        .disabled(model.isRefreshing)
    }

    private var isValid: Bool {
        !draft.outputFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.generalOptions.allSatisfy(generalOptionIsValid)
            && sharedEditorError == nil
    }

    private var sharedEditorError: String? {
        let keys = draft.generalOptions.compactMap { item -> String? in
            guard item.kind == .keyValue else { return nil }
            return item.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if Set(keys).count != keys.count {
            return "General 配置键不能重复。"
        }
        let managed = ["General", "Proxy", "Proxy Group", "Rule"]
        for section in managed {
            let escaped = NSRegularExpression.escapedPattern(for: section)
            if draft.advancedProfile.range(
                of: "(?im)^\\s*\\[\(escaped)\\]\\s*$",
                options: .regularExpression
            ) != nil {
                return "[\(section)] 已由结构化界面管理，请从高级公共段编辑器中移除。"
            }
        }
        return nil
    }

    private func addGeneralOption(_ option: ProfileOptionDescriptor) {
        guard !containsGeneralOption(option) else { return }
        draft.generalOptions.append(option.makeItem())
    }

    private func containsGeneralOption(_ option: ProfileOptionDescriptor) -> Bool {
        draft.generalOptions.contains {
            $0.key.caseInsensitiveCompare(option.key) == .orderedSame
        }
    }

    private func generalOptionIsValid(_ item: ProfileDifferenceItem) -> Bool {
        guard item.isValid,
              item.normalizedSection.caseInsensitiveCompare("General") == .orderedSame else {
            return false
        }
        guard let descriptor = ProfileOptionCatalog.descriptor(
            section: "General",
            key: item.key
        ) else { return true }
        guard descriptor.scope == .common else { return false }
        if case .port = descriptor.valueKind {
            guard let port = Int(item.value), (1...65_535).contains(port) else { return false }
        }
        if case .number = descriptor.valueKind {
            guard Double(item.value) != nil else { return false }
        }
        return true
    }

    private func appendSection(_ section: String) {
        let header = "[\(section)]"
        guard !draft.advancedProfile.localizedCaseInsensitiveContains(header) else { return }
        let existing = draft.advancedProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.advancedProfile = existing + (existing.isEmpty ? "" : "\n\n") + header + "\n"
    }
}

private struct PlatformDifferenceEditor: View {
    @Environment(AppModel.self) private var model
    @State private var draft: TargetProfile

    init(target: TargetProfile) {
        _draft = State(initialValue: target)
    }

    var body: some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 13) {
                    Image(systemName: draft.platform.symbolName)
                        .font(.title2)
                        .frame(width: 38, height: 38)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.platform.displayName)
                            .font(.title3.weight(.semibold))
                        if let date = draft.lastGeneratedAt {
                            Text("上次生成 \(date.formatted(date: .abbreviated, time: .shortened)) · \(draft.lastRuleCount) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("尚未生成")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle("启用", isOn: $draft.isEnabled)
                        .toggleStyle(.switch)
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("输出文件")
                            .foregroundStyle(.secondary)
                        TextField("文件名", text: $draft.outputFileName)
                    }
                    GridRow {
                        Text("FINAL 策略")
                            .foregroundStyle(.secondary)
                        RelayPolicyPicker(
                            title: "FINAL 策略",
                            selection: $draft.finalPolicy,
                            sharedProfile: model.document.sharedProfile
                        )
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("差异配置")
                                .font(.headline)
                            Text("删除一项即恢复继承公共配置；同名值会在 #!include 公共段之后覆盖。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Menu("通用选项（覆盖公共值）") {
                                ForEach(ProfileOptionCatalog.common) { option in
                                    Button("\(option.title) · \(option.key)") {
                                        add(option)
                                    }
                                    .disabled(contains(option))
                                }
                            }
                            Menu("\(draft.platform.displayName) 专属选项") {
                                ForEach(ProfileOptionCatalog.platformOnlyOptions(for: draft.platform)) { option in
                                    Button("\(option.title) · \(option.key)") {
                                        add(option)
                                    }
                                    .disabled(contains(option))
                                }
                            }
                            Divider()
                            Button {
                                draft.platformDifferences.append(ProfileDifferenceItem(
                                    section: "General",
                                    key: "",
                                    value: ""
                                ))
                            } label: {
                                Label("自定义键值", systemImage: "text.badge.plus")
                            }
                            Button {
                                draft.platformDifferences.append(.rawLine(section: "", line: ""))
                            } label: {
                                Label("自定义原始行", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                        } label: {
                            Label("添加差异项", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                    }

                    if draft.platformDifferences.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("没有平台差异")
                                    .font(.subheadline.weight(.medium))
                                Text("\(draft.platform.displayName) 将完整继承公共配置。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        ForEach($draft.platformDifferences) { $item in
                            ProfileDifferenceRow(
                                item: $item,
                                platform: draft.platform,
                                locksSection: false,
                                onDelete: {
                                    draft.platformDifferences.removeAll { $0.id == item.id }
                                }
                            )
                        }
                    }
                }

                if let validation = draft.lastValidationMessage {
                    ValidationLabel(message: validation)
                }

                HStack {
                    Button {
                        model.importPlatformProfile(for: draft.platform)
                    } label: {
                        Label("导入并转换差异片段", systemImage: "square.and.arrow.down")
                    }
                    Button("查看完整预览") { model.showPreview(for: draft.platform) }
                        .disabled(draft.lastGeneratedAt == nil)
                    Spacer()
                    Button("保存平台设置") {
                        model.updateTarget(draft.platform) { $0 = draft }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
        }
        .opacity(draft.isEnabled ? 1 : 0.68)
        .disabled(model.isRefreshing)
    }

    private var isValid: Bool {
        let final = draft.finalPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        return !draft.outputFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !final.isEmpty
            && !final.contains(",")
            && !final.contains("\n")
            && !final.contains("\r")
            && draft.platformDifferences.allSatisfy { differenceIsValid($0) }
    }

    private func add(_ option: ProfileOptionDescriptor) {
        guard !contains(option) else { return }
        draft.platformDifferences.append(option.makeItem())
    }

    private func contains(_ option: ProfileOptionDescriptor) -> Bool {
        draft.platformDifferences.contains {
            $0.normalizedSection.caseInsensitiveCompare(option.section) == .orderedSame
                && $0.key.caseInsensitiveCompare(option.key) == .orderedSame
        }
    }

    private func differenceIsValid(_ item: ProfileDifferenceItem) -> Bool {
        guard item.isValid else { return false }
        guard let descriptor = ProfileOptionCatalog.descriptor(section: item.normalizedSection, key: item.key) else {
            return true
        }
        switch descriptor.scope {
        case .common:
            break
        case .macOS where draft.platform != .macOS:
            return false
        case .iOS where draft.platform != .iOS:
            return false
        default:
            break
        }
        if case .port = descriptor.valueKind {
            guard let port = Int(item.value), (1...65_535).contains(port) else { return false }
        }
        if case .number = descriptor.valueKind {
            guard Double(item.value) != nil else { return false }
        }
        return true
    }
}

private struct ProfileDifferenceRow: View {
    @Binding var item: ProfileDifferenceItem
    let platform: RelayPlatform?
    let locksSection: Bool
    let onDelete: () -> Void

    private var descriptor: ProfileOptionDescriptor? {
        guard item.kind == .keyValue else { return nil }
        return ProfileOptionCatalog.descriptor(section: item.normalizedSection, key: item.key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    if let descriptor {
                        HStack(spacing: 7) {
                            Text(descriptor.title)
                                .font(.subheadline.weight(.semibold))
                            Text("[\(descriptor.section)] \(descriptor.key)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(descriptor.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.kind == .keyValue ? "自定义键值" : "自定义原始行")
                            .font(.subheadline.weight(.semibold))
                        Text(item.kind == .keyValue ? "填写 Surge 段名、配置键和值。" : "用于保留导入片段中的注释、指令或无法识别的语法。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除并恢复继承公共配置")
            }

            if let descriptor {
                optionValueEditor(descriptor)
                if !descriptorAppliesToPlatform(descriptor) {
                    Label(applicabilityMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !valueIsValid(descriptor) {
                    Label(validationMessage(descriptor), systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                customEditor
            }

            if item.isRuleSection {
                Label("[Rule] 由 Relay 自动生成，不能作为平台差异保存。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(item.isValid ? Color.primary.opacity(0.06) : Color.red.opacity(0.45))
        }
    }

    @ViewBuilder
    private func optionValueEditor(_ descriptor: ProfileOptionDescriptor) -> some View {
        HStack {
            Text("值")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            switch descriptor.valueKind {
            case .boolean:
                Picker("值", selection: $item.value) {
                    Text("开启").tag("true")
                    Text("关闭").tag("false")
                    if !["true", "false"].contains(item.value.lowercased()) {
                        Text("原值：\(item.value)").tag(item.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            case .choice(let choices):
                Picker("值", selection: $item.value) {
                    ForEach(choices) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                    if !choices.contains(where: { $0.value == item.value }) {
                        Text("原值：\(item.value)").tag(item.value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
            case .text, .number, .port, .list:
                TextField(descriptor.placeholder, text: $item.value)
                    .textFieldStyle(.roundedBorder)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var customEditor: some View {
        if item.kind == .keyValue {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                if !locksSection {
                    GridRow {
                        Text("段")
                            .foregroundStyle(.secondary)
                        TextField("General", text: $item.section)
                    }
                }
                GridRow {
                    Text("键")
                        .foregroundStyle(.secondary)
                    TextField("配置键", text: $item.key)
                }
                GridRow {
                    Text("值")
                        .foregroundStyle(.secondary)
                    TextField("配置值", text: $item.value)
                }
            }
            .textFieldStyle(.roundedBorder)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                if !locksSection {
                    GridRow {
                        Text("所在段")
                            .foregroundStyle(.secondary)
                        TextField("留空表示文件开头", text: $item.section)
                    }
                }
                GridRow {
                    Text("原始行")
                        .foregroundStyle(.secondary)
                    TextField("# 注释或 #!include 指令", text: $item.value)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func descriptorAppliesToPlatform(_ descriptor: ProfileOptionDescriptor) -> Bool {
        switch descriptor.scope {
        case .common: true
        case .macOS: platform == RelayPlatform.macOS
        case .iOS: platform == RelayPlatform.iOS
        }
    }

    private var applicabilityMessage: String {
        if let platform {
            return "此项不适用于 \(platform.displayName)，请删除或改为该平台支持的配置。"
        }
        return "公共 General 只能使用 macOS 与 iOS/iPadOS 都支持的通用选项。"
    }

    private func valueIsValid(_ descriptor: ProfileOptionDescriptor) -> Bool {
        guard !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch descriptor.valueKind {
        case .port:
            guard let port = Int(item.value) else { return false }
            return (1...65_535).contains(port)
        case .number:
            return Double(item.value) != nil
        default:
            return true
        }
    }

    private func validationMessage(_ descriptor: ProfileOptionDescriptor) -> String {
        switch descriptor.valueKind {
        case .port: "端口必须是 1 到 65535 的整数。"
        case .number: "请输入有效数字。"
        default: "配置值不能为空。"
        }
    }
}

private struct ValidationLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: isFailure ? "xmark.circle" : "checkmark.circle")
            .font(.caption)
            .foregroundStyle(isFailure ? .red : .secondary)
            .textSelection(.enabled)
    }

    private var isFailure: Bool {
        message.localizedCaseInsensitiveContains("fail") || message.contains("失败")
    }
}
