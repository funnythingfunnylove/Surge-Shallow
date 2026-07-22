import Foundation

public struct RelayBuiltInPolicy: Identifiable, Hashable, Sendable {
    public var name: String
    public var title: String
    public var detail: String

    public var id: String { name }

    public init(name: String, title: String, detail: String) {
        self.name = name
        self.title = title
        self.detail = detail
    }
}

public enum RelayPolicyCatalog {
    public static let builtInPolicies: [RelayBuiltInPolicy] = [
        .init(name: "DIRECT", title: "直接连接", detail: "不经过代理直接连接。"),
        .init(name: "REJECT", title: "拒绝连接", detail: "返回拒绝响应，适合一般拦截。"),
        .init(name: "REJECT-DROP", title: "静默丢弃", detail: "静默丢弃连接，避免激进重试。"),
        .init(name: "REJECT-TINYGIF", title: "透明图片", detail: "对 HTTP 请求返回 1 × 1 透明 GIF。"),
        .init(name: "REJECT-NO-DROP", title: "拒绝但不升级丢弃", detail: "保持返回拒绝响应。")
    ]

    public static func proxyNames(in sharedProfile: SharedProfile) -> [String] {
        definitionNames(sharedProfile.proxies)
    }

    public static func groupNames(in sharedProfile: SharedProfile) -> [String] {
        definitionNames(sharedProfile.proxyGroups)
    }

    public static func allNames(in sharedProfile: SharedProfile) -> [String] {
        uniqueCaseInsensitive(
            builtInPolicies.map(\.name)
                + proxyNames(in: sharedProfile)
                + groupNames(in: sharedProfile)
        )
    }

    private static func definitionNames(_ definitions: [ProxyDefinition]) -> [String] {
        uniqueCaseInsensitive(
            definitions.compactMap { definition in
                guard definition.kind == .definition else { return nil }
                let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
        )
    }

    private static func uniqueCaseInsensitive(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            seen.insert(value.lowercased()).inserted
        }
    }

    public static func replacingMemberNames(
        in parameters: String,
        renames: [String: String]
    ) -> String {
        RuleParser.splitTopLevelCSV(parameters).map { token in
            guard !token.contains("=") else { return token }
            return renames[token.lowercased()] ?? token
        }
        .joined(separator: ", ")
    }
}
