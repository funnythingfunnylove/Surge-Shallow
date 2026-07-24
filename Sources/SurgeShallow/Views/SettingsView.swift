import AppKit
import SwiftUI
import SurgeModuleManagement
import SurgeProfileRelayCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SurgeAppearance.storageKey) private var appearanceRawValue = SurgeAppearance.system.rawValue

    private var appearance: SurgeAppearance {
        SurgeAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var softwareUpdate = model.softwareUpdate

        Form {
            Section("外观") {
                Picker(
                    "显示模式",
                    selection: Binding(
                        get: { appearance },
                        set: { appearanceRawValue = $0.rawValue }
                    )
                ) {
                    ForEach(SurgeAppearance.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Label(appearance.detail, systemImage: appearance.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            Section("iCloud 与输出") {
                LabeledContent("目录") {
                    Text(model.document.settings.outputDirectory)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                HStack {
                    Label(
                        model.isSurgeICloudAvailable ? "已检测到 Surge iCloud 容器" : "未检测到 Surge iCloud 容器",
                        systemImage: model.isSurgeICloudAvailable ? "icloud.and.arrow.up" : "icloud.slash"
                    )
                    .foregroundStyle(model.isSurgeICloudAvailable ? SurgePalette.success : SurgePalette.warning)
                    Spacer()
                    Button("使用默认 Surge 目录") { model.useDefaultSurgeICloudDirectory() }
                        .disabled(!model.isSurgeICloudAvailable)
                    Button("选择…") { model.chooseOutputDirectory() }
                    Button("在 Finder 中显示") { model.openOutputDirectory() }
                }
                Text("默认目录位于 Surge 自己的 iCloud Documents 容器。生成的 .conf 会由 Surge 在 macOS、iPhone 和 iPad 之间同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自动合并生成") {
                Toggle(
                    "自动处理需要本地转换的规则源",
                    isOn: Binding(
                        get: { model.document.settings.automaticallyRefresh },
                        set: { model.document.settings.automaticallyRefresh = $0; model.save() }
                    )
                )
                Toggle(
                    "应用启动时处理并生成",
                    isOn: Binding(
                        get: { model.document.settings.refreshOnLaunch },
                        set: { model.document.settings.refreshOnLaunch = $0; model.save() }
                    )
                )
                Picker(
                    "内联规则源处理频率",
                    selection: Binding(
                        get: { model.document.settings.refreshIntervalMinutes },
                        set: { model.document.settings.refreshIntervalMinutes = $0; model.save() }
                    )
                ) {
                    Text("每 15 分钟").tag(15)
                    Text("每小时").tag(60)
                    Text("每 6 小时").tag(360)
                    Text("每天").tag(1_440)
                }
                Text("Surge Ruleset 仅保存 URL、策略与参数，由 Surge 自行加载；不会被 Surge Shallow 下载、缓存或定时更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { model.document.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

            Section("软件更新") {
                LabeledContent("当前版本") {
                    Text("\(softwareUpdate.currentVersion) (\(softwareUpdate.currentBuild))")
                        .monospacedDigit()
                }
                Toggle(
                    "自动检查 GitHub Release（每 6 小时）",
                    isOn: $softwareUpdate.automaticChecksEnabled
                )
                LabeledContent("更新状态") {
                    HStack(spacing: 7) {
                        if softwareUpdate.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: softwareUpdateStatusSymbol)
                                .foregroundStyle(softwareUpdateStatusColor)
                        }
                        Text(softwareUpdate.statusText)
                            .foregroundStyle(softwareUpdateStatusColor)
                    }
                }
                HStack {
                    Text("通过 GitHub 最新正式 Release 检查版本，并在安装前校验更新包与代码签名完整性。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if softwareUpdate.availableUpdate != nil {
                        Button("查看更新日志") {
                            openWindow(id: "main")
                            softwareUpdate.presentAvailableUpdate()
                        }
                    }
                    Button("检查更新") {
                        openWindow(id: "main")
                        Task { await model.checkForSoftwareUpdates() }
                    }
                    .disabled(softwareUpdate.isBusy)
                }
            }

            ModuleManagementSettingsSection(controller: model.moduleManagement)

            Section("安全门禁") {
                Toggle(
                    "发布前使用 surge-cli 校验",
                    isOn: Binding(
                        get: { model.document.settings.validateWithSurgeCLI },
                        set: { model.document.settings.validateWithSurgeCLI = $0; model.save() }
                    )
                )
                Stepper(
                    "请求超时：\(model.document.settings.requestTimeoutSeconds) 秒",
                    value: Binding(
                        get: { model.document.settings.requestTimeoutSeconds },
                        set: { model.document.settings.requestTimeoutSeconds = $0; model.save() }
                    ),
                    in: 5...120,
                    step: 5
                )
                Stepper(
                    "单个规则源上限：\(model.document.settings.maximumSourceSizeMB) MB",
                    value: Binding(
                        get: { model.document.settings.maximumSourceSizeMB },
                        set: { model.document.settings.maximumSourceSizeMB = $0; model.save() }
                    ),
                    in: 1...50
                )
                Text("下载内容只有在解析成功后才会替换缓存。首次失败会停止发布；后续失败会使用最后成功缓存并明确标记。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: 54, height: 54)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Surge Shallow")
                            .font(.headline)
                        Text("版本 \(softwareUpdate.currentVersion) (\(softwareUpdate.currentBuild))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                LabeledContent("目标系统", value: "macOS 26")
                LabeledContent("配置规范", value: "Surge Profile / Rule / Module")
                Link("打开 Surge 配置文档", destination: URL(string: "https://manual.nssurge.com/overview/configuration.html")!)

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Surge Shallow 以 MIT License 开源；原生模块管理基于 Apache License 2.0 授权的 SurgeRelay-macOS 进行整合与适配。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        aboutLink(
                            title: "Surge Shallow",
                            detail: "MIT License",
                            systemImage: "doc.text",
                            destination: "https://github.com/funnythingfunnylove/Surge-Shallow/blob/main/LICENSE"
                        )
                        aboutLink(
                            title: "SurgeRelay-macOS",
                            detail: "Apache License 2.0",
                            systemImage: "doc.text",
                            destination: "https://github.com/EEliberto/SurgeRelay-macOS/blob/b19d0dd6d6b9593be9cdf01c578de76c55d43150/LICENSE"
                        )
                        aboutLink(
                            title: "第三方声明",
                            detail: "THIRD_PARTY_NOTICES.md",
                            systemImage: "list.bullet.rectangle",
                            destination: "https://github.com/funnythingfunnylove/Surge-Shallow/blob/main/THIRD_PARTY_NOTICES.md"
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Label("开源许可", systemImage: "checkmark.seal")
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("特别感谢 SurgeRelay-macOS 项目及其作者公开的源码与设计积累，也感谢 Script Hub 与 Surge 为模块转换和配置生态提供的基础能力。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        aboutLink(
                            title: "Surge Relay",
                            detail: "EEliberto/SurgeRelay-macOS",
                            systemImage: "shippingbox",
                            destination: "https://github.com/EEliberto/SurgeRelay-macOS"
                        )
                        aboutLink(
                            title: "Script Hub",
                            detail: "github.com/Script-Hub-Org",
                            systemImage: "arrow.triangle.branch",
                            destination: "https://github.com/Script-Hub-Org"
                        )
                        aboutLink(
                            title: "Surge",
                            detail: "nssurge.com",
                            systemImage: "bolt.horizontal.circle",
                            destination: "https://nssurge.com"
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Label("感谢", systemImage: "heart")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .formStyle(.grouped)
        .disabled(model.isRefreshing)
        .navigationTitle("设置")
    }

    private var softwareUpdateStatusColor: Color {
        switch model.softwareUpdate.phase.presentation.tone {
        case .neutral: .secondary
        case .accent: SurgePalette.accent
        case .success: SurgePalette.success
        case .danger: SurgePalette.danger
        }
    }

    private var softwareUpdateStatusSymbol: String {
        model.softwareUpdate.phase.presentation.symbol
    }

    private func aboutLink(
        title: String,
        detail: String,
        systemImage: String,
        destination: String
    ) -> some View {
        Link(destination: URL(string: destination)!) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SurgePalette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
