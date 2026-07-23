import SwiftUI
import SurgeProfileRelayCore

enum SurgePalette {
    // Keep these light/dark components aligned with Packaging/Assets.xcassets/AccentColor.
    // The SwiftUI views use this value while AppKit controls resolve the packaged asset.
    static let accent = adaptive(
        light: NSColor(srgbRed: 0.22, green: 0.40, blue: 0.46, alpha: 1),
        dark: NSColor(srgbRed: 0.48, green: 0.70, blue: 0.73, alpha: 1)
    )
    static let accentSoft = adaptive(
        light: NSColor(srgbRed: 0.47, green: 0.62, blue: 0.65, alpha: 1),
        dark: NSColor(srgbRed: 0.61, green: 0.78, blue: 0.79, alpha: 1)
    )
    static let success = adaptive(
        light: NSColor(srgbRed: 0.27, green: 0.52, blue: 0.42, alpha: 1),
        dark: NSColor(srgbRed: 0.43, green: 0.70, blue: 0.57, alpha: 1)
    )
    static let warning = adaptive(
        light: NSColor(srgbRed: 0.68, green: 0.49, blue: 0.25, alpha: 1),
        dark: NSColor(srgbRed: 0.80, green: 0.63, blue: 0.38, alpha: 1)
    )
    static let danger = adaptive(
        light: NSColor(srgbRed: 0.66, green: 0.31, blue: 0.30, alpha: 1),
        dark: NSColor(srgbRed: 0.84, green: 0.47, blue: 0.46, alpha: 1)
    )
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevatedSurface = Color(nsColor: .textBackgroundColor)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum SurgeSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum SurgeRadius {
    static let control: CGFloat = 10
    static let card: CGFloat = 16
    static let hero: CGFloat = 22
}

struct SurgeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    SurgePalette.accent.opacity(colorScheme == .dark ? 0.10 : 0.055),
                    .clear,
                    SurgePalette.accentSoft.opacity(colorScheme == .dark ? 0.055 : 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct RelayCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(SurgeSpacing.lg)
            .background(
                SurgePalette.surface.opacity(0.94),
                in: RoundedRectangle(cornerRadius: SurgeRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SurgeRadius.card, style: .continuous)
                    .strokeBorder(.primary.opacity(0.075))
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.035), radius: 12, y: 5)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.35)
                .foregroundStyle(SurgePalette.accent)
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .tracking(-0.5)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct GlassProgressOverlay: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: SurgeSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(SurgeSpacing.xl)
        .frame(width: 290)
        .glassEffect()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(detail)")
    }
}

struct StatusPill: View {
    let state: RuleSourceState

    private var color: Color {
        switch state {
        case .never: .secondary
        case .checking: SurgePalette.accent
        case .current: SurgePalette.success
        case .updated: SurgePalette.accentSoft
        case .staleCache: SurgePalette.warning
        case .failed: SurgePalette.danger
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.displayName)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        RelayCard {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct SurgeThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .accentColor(SurgePalette.accent)
            .tint(SurgePalette.accent)
    }
}

extension View {
    func surgeTheme() -> some View {
        modifier(SurgeThemeModifier())
    }
}

extension UpdateRecord.Outcome {
    var color: Color {
        switch self {
        case .success: SurgePalette.success
        case .warning: SurgePalette.warning
        case .failure: SurgePalette.danger
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.circle.fill"
        }
    }
}
