import Foundation

public struct ProfileSectionDescriptor: Identifiable, Hashable, Sendable {
    public enum Availability: String, Hashable, Sendable {
        case allPlatforms
        case macOS
        case iOS

        public var displayName: String {
            switch self {
            case .allPlatforms: "macOS 与 iOS"
            case .macOS: "仅 macOS"
            case .iOS: "仅 iOS / iPadOS"
            }
        }
    }

    public var name: String
    public var title: String
    public var detail: String
    public var availability: Availability
    public var documentationURL: String?

    public var id: String { name.lowercased() }

    public init(
        name: String,
        title: String,
        detail: String,
        availability: Availability = .allPlatforms,
        documentationURL: String? = nil
    ) {
        self.name = name
        self.title = title
        self.detail = detail
        self.availability = availability
        self.documentationURL = documentationURL
    }

    public func isAvailable(on platform: RelayPlatform?) -> Bool {
        switch availability {
        case .allPlatforms:
            true
        case .macOS:
            platform == .macOS
        case .iOS:
            platform == .iOS
        }
    }
}

/// Profile section names documented by Surge that are safe to keep outside the
/// app-managed General, Proxy, Proxy Group, and Rule sections.
public enum ProfileSectionCatalog {
    public static let advanced: [ProfileSectionDescriptor] = [
        .init(
            name: "Host",
            title: "本地 DNS 映射",
            detail: "配置域名到 IP、别名或指定 DNS 服务器的映射。",
            documentationURL: "https://manual.nssurge.com/dns/local-dns-mapping.html"
        ),
        .init(
            name: "MITM",
            title: "HTTPS 解密",
            detail: "配置 MITM 主机名与 HTTPS 解密选项。",
            documentationURL: "https://manual.nssurge.com/http-processing/mitm.html"
        ),
        .init(
            name: "Script",
            title: "脚本",
            detail: "配置 HTTP、规则、DNS、事件与定时脚本。",
            documentationURL: "https://manual.nssurge.com/scripting/common.html"
        ),
        .init(
            name: "URL Rewrite",
            title: "URL 重写",
            detail: "重写、跳转或拒绝匹配的 URL。",
            documentationURL: "https://manual.nssurge.com/http-processing/url-rewrite.html"
        ),
        .init(
            name: "Header Rewrite",
            title: "Header 重写",
            detail: "添加、删除或替换请求与响应 Header。",
            documentationURL: "https://manual.nssurge.com/http-processing/header-rewrite.html"
        ),
        .init(
            name: "Body Rewrite",
            title: "Body 重写",
            detail: "使用正则或 JQ 修改请求与响应正文。",
            documentationURL: "https://manual.nssurge.com/http-processing/body-rewrite.html"
        ),
        .init(
            name: "Map Local",
            title: "本地响应映射",
            detail: "将匹配请求映射到本地数据、文件或脚本响应。",
            documentationURL: "https://manual.nssurge.com/http-processing/mock.html"
        ),
        .init(
            name: "SSID Setting",
            title: "子网设置",
            detail: "按 SSID、BSSID、路由器或网络类型应用子网设置。",
            documentationURL: "https://manual.nssurge.com/others/subnet-settings.html"
        ),
        .init(
            name: "Panel",
            title: "信息面板",
            detail: "配置静态或脚本驱动的信息面板。",
            availability: .iOS,
            documentationURL: "https://manual.nssurge.com/others/panel.html"
        ),
        .init(
            name: "Port Forwarding",
            title: "端口转发",
            detail: "配置本机监听端口到目标地址的 TCP 或 UDP 转发。",
            documentationURL: "https://manual.nssurge.com/others/port-forwarding.html"
        ),
        .init(
            name: "DHCP",
            title: "DHCP",
            detail: "配置 Surge Mac DHCP 租约行为。",
            availability: .macOS,
            documentationURL: "https://manual.nssurge.com/others/dhcp.html"
        ),
        .init(
            name: "Testing",
            title: "网络测试",
            detail: "配置吞吐量测试的下载、上传与并发参数。",
            availability: .macOS,
            documentationURL: "https://manual.nssurge.com/others/testing.html"
        ),
        .init(
            name: "MTProto",
            title: "MTProto 代理服务",
            detail: "配置 Telegram MTProto 代理监听与 DC 数据源。",
            documentationURL: "https://manual.nssurge.com/others/mtproto.html"
        ),
        .init(
            name: "Keystore",
            title: "证书存储",
            detail: "为需要客户端证书的代理策略定义可复用证书。",
            documentationURL: "https://manual.nssurge.com/policy/proxy.html"
        ),
        .init(
            name: "Ruleset Streaming",
            title: "内联规则集",
            detail: "在 Profile 内嵌可由 RULE-SET 引用的规则集合。",
            availability: .macOS,
            documentationURL: "https://manual.nssurge.com/rule/ruleset.html"
        )
    ]

    public static let managedSectionNames = ["General", "Proxy", "Proxy Group", "Rule"]

    public static func descriptor(named name: String) -> ProfileSectionDescriptor? {
        advanced.first { $0.name.caseInsensitiveCompare(normalized(name)) == .orderedSame }
    }

    public static func customSectionNames(in items: [ProfileDifferenceItem]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        let reserved = Set((advanced.map(\.name) + managedSectionNames).map { $0.lowercased() })

        for item in items {
            let name = item.normalizedSection
            let identity = name.lowercased()
            guard !name.isEmpty, !reserved.contains(identity), seen.insert(identity).inserted else {
                continue
            }
            result.append(name)
        }
        return result
    }

    public static func isValidCustomSectionName(_ value: String) -> Bool {
        let name = normalized(value)
        guard !name.isEmpty,
              !name.contains("["),
              !name.contains("]"),
              !name.contains("\n"),
              !name.contains("\r") else {
            return false
        }
        return !managedSectionNames.contains {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    public static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
