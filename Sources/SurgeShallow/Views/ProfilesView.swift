import SurgeProfileRelayCore
import SwiftUI

struct ProfilesView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: SurgeSpacing.lg) {
        compactHeader

        sharingOverview

        SharedProfileEditor(profile: model.document.sharedProfile)

        VStack(alignment: .leading, spacing: SurgeSpacing.xs) {
          Text("平台差异")
            .font(.title2.weight(.semibold))
          Text("这里只填写与公共配置不同或额外增加的项目。生成时，Relay 会在对应段先引用公共 .dconf，再叠加这些差异。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        ForEach(model.document.targets) { target in
          PlatformDifferenceEditor(target: target)
        }
      }
      .padding(SurgeSpacing.lg)
      .frame(maxWidth: 1120, alignment: .leading)
    }
    .navigationTitle("Profiles")
  }

  private var compactHeader: some View {
    HStack(alignment: .center, spacing: SurgeSpacing.lg) {
      PageHeader(
        eyebrow: "Profile Architecture",
        title: "共享基础，只维护真正的差异",
        detail: "公共 Detached Profile + macOS / iOS 差异，规则由 Relay 自动合并。"
      )
      Spacer(minLength: SurgeSpacing.lg)
      Button {
        model.beginFullProfileImport()
      } label: {
        Label("导入 Profile", systemImage: "arrow.down.doc")
      }
      .buttonStyle(.glassProminent)
      .help("识别 General、Proxy、策略组、规则、FINAL 与高级段")
    }
  }

  private var sharingOverview: some View {
    HStack(spacing: SurgeSpacing.sm) {
      Image(systemName: "square.stack.3d.up")
        .foregroundStyle(SurgePalette.accent)
      Text("公共 .dconf")
        .fontWeight(.semibold)
      Image(systemName: "plus")
        .foregroundStyle(.tertiary)
      Text("平台差异")
      Image(systemName: "arrow.right")
        .foregroundStyle(.tertiary)
      Text("macOS / iOS 完整 Profile")
      Spacer(minLength: SurgeSpacing.sm)
      Text("相同段只维护一次")
        .font(.caption)
        .foregroundStyle(.secondary)
      Link(
        destination: URL(
          string: "https://manual.nssurge.com/overview/configuration.html#detached-profile-section")!
      ) {
        Image(systemName: "book.closed")
      }
      .help("查看 Surge Detached Profile 文档")
    }
    .font(.subheadline)
    .padding(.horizontal, SurgeSpacing.md)
    .padding(.vertical, 9)
    .glassEffect(.regular, in: .rect(cornerRadius: SurgeRadius.control))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("公共配置加平台差异，生成 macOS 与 iOS 完整 Profile，相同段只维护一次")
  }
}

private struct SharedProfileEditor: View {
  @Environment(AppModel.self) private var model
  let profile: SharedProfile
  @State private var draft: SharedProfile
  @State private var advancedDifferences: [ProfileDifferenceItem]

  init(profile: SharedProfile) {
    self.profile = profile
    _draft = State(initialValue: profile)
    _advancedDifferences = State(
      initialValue: ProfileDifferenceCodec.parse(profile.advancedProfile))
  }

