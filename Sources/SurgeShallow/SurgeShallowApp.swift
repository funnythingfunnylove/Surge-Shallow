import SwiftUI
import SurgeProfileRelayCore

@main
struct SurgeShallowApp: App {
    @State private var model = AppModel()
    @AppStorage(SurgeAppearance.storageKey) private var appearanceRawValue = SurgeAppearance.system.rawValue

    private var appearance: SurgeAppearance {
        SurgeAppearance(rawValue: appearanceRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup("Surge Shallow") {
            RootView()
                .environment(model)
                .preferredColorScheme(appearance.preferredColorScheme)
                .frame(minWidth: 980, minHeight: 640)
                .task { model.start() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Relay") {
                Button("立即更新并合并") {
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
                .preferredColorScheme(appearance.preferredColorScheme)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(appearance.preferredColorScheme)
                .frame(width: 620, height: 520)
        }
    }
}
