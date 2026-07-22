import Foundation

public enum RelayPlatform: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case macOS
    case iOS

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .macOS: "macOS"
        case .iOS: "iOS 与 iPadOS"
        }
    }

    public var symbolName: String {
        switch self {
        case .macOS: "macbook"
        case .iOS: "iphone"
        }
    }
}