  var body: some View {
    RelayCard {
      VStack(alignment: .leading, spacing: SurgeSpacing.md) {
        HStack(spacing: SurgeSpacing.sm) {
          Image(systemName: "square.stack.3d.up.fill")
            .font(.headline)
            .foregroundStyle(SurgePalette.accent)
            .frame(width: 28, height: 28)
            .background(SurgePalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
          VStack(alignment: .leading, spacing: 2) {
            Text("公共配置")
              .font(.headline)
            Text("管理 General 通用选项、文件名与其他高级公共段")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let date = draft.lastGeneratedAt {
            Text("上次生成 \(date.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Grid(
          alignment: .leading, horizontalSpacing: SurgeSpacing.md, verticalSpacing: SurgeSpacing.sm
        ) {
          GridRow {
            Text("共享文件")
              .foregroundStyle(.secondary)
            TextField("Surge-Profile-Relay-Shared.dconf", text: $draft.outputFileName)
          }
        }

        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
              Text("General 通用选项")
                .font(.subheadline.weight(.semibold))
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
                draft.generalOptions.append(
                  ProfileDifferenceItem(
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
            HStack(spacing: SurgeSpacing.sm) {
              Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
              Text("还没有 General 通用选项。")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
            }
            .padding(.vertical, SurgeSpacing.sm)
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

        VStack(alignment: .leading, spacing: SurgeSpacing.xs) {
          VStack(alignment: .leading, spacing: 1) {
            Text("文件头注释与指令")
              .font(.subheadline.weight(.semibold))
            Text("这里保留公共 Detached Profile 的说明与 #! 指令。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          TextEditor(text: $draft.preamble)
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 52, maxHeight: 72)
            .scrollContentBackground(.hidden)
            .padding(7)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }

        ProfileAdvancedSectionsEditor(
          items: $advancedDifferences,
          platform: nil,
          includesFileHeader: false
        )

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
              shared.advancedProfile = renderedAdvancedProfile
              shared.lastValidationMessage = "General 与其他公共段已保存，等待重新生成。"
            }
          }
          .buttonStyle(.glassProminent)
          .disabled(!isValid)
        }
      }
    }
    .disabled(model.isRefreshing)
    .onChange(of: profile) { oldProfile, newProfile in
      let oldAdvanced = ProfileDifferenceCodec.parse(oldProfile.advancedProfile)
      guard draft == oldProfile, advancedDifferences == oldAdvanced else { return }
      draft = newProfile
      advancedDifferences = ProfileDifferenceCodec.parse(newProfile.advancedProfile)
    }
  }

  private var isValid: Bool {
    !draft.outputFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && draft.generalOptions.allSatisfy(generalOptionIsValid)
      && advancedDifferences.allSatisfy(\.isValid)
      && sharedEditorError == nil
  }

  private var renderedAdvancedProfile: String {
    ProfileDifferenceCodec.render(advancedDifferences)
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
      if renderedAdvancedProfile.range(
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
      item.normalizedSection.caseInsensitiveCompare("General") == .orderedSame
    else {
      return false
    }
    guard
      let descriptor = ProfileOptionCatalog.descriptor(
        section: "General",
        key: item.key
      )
    else { return true }
    guard descriptor.scope == .common else { return false }
    if case .port = descriptor.valueKind {
      guard let port = Int(item.value), (1...65_535).contains(port) else { return false }
    }
    if case .number = descriptor.valueKind {
      guard Double(item.value) != nil else { return false }
    }
    return true
  }

}

private struct PlatformDifferenceEditor: View {
  @Environment(AppModel.self) private var model
  let target: TargetProfile
  @State private var draft: TargetProfile

  init(target: TargetProfile) {
    self.target = target
    _draft = State(initialValue: target)
  }

  var body: some View {
    RelayCard {
      VStack(alignment: .leading, spacing: SurgeSpacing.md) {
        HStack(spacing: SurgeSpacing.sm) {
          Image(systemName: draft.platform.symbolName)
            .font(.headline)
            .frame(width: 28, height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
          VStack(alignment: .leading, spacing: 2) {
            Text(draft.platform.displayName)
              .font(.headline)
            if let date = draft.lastGeneratedAt {
              Text(
                "上次生成 \(date.formatted(date: .abbreviated, time: .shortened)) · \(draft.lastRuleCount) 条"
              )
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

        Grid(
          alignment: .leading, horizontalSpacing: SurgeSpacing.md, verticalSpacing: SurgeSpacing.sm
        ) {
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

        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
              Text("[General] 差异")
                .font(.subheadline.weight(.semibold))
              Text("这里只覆盖 General；其他段在下方按官方 section 分类编辑。删除一项即恢复继承公共配置。")
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
                draft.platformDifferences.append(
                  ProfileDifferenceItem(
                    section: "General",
                    key: "",
                    value: ""
                  ))
              } label: {
                Label("自定义键值", systemImage: "text.badge.plus")
              }
              Button {
                draft.platformDifferences.append(.rawLine(section: "General", line: ""))
              } label: {
                Label("自定义 General 原始行", systemImage: "chevron.left.forwardslash.chevron.right")
              }
            } label: {
              Label("添加差异项", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
          }

          if generalDifferences.isEmpty {
            HStack(spacing: SurgeSpacing.sm) {
              Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text("没有 General 差异")
                  .font(.subheadline.weight(.medium))
                Text("\(draft.platform.displayName) 的 [General] 将完整继承公共配置。")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(.vertical, SurgeSpacing.sm)
          } else {
            ForEach(generalDifferences) { item in
              if let itemBinding = differenceBinding(for: item.id) {
                ProfileDifferenceRow(
                  item: itemBinding,
                  platform: draft.platform,
                  locksSection: true,
                  onDelete: {
                    draft.platformDifferences.removeAll { $0.id == item.id }
                  }
                )
              }
            }
          }
        }

        ProfileAdvancedSectionsEditor(
          items: $draft.platformDifferences,
          platform: draft.platform,
          includesFileHeader: true
        )

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
          .buttonStyle(.glassProminent)
          .disabled(!isValid)
        }
      }
    }
    .opacity(draft.isEnabled ? 1 : 0.68)
    .disabled(model.isRefreshing)
    .onChange(of: target) { oldTarget, newTarget in
      guard draft == oldTarget else { return }
      draft = newTarget
    }
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

  private var generalDifferences: [ProfileDifferenceItem] {
    draft.platformDifferences.filter {
      $0.normalizedSection.caseInsensitiveCompare("General") == .orderedSame
    }
  }

  private func differenceBinding(for id: UUID) -> Binding<ProfileDifferenceItem>? {
    guard draft.platformDifferences.contains(where: { $0.id == id }) else { return nil }
    return Binding(
      get: {
        draft.platformDifferences.first(where: { $0.id == id })
          ?? .rawLine(id: id, section: "General", line: "")
      },
      set: { updated in
        guard let index = draft.platformDifferences.firstIndex(where: { $0.id == id }) else {
          return
        }
        draft.platformDifferences[index] = updated
      }
    )
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
    guard
      let descriptor = ProfileOptionCatalog.descriptor(
        section: item.normalizedSection, key: item.key)
    else {
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
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center, spacing: SurgeSpacing.sm) {
        compactLabel
        if let descriptor {
          optionValueEditor(descriptor)
        } else {
          customEditor
        }
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "trash")
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help("删除并恢复继承公共配置")
      }

      if let inlineError {
        HStack(spacing: SurgeSpacing.sm) {
          Color.clear.frame(width: 230, height: 1)
          Label(inlineError, systemImage: "exclamationmark.circle")
            .font(.caption2)
            .foregroundStyle(.red)
        }
      }
    }
    .padding(.horizontal, SurgeSpacing.sm)
    .padding(.vertical, 5)
    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .strokeBorder(item.isValid ? Color.primary.opacity(0.045) : Color.red.opacity(0.4))
    }
  }

  private var compactLabel: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(descriptor?.title ?? (item.kind == .keyValue ? "自定义键值" : "原始行"))
        .font(.caption.weight(.semibold))
        .lineLimit(1)
      Text(compactKeyLabel)
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(width: 230, alignment: .leading)
    .help(descriptor?.detail ?? customHelp)
  }

  private var compactKeyLabel: String {
    if let descriptor { return descriptor.key }
    if item.kind == .rawLine {
      return item.normalizedSection.isEmpty ? "文件头" : "[\(item.normalizedSection)]"
    }
    let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
    return key.isEmpty ? "key = value" : key
  }

  private var customHelp: String {
    item.kind == .keyValue
      ? "填写 Surge 配置键和值。"
      : "保留注释、指令或无法结构化的官方语法。"
  }

  @ViewBuilder
  private func optionValueEditor(_ descriptor: ProfileOptionDescriptor) -> some View {
    switch descriptor.valueKind {
    case .boolean:
      Picker("值", selection: $item.value) {
        Text("开").tag("true")
        Text("关").tag("false")
        if !["true", "false"].contains(item.value.lowercased()) {
          Text("原值：\(item.value)").tag(item.value)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 130)
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
      .pickerStyle(.menu)
      .frame(maxWidth: 260, alignment: .leading)
    case .text, .number, .port, .list:
      TextField(descriptor.placeholder, text: $item.value)
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
    }
  }

  @ViewBuilder
  private var customEditor: some View {
    if item.kind == .keyValue {
      HStack(spacing: 6) {
        if !locksSection {
          TextField("Section", text: $item.section)
            .frame(maxWidth: 130)
        }
        TextField("配置键", text: $item.key)
        Text("=")
          .foregroundStyle(.tertiary)
        TextField("配置值", text: $item.value)
      }
      .textFieldStyle(.roundedBorder)
      .controlSize(.small)
    } else {
      HStack(spacing: 6) {
        if !locksSection {
          TextField("Section", text: $item.section)
            .frame(maxWidth: 130)
        }
        TextField("# 注释、#! 指令或原始语法", text: $item.value)
      }
      .textFieldStyle(.roundedBorder)
      .controlSize(.small)
    }
  }

  private var inlineError: String? {
    if item.isRuleSection {
      return "[Rule] 由 Relay 自动生成，不能在这里保存。"
    }
    if let descriptor {
      if !descriptorAppliesToPlatform(descriptor) { return applicabilityMessage }
      if !valueIsValid(descriptor) { return validationMessage(descriptor) }
    } else if !item.isValid {
      return "请完整填写这一项。"
    }
    return nil
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

private struct ProfileAdvancedSectionsEditor: View {
  @Binding var items: [ProfileDifferenceItem]
  let platform: RelayPlatform?
  let includesFileHeader: Bool

  @State private var selectedSectionID: String
  @State private var showsCustomSectionAlert = false
  @State private var customSectionName = ""

  init(
    items: Binding<[ProfileDifferenceItem]>,
    platform: RelayPlatform?,
    includesFileHeader: Bool
  ) {
    _items = items
    self.platform = platform
    self.includesFileHeader = includesFileHeader
    let populated = items.wrappedValue.first { item in
      !item.normalizedSection.isEmpty
        && item.normalizedSection.caseInsensitiveCompare("General") != .orderedSame
    }
    let initialID: String
    if let populated {
      initialID = populated.normalizedSection.lowercased()
    } else if includesFileHeader,
      items.wrappedValue.contains(where: { $0.normalizedSection.isEmpty })
    {
      initialID = Self.fileHeaderID
    } else {
      initialID = ProfileSectionCatalog.advanced.first?.id ?? "host"
    }
    _selectedSectionID = State(initialValue: initialID)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
      HStack(spacing: SurgeSpacing.sm) {
        Text("Section")
          .font(.subheadline.weight(.semibold))
        Picker("Section", selection: $selectedSectionID) {
          if includesFileHeader {
            Text("文件头 · \(fileHeaderItems.count)")
              .tag(Self.fileHeaderID)
          }
          ForEach(sectionDescriptors) { descriptor in
            Text("[\(descriptor.name)] · \(items(in: descriptor.name).count)")
              .tag(descriptor.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 260)
        Text(editorDetail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: SurgeSpacing.sm)
        Button {
          customSectionName = ""
          showsCustomSectionAlert = true
        } label: {
          Label("自定义 []", systemImage: "square.brackets")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(sectionAccessibilityIdentifier("custom-add"))
      }

      selectedSectionEditor
    }
    .alert("添加自定义 [Section]", isPresented: $showsCustomSectionAlert) {
      TextField("例如 WireGuard Office / Tailscale Home", text: $customSectionName)
      Button("取消", role: .cancel) {}
      Button("添加") {
        addCustomSection()
      }
      .disabled(!canAddCustomSection)
    } message: {
      Text("输入方括号内的名称。自定义 Section 会保留到 Profile，便于支持 Surge 后续新增语法或动态命名段。")
    }
  }

  private var editorDetail: String {
    if let platform {
      return "编辑 \(platform.displayName) 对公共配置的覆盖或附加内容；每段内可添加键值或保留官方原始语法。"
    }
    return "公共段会由 macOS 与 iOS Profile 共同引用；平台专属段请放到下方对应平台。"
  }

  private var sectionDescriptors: [ProfileSectionDescriptor] {
    let custom = ProfileSectionCatalog.customSectionNames(in: items).map { name in
      ProfileSectionDescriptor(
        name: name,
        title: "自定义 Section",
        detail: "保留自定义或 Surge 后续扩展的 [\(name)] 配置。"
      )
    }
    return ProfileSectionCatalog.advanced + custom
  }

  private var fileHeaderItems: [ProfileDifferenceItem] {
    items.filter { $0.normalizedSection.isEmpty }
  }

  private static let fileHeaderID = "file-header"

  private var selectedDescriptor: ProfileSectionDescriptor? {
    sectionDescriptors.first { $0.id == selectedSectionID }
  }

  private var canAddCustomSection: Bool {
    let name = ProfileSectionCatalog.normalized(customSectionName)
    guard ProfileSectionCatalog.isValidCustomSectionName(name),
      ProfileSectionCatalog.descriptor(named: name) == nil
    else {
      return false
    }
    return !ProfileSectionCatalog.customSectionNames(in: items).contains {
      $0.caseInsensitiveCompare(name) == .orderedSame
    }
  }

  @ViewBuilder
  private var selectedSectionEditor: some View {
    if selectedSectionID == Self.fileHeaderID {
      compactSectionContainer {
        sectionToolbar(
          name: "文件头",
          title: "注释与 #! 指令",
          availability: nil,
          documentationURL: nil
        )
        itemRows(fileHeaderItems, emptyMessage: "没有平台专属的文件头注释或指令。")
        Button {
          items.append(.rawLine(section: "", line: ""))
        } label: {
          Label("添加原始行", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
      }
    } else if let descriptor = selectedDescriptor {
      let isAvailable = descriptor.isAvailable(on: platform)
      compactSectionContainer {
        sectionToolbar(
          name: descriptor.name,
          title: descriptor.title,
          availability: descriptor.availability,
          documentationURL: descriptor.documentationURL
        )
        if !isAvailable {
          Label(unavailableMessage(for: descriptor), systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
        itemRows(items(in: descriptor.name), emptyMessage: "此段暂无配置。")
        Menu {
          Button {
            items.append(ProfileDifferenceItem(section: descriptor.name, key: "", value: ""))
          } label: {
            Label("添加键值", systemImage: "equal")
          }
          Button {
            items.append(.rawLine(section: descriptor.name, line: ""))
          } label: {
            Label("添加原始行", systemImage: "chevron.left.forwardslash.chevron.right")
          }
        } label: {
          Label("添加", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .disabled(!isAvailable)
      }
    }
  }

  private func sectionToolbar(
    name: String,
    title: String,
    availability: ProfileSectionDescriptor.Availability?,
    documentationURL: String?
  ) -> some View {
    HStack(spacing: 8) {
      Text("[\(name)]")
        .font(.system(.caption, design: .monospaced, weight: .semibold))
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let availability, availability != .allPlatforms {
        Text(availability.displayName)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }
      Spacer()
      if let documentationURL, let url = URL(string: documentationURL) {
        Link(destination: url) {
          Image(systemName: "book.closed")
        }
        .help("查看 [\(name)] 官方文档")
      }
    }
  }

  private func compactSectionContainer<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      content()
    }
    .padding(SurgeSpacing.sm)
    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.primary.opacity(0.055))
    }
    .accessibilityIdentifier(sectionAccessibilityIdentifier(selectedSectionID))
  }

  @ViewBuilder
  private func itemRows(_ sectionItems: [ProfileDifferenceItem], emptyMessage: String) -> some View
  {
    if sectionItems.isEmpty {
      Text(emptyMessage)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.vertical, 3)
    } else {
      ForEach(sectionItems) { item in
        if let binding = itemBinding(for: item.id) {
          ProfileDifferenceRow(
            item: binding,
            platform: platform,
            locksSection: true,
            onDelete: { removeItem(item.id) }
          )
        }
      }
    }
  }

  private func items(in section: String) -> [ProfileDifferenceItem] {
    items.filter {
      $0.normalizedSection.caseInsensitiveCompare(section) == .orderedSame
    }
  }

  private func itemBinding(for id: UUID) -> Binding<ProfileDifferenceItem>? {
    guard items.contains(where: { $0.id == id }) else { return nil }
    return Binding(
      get: {
        items.first(where: { $0.id == id })
          ?? .rawLine(id: id, section: "", line: "")
      },
      set: { updated in
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index] = updated
      }
    )
  }

  private func removeItem(_ id: UUID) {
    let removedSection = items.first(where: { $0.id == id })?.normalizedSection.lowercased()
    items.removeAll { $0.id == id }
    if removedSection == selectedSectionID,
      ProfileSectionCatalog.descriptor(named: selectedSectionID) == nil,
      !items.contains(where: { $0.normalizedSection.lowercased() == selectedSectionID })
    {
      selectedSectionID = ProfileSectionCatalog.advanced.first?.id ?? "host"
    }
  }

  private func addCustomSection() {
    guard canAddCustomSection else { return }
    let name = ProfileSectionCatalog.normalized(customSectionName)
    items.append(ProfileDifferenceItem(section: name, key: "", value: ""))
    selectedSectionID = name.lowercased()
    customSectionName = ""
  }

  private func unavailableMessage(for descriptor: ProfileSectionDescriptor) -> String {
    if platform == nil {
      return
        "[\(descriptor.name)] \(descriptor.availability.displayName)，不能加入由两个平台共同引用的公共配置；请在对应平台中编辑。"
    }
    return "Surge 官方文档标注 [\(descriptor.name)] 为\(descriptor.availability.displayName)，不适用于当前平台。"
  }

  private func sectionAccessibilityIdentifier(_ suffix: String) -> String {
    let owner = platform?.rawValue.lowercased() ?? "shared"
    let normalized = suffix.lowercased().replacingOccurrences(of: " ", with: "-")
    return "\(owner)-profile-section-\(normalized)"
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
