import AppKit
import SurgeModuleManagement
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surge Shallow")
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if model.isRefreshing {
                ProgressView(value: model.progressFraction)
            } else {
                HStack {
                    Label("\(model.enabledSourceCount) 个规则源", systemImage: "link")
                    Spacer()
                    Text("\(model.currentRuleCount) 条规则")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Divider()

            Button {
                Task { await model.refresh(force: true) }
            } label: {
                Label("合并生成", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.isRefreshing)

            Button {
                openWindow(id: "main")
                model.presentAvailableSoftwareUpdateOrCheck()
            } label: {
                Label(
                    model.softwareUpdate.availableUpdate.map { release in
                        "更新到 \(release.version.description)"
                    } ?? "检查软件更新",
                    systemImage: "arrow.down.app"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.softwareUpdate.isBusy)

            ForEach(model.document.targets.filter(\.isEnabled)) { target in
                Button {
                    model.openOutput(for: target.platform)
                } label: {
                    Label("打开 \(target.platform.displayName) Profile", systemImage: target.platform.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(target.lastGeneratedAt == nil)
            }

            Divider()

            ModuleManagementMenuSection(controller: model.moduleManagement)

            Divider()

            HStack {
                Button("显示主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
