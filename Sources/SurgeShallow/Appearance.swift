import SwiftUI

enum SurgeAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "SurgeShallow.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var detail: String {
        switch self {
        case .system: "随 macOS 外观自动切换，适合日常使用。"
        case .light: "始终使用明亮、清晰的浅色界面。"
        case .dark: "始终使用低亮度深色界面，减少夜间眩光。"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
