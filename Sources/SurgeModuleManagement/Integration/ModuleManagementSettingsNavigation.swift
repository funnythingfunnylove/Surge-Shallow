import Foundation

extension Notification.Name {
    static let showModuleManagementAbout = Notification.Name("showModuleManagementAbout")
}

@MainActor
enum ModuleManagementSettingsNavigation {
    private static var hasPendingAboutRequest = false

    static func requestAbout() {
        hasPendingAboutRequest = true
        NotificationCenter.default.post(name: .showModuleManagementAbout, object: nil)
    }

    static func consumeAboutRequest() -> Bool {
        defer { hasPendingAboutRequest = false }
        return hasPendingAboutRequest
    }
}
