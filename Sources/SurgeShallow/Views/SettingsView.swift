import SwiftUI
import SurgeProfileRelayCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
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
                    .foregroundStyle(model.isSurgeICloudAvailable ? .green : .orange)
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

            Section("自动更新") {
                Toggle(
                    "自动检查规则源",
                    isOn: Binding(
                        get: { model.document.settings.automaticallyRefresh },
                        set: { model.document.settings.automaticallyRefresh = $0; model.save() }
                    )
                )
                Toggle(
                    "应用启动时检查",
                    isOn: Binding(
                        get: { model.document.settings.refreshOnLaunch },
                        set: { model.document.settings.refreshOnLaunch = $0; model.save() }
                    )
                )
                Picker(
                    "默认检查频率",
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
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { model.document.settings.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }

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
                LabeledContent("应用", value: "Surge Shallow")
                LabeledContent("目标系统", value: "macOS 26")
                LabeledContent("配置规范", value: "Surge Profile / Rule")
                Link("打开 Surge 配置文档", destination: URL(string: "https://manual.nssurge.com/overview/configuration.html")!)
            }
        }
        .formStyle(.grouped)
        .disabled(model.isRefreshing)
        .navigationTitle("设置")
    }
}
