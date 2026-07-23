import AppKit
import Observation
import SwiftUI

/// Feature state shared by Surge Shallow's module page, settings, and menu bar.
@MainActor
@Observable
public final class ModuleManagementController {
    @ObservationIgnored fileprivate let model: ModuleManagementModel

    public init() {
        model = ModuleManagementModel()
    }

    /// Starts an already configured feature from Surge Shallow's app runtime.
    public func startConfiguredRuntime() async {
        await model.startIfConfigured()
    }

    /// Activates the feature page, including its first-use setup when needed.
    public func activate() async {
        await model.start()
    }
}

/// Native module-management feature presented inside Surge Shallow's navigation.
public struct ModuleManagementView: View {
    private let controller: ModuleManagementController
    private let onOpenSettings: () -> Void

    public init(
        controller: ModuleManagementController,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        IntegratedModuleRoot(onOpenSettings: onOpenSettings)
            .environment(controller.model)
            .task { await controller.activate() }
    }
}

private struct IntegratedModuleRoot: View {
    @Environment(ModuleManagementModel.self) private var model
    let onOpenSettings: () -> Void

    var body: some View {
        @Bindable var model = model

        Group {
            if model.deviceMode == .client, !model.hasConfiguredRemoteServer {
                unavailableView(
                    title: "尚未设置服务器",
                    symbol: "network.slash",
                    description: "请完成欢迎向导，输入服务器 Mac 的 Surge Ponte 地址。",
                    buttonTitle: "打开欢迎向导"
                ) {
                    model.presentWelcomeWizard(allowDismiss: true)
                }
            } else if model.deviceMode == .client, model.remoteConnectionState.isUnavailable {
                unavailableView(
                    title: "服务器无响应",
                    symbol: "wifi.exclamationmark",
                    description: unavailableDescription,
                    buttonTitle: "重新连接"
                ) {
                    model.startRemoteSessionIfNeeded(force: true)
                }
            } else if model.deviceMode == .client, !model.remoteConnectionState.isOperational {
                ContentUnavailableView {
                    Label("正在连接服务器", systemImage: "network")
                } description: {
                    Text("正在通过 Surge Ponte 连接服务器 Mac…")
                } actions: {
                    ProgressView().controlSize(.small)
                }
            } else {
                ModulesView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("模块设置", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $model.presentsConfigurationWelcome) {
            ModuleManagementSetupView()
                .environment(model)
        }
        .alert(
            "模块管理",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
    }

    private func unavailableView(
        title: String,
        symbol: String,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(description)
        } actions: {
            Button(buttonTitle, action: action)
                .buttonStyle(.glassProminent)
            Button("模块设置", action: onOpenSettings)
        }
    }

    private var unavailableDescription: String {
        if let message = model.remoteConnectionState.unavailableMessage, !message.isEmpty {
            return "\(message)\n\n请确认服务器 Mac 上的 Surge Shallow 正在运行，且已启用模块 Web 管理。"
        }
        return "请确认服务器 Mac 上的 Surge Shallow 正在运行，且已启用模块 Web 管理。"
    }
}

/// Module-specific settings live under Surge Shallow's existing Settings page.
public struct ModuleManagementSettingsSection: View {
    private let controller: ModuleManagementController
    @State private var showsSettings = false

    public init(controller: ModuleManagementController) {
        self.controller = controller
    }

    public var body: some View {
        ModuleSettingsSectionContent(showsSettings: $showsSettings)
            .environment(controller.model)
            .sheet(isPresented: $showsSettings) {
                ModuleManagementSettingsView()
                    .environment(controller.model)
                    .frame(minWidth: 820, minHeight: 620)
            }
    }
}

private struct ModuleSettingsSectionContent: View {
    @Environment(ModuleManagementModel.self) private var model
    @Binding var showsSettings: Bool

    var body: some View {
        Section("模块管理") {
            LabeledContent(
                "来源模块",
                value: "\(model.modules.filter(\.isEnabled).count) / \(model.modules.count) 已启用"
            )
            LabeledContent(
                "发布方式",
                value: model.settings.storageMode == .local ? "Surge iCloud" : "GitHub"
            )
            HStack {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("模块设置…") { showsSettings = true }
            }
            Text("模块转换、参数覆盖、按平台排序与 .sgmodule 发布由此 App 的模块管理功能统一维护。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Quick module actions intended for Surge Shallow's menu-bar extra.
public struct ModuleManagementMenuSection: View {
    private let controller: ModuleManagementController

    public init(controller: ModuleManagementController) {
        self.controller = controller
    }

    public var body: some View {
        ModuleMenuContent()
            .environment(controller.model)
    }
}

private struct ModuleMenuContent: View {
    @Environment(ModuleManagementModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("模块管理", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                Text("\(model.modules.filter(\.isEnabled).count) / \(model.modules.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if model.isWorking, model.synchronizationTotalCount > 0 {
                ProgressView(
                    value: Double(model.synchronizationCompletedCount),
                    total: Double(model.synchronizationTotalCount)
                )
            }

            Button {
                Task { await model.updateAll() }
            } label: {
                Label("更新全部模块", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(
                model.modules.isEmpty
                    || model.isWorking
                    || model.isVerificationMode
                    || (model.deviceMode == .client && !model.isRemoteServerOperational)
            )

            if let url = model.combinedRawURL(for: .ios) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    Label("复制模块订阅地址", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if model.deviceMode == .server {
                Toggle(
                    "自动发布模块",
                    isOn: Binding(
                        get: { model.settings.automaticallyPublish },
                        set: {
                            guard !model.isVerificationMode else { return }
                            model.settings.automaticallyPublish = $0
                            model.saveSettings()
                        }
                    )
                )
                .disabled(model.isVerificationMode)
            }
        }
    }
}
