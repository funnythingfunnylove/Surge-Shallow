import AppKit
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

    var applicationAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Applies the selected appearance at the AppKit application level.
///
/// SwiftUI does not reliably clear a window's previous explicit color scheme
/// when `preferredColorScheme` changes from light/dark to `nil`. Assigning
/// `nil` to `NSApplication.appearance` explicitly releases that override and
/// lets every window follow the current macOS appearance again.
@MainActor
final class ApplicationAppearanceSynchronizer {
    static let shared = ApplicationAppearanceSynchronizer()

    private let setApplicationAppearance: (NSAppearance?) -> Void

    init(
        setApplicationAppearance: @escaping (NSAppearance?) -> Void = {
            NSApplication.shared.appearance = $0
        }
    ) {
        self.setApplicationAppearance = setApplicationAppearance
    }

    func apply(_ appearance: SurgeAppearance) {
        setApplicationAppearance(appearance.applicationAppearance)
    }
}

private struct ApplicationAppearanceSynchronizationModifier: ViewModifier {
    let appearance: SurgeAppearance

    func body(content: Content) -> some View {
        content.task(id: appearance.rawValue) {
            ApplicationAppearanceSynchronizer.shared.apply(appearance)
        }
    }
}

extension View {
    func synchronizeApplicationAppearance(_ appearance: SurgeAppearance) -> some View {
        modifier(ApplicationAppearanceSynchronizationModifier(appearance: appearance))
    }
}
