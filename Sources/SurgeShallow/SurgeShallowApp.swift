import SwiftUI
import SurgeModuleManagement
import SurgeProfileRelayCore

@main
struct SurgeShallowApp: App {
    @State private var model = AppModel()
    @AppStorage(SurgeAppearance.storageKey) private var appearanceRawValue = SurgeAppearance.system.rawValue

    private var appearance: SurgeAppearance {
        SurgeAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        Window("Surge Shallow", id: "main") {
            RootView()
                .environment(model)
                .surgeTheme()
                .synchronizeApplicationAppearance(appearance)
                .frame(minWidth: 980, minHeight: 640)
                .task { model.start() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            SoftwareUpdateCommands(model: model)

            CommandMenu("Relay") {
                Button("合并生成") {
                    Task { await model.refresh(force: true) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isRefreshing)

                Button("打开输出目录") {
                    model.openOutputDirectory()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Surge Shallow", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") {
            MenuBarView()
                .environment(model)
                .surgeTheme()
                .synchronizeApplicationAppearance(appearance)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .surgeTheme()
                .synchronizeApplicationAppearance(appearance)
                .frame(width: 620, height: 520)
                .background(SurgeBackground())
                .background(WindowGlassConfigurator().frame(width: 0, height: 0))
        }
    }
}

private struct SoftwareUpdateCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("检查更新…") {
                openWindow(id: "main")
                model.presentAvailableSoftwareUpdateOrCheck()
            }
            .disabled(model.softwareUpdate.isBusy)
        }
    }
}
