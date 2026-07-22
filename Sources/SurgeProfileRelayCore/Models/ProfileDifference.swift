import Foundation

public struct ProfileDifferenceItem: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case keyValue
        case rawLine
    }

    public var id: UUID
    public var section: String
    public var key: String
    public var value: String
    public var kind: Kind

    public init(
        id: UUID = UUID(),
        section: String,
        key: String,
        value: String,
        kind: Kind = .keyValue
    ) {
        self.id = id
        self.section = section
        self.key = key
        self.value = value
        self.kind = kind
    }

    public static func rawLine(
        id: UUID = UUID(),
        section: String,
        line: String
    ) -> ProfileDifferenceItem {
        ProfileDifferenceItem(id: id, section: section, key: "", value: line, kind: .rawLine)
    }

    public var normalizedSection: String {
        section
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isRuleSection: Bool {
        normalizedSection.caseInsensitiveCompare("Rule") == .orderedSame
    }

    public var isValid: Bool {
        guard !isRuleSection else { return false }
        guard !section.contains("[") && !section.contains("]"),
              !section.contains("\n"),
              !section.contains("\r") else { return false }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .keyValue:
            return !normalizedSection.isEmpty
                && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !trimmedValue.isEmpty
                && !key.contains("\n")
                && !key.contains("\r")
                && !value.contains("\n")
                && !value.contains("\r")
        case .rawLine:
            return !trimmedValue.isEmpty
                && !value.contains("\n")
                && !value.contains("\r")
                && ProfileDifferenceCodec.sectionName(inRawLine: trimmedValue) == nil
        }
    }
}

public enum ProfileDifferenceCodec {
    public static func sectionName(inRawLine line: String) -> String? {
        sectionName(of: line.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func parse(_ profile: String) -> [ProfileDifferenceItem] {
        let lines = normalize(profile).components(separatedBy: "\n")
        var currentSection = ""
        var ignoresCurrentSection = false
        var result: [ProfileDifferenceItem] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let section = sectionName(of: trimmed) {
                currentSection = section
                ignoresCurrentSection = section.caseInsensitiveCompare("Rule") == .orderedSame
                continue
            }
            guard !ignoresCurrentSection, !trimmed.isEmpty, !isLegacyPlaceholder(trimmed) else {
                continue
            }

            if !trimmed.hasPrefix("#"),
               !trimmed.hasPrefix(";"),
               !trimmed.hasPrefix("//"),
               let equals = line.firstIndex(of: "=") {
                let key = String(line[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: equals)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !currentSection.isEmpty, !key.isEmpty, !value.isEmpty {
                    result.append(ProfileDifferenceItem(
                        section: currentSection,
                        key: key,
                        value: value
                    ))
                    continue
                }
            }

            result.append(.rawLine(section: currentSection, line: trimmed))
        }
        return result
    }

    public static func render(_ items: [ProfileDifferenceItem]) -> String {
        var preamble: [String] = []
        var sectionOrder: [String] = []
        var sectionLines: [String: [String]] = [:]
        var sectionDisplayNames: [String: String] = [:]

        for item in items where item.isValid && !item.isRuleSection {
            let line: String
            switch item.kind {
            case .keyValue:
                line = "\(item.key.trimmingCharacters(in: .whitespacesAndNewlines)) = \(item.value.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .rawLine:
                line = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let section = item.normalizedSection
            guard !section.isEmpty else {
                preamble.append(line)
                continue
            }
            let normalized = section.lowercased()
            if sectionLines[normalized] == nil {
                sectionOrder.append(normalized)
                sectionLines[normalized] = []
                sectionDisplayNames[normalized] = section
            }
            sectionLines[normalized, default: []].append(line)
        }

        var blocks: [String] = []
        if !preamble.isEmpty { blocks.append(preamble.joined(separator: "\n")) }
        for section in sectionOrder {
            guard let displayName = sectionDisplayNames[section],
                  let lines = sectionLines[section],
                  !lines.isEmpty else { continue }
            blocks.append((["[\(displayName)]"] + lines).joined(separator: "\n"))
        }
        guard !blocks.isEmpty else { return "" }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func sectionName(of line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]"), line.count >= 3 else { return nil }
        return String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLegacyPlaceholder(_ line: String) -> Bool {
        guard line.hasPrefix("#") else { return false }
        return line.contains("差异配置")
            || line.contains("只填写与公共配置不同或额外增加的项目")
            || line.contains("公共段会通过 #!include 自动复用")
    }
}

public enum ProfileOptionScope: String, Hashable, Sendable {
    case common
    case macOS
    case iOS
}

public struct ProfileOptionChoice: Identifiable, Hashable, Sendable {
    public var value: String
    public var label: String

    public var id: String { value }

    public init(_ value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

public enum ProfileOptionValueKind: Hashable, Sendable {
    case boolean
    case choice([ProfileOptionChoice])
    case text
    case number
    case port
    case list
}

public struct ProfileOptionDescriptor: Identifiable, Hashable, Sendable {
    public var section: String
    public var key: String
    public var title: String
    public var detail: String
    public var scope: ProfileOptionScope
    public var valueKind: ProfileOptionValueKind
    public var defaultValue: String
    public var placeholder: String

    public var id: String { "\(section.lowercased()).\(key.lowercased())" }

    public init(
        section: String = "General",
        key: String,
        title: String,
        detail: String,
        scope: ProfileOptionScope,
        valueKind: ProfileOptionValueKind,
        defaultValue: String,
        placeholder: String = ""
    ) {
        self.section = section
        self.key = key
        self.title = title
        self.detail = detail
        self.scope = scope
        self.valueKind = valueKind
        self.defaultValue = defaultValue
        self.placeholder = placeholder
    }

    public func makeItem() -> ProfileDifferenceItem {
        ProfileDifferenceItem(section: section, key: key, value: defaultValue)
    }
}

public enum ProfileOptionCatalog {
    public static let common: [ProfileOptionDescriptor] = [
        option("loglevel", "日志级别", "控制 Surge 日志详细程度。", .choice([.init("verbose"), .init("info"), .init("notify"), .init("warning")]), "notify"),
        option("ipv6", "IPv6 支持", "启用完整 IPv6 支持。", .boolean, "true"),
        option("ipv6-vif", "IPv6 VIF", "控制 Surge VIF 何时承载 IPv6。", .choice([.init("off", label: "关闭"), .init("auto", label: "自动"), .init("always", label: "始终")]), "auto"),
        option("dns-server", "DNS 服务器", "传统 DNS 服务器列表。", .list, "system, 1.1.1.1", "system, 1.1.1.1"),
        option("skip-proxy", "绕过代理", "不由 Surge 代理服务器处理的主机列表。", .list, "localhost, *.local", "localhost, *.local"),
        option("exclude-simple-hostnames", "排除简单主机名", "让不含点号的主机名绕过代理。", .boolean, "true"),
        option("external-controller-access", "外部控制器", "Surge Dashboard 或远程控制器访问参数。", .text, "key@0.0.0.0:6165", "key@0.0.0.0:6165"),
        option("http-api", "HTTP API", "HTTP API 的密钥与监听地址。", .text, "key@0.0.0.0:6166", "key@0.0.0.0:6166"),
        option("http-api-tls", "HTTP API TLS", "使用 HTTPS 提供 HTTP API。", .boolean, "true"),
        option("http-api-web-dashboard", "Web Dashboard", "允许通过浏览器控制 Surge。", .boolean, "true"),
        option("show-error-page-for-reject", "REJECT 错误页", "普通 HTTP 请求被拒绝时显示错误页。", .boolean, "true"),
        option("full-header-mode", "完整 Header 模式", "向重写、脚本和抓包暴露重复 Header。", .boolean, "true"),
        option("tun-excluded-routes", "VIF 排除路由", "不经过 Surge VIF 的 CIDR 列表。", .list, "192.168.0.0/16", "192.168.0.0/16, fd00::/8"),
        option("tun-included-routes", "VIF 包含路由", "为 Surge VIF 添加更具体的路由。", .list, "", "CIDR，多个值用逗号分隔"),
        option("internet-test-url", "联网测试 URL", "DIRECT 与互联网连通性测试地址。", .text, "http://www.gstatic.com/generate_204", "https://example.com/generate_204"),
        option("proxy-test-url", "代理测试 URL", "代理策略默认测试地址。", .text, "http://www.gstatic.com/generate_204", "https://example.com/generate_204"),
        option("test-timeout", "测试超时", "连通性测试超时时间。", .number, "5", "秒数"),
        option("always-real-ip", "始终返回真实 IP", "指定不使用 Fake IP 的主机列表。", .list, "", "*.example.com"),
        option("hijack-dns", "劫持 DNS", "由 Surge Fake DNS responder 接管的 DNS 目标。", .list, "*:53", "*:53"),
        option("force-http-engine-hosts", "强制 HTTP Engine", "让匹配的 TCP 连接进入 HTTP Engine。", .list, "", "主机列表"),
        option("encrypted-dns-follow-outbound-mode", "加密 DNS 跟随出站", "让加密 DNS 查询遵循出站模式和规则。", .boolean, "true"),
        option("encrypted-dns-server", "加密 DNS", "DoH、HTTP/3 或 QUIC DNS 服务地址。", .list, "https://1.1.1.1/dns-query", "https://example.com/dns-query"),
        option("encrypted-dns-skip-cert-verification", "跳过加密 DNS 证书校验", "不安全，仅用于明确需要的场景。", .boolean, "false"),
        option("use-local-host-item-for-proxy", "代理使用本地 Host", "代理连接可使用本地 DNS/Host 映射结果。", .boolean, "true"),
        option("geoip-maxmind-url", "GeoIP 数据库 URL", "MaxMind GeoIP 数据库更新地址。", .text, "", "https://example.com/GeoLite2-Country.mmdb"),
        option("disable-geoip-db-auto-update", "停用 GeoIP 自动更新", "关闭 GeoIP 数据库自动更新。", .boolean, "true"),
        option("allow-dns-svcb", "允许 DNS SVCB", "允许系统进行 SVCB 记录查询。", .boolean, "true"),
        option("udp-policy-not-supported-behaviour", "UDP 不支持时", "策略不支持 UDP relay 时的回退行为。", .choice([.init("DIRECT"), .init("REJECT")]), "REJECT"),
        option("proxy-test-udp", "代理 UDP 测试", "代理默认 UDP 测试目标。", .text, "apple.com@8.8.8.8", "apple.com@8.8.8.8"),
        option("udp-priority", "UDP 优先", "高负载时优先处理 UDP 数据包。", .boolean, "true"),
        option("always-raw-tcp-hosts", "始终使用 Raw TCP", "这些主机跳过 80/443 协议嗅探。", .list, "", "主机列表"),
        option("proxy-restricted-to-lan", "代理仅限当前子网", "限制代理服务只接受当前子网设备。", .boolean, "true"),
        option("gateway-restricted-to-lan", "网关仅限当前子网", "限制网关服务只接受当前子网设备。", .boolean, "true"),
        option("icmp-forwarding", "转发 ICMP", "Enhanced Mode 下直接转发 ICMP。", .boolean, "true"),
        option("block-quic", "QUIC 策略", "全局覆盖 QUIC 阻止行为。", .choice([.init("per-policy", label: "按策略"), .init("all-proxy", label: "所有代理"), .init("all", label: "全部"), .init("always-allow", label: "始终允许")]), "per-policy")
    ]

    public static let iOSOnly: [ProfileOptionDescriptor] = [
        platformOption("allow-wifi-access", "允许局域网代理访问", "允许局域网其他设备访问 Surge 代理服务。", .iOS, .boolean, "true"),
        platformOption("wifi-access-http-port", "HTTP 代理端口", "Surge HTTP 代理服务端口。", .iOS, .port, "6152", "1…65535"),
        platformOption("wifi-access-socks5-port", "SOCKS5 代理端口", "Surge SOCKS5 代理服务端口。", .iOS, .port, "6153", "1…65535"),
        platformOption("wifi-access-http-auth", "HTTP 代理认证", "HTTP 代理服务的用户名与密码。", .iOS, .text, "", "username:password"),
        platformOption("wifi-assist", "Wi-Fi Assist", "Wi-Fi 较差时允许蜂窝网络辅助。", .iOS, .boolean, "true"),
        platformOption("hide-vpn-icon", "隐藏 VPN 图标", "隐藏状态栏中的 VPN 图标。", .iOS, .boolean, "true"),
        platformOption("all-hybrid", "所有连接使用 Hybrid", "所有 TCP 与 DNS 同时尝试 Wi-Fi 和蜂窝网络；仅建议无限流量套餐使用。", .iOS, .boolean, "true"),
        platformOption("allow-hotspot-access", "允许热点代理访问", "个人热点开启时允许其他设备访问 Surge 代理服务。", .iOS, .boolean, "true"),
        platformOption("include-all-networks", "接管所有网络", "防止应用绑定物理接口绕过 Surge；可能影响 AirDrop 和 Xcode 调试。", .iOS, .boolean, "true"),
        platformOption("include-local-networks", "接管本地网络", "让 Surge VIF 处理发往 LAN 的请求；需要同时开启 include-all-networks。", .iOS, .boolean, "true"),
        platformOption("include-apns", "接管 APNs", "让 Surge VIF 处理 Apple Push Notification 流量；需要 include-all-networks。", .iOS, .boolean, "true"),
        platformOption("include-cellular-services", "接管蜂窝服务", "接管 VoLTE、Wi-Fi Calling、IMS、MMS 等可路由流量；需要 include-all-networks。", .iOS, .boolean, "true"),
        platformOption("compatibility-mode", "兼容模式", "控制 Surge iOS 的 Proxy/VIF 接管方式。", .iOS, .choice([
            .init("0", label: "0 · 自动"),
            .init("1", label: "1 · Proxy + VIF"),
            .init("2", label: "2 · 仅 Proxy"),
            .init("3", label: "3 · 仅 VIF"),
            .init("4", label: "4 · Proxy 使用 VIF 地址"),
            .init("5", label: "5 · VIF 小路由")
        ]), "0"),
        platformOption("auto-suspend", "自动暂停", "检测到由 Surge Mac 接管的网络时自动暂停 Surge iOS。", .iOS, .boolean, "true")
    ]

    public static let macOSOnly: [ProfileOptionDescriptor] = [
        platformOption("use-default-policy-if-wifi-not-primary", "Wi-Fi 非主接口时使用默认策略", "控制 Wi-Fi 非主网络接口时的 SSID/BSSID 匹配行为。", .macOS, .boolean, "true"),
        platformOption("read-etc-hosts", "读取 /etc/hosts", "使用本机 /etc/hosts 的 DNS 映射。", .macOS, .boolean, "true"),
        platformOption("http-listen", "HTTP 代理监听", "macOS HTTP 代理服务监听地址。", .macOS, .text, "0.0.0.0:6152", "0.0.0.0:6152"),
        platformOption("socks5-listen", "SOCKS5 代理监听", "macOS SOCKS5 代理服务监听地址。", .macOS, .text, "0.0.0.0:6153", "0.0.0.0:6153"),
        platformOption("show-error-page", "显示内置错误页", "请求失败时显示 Surge 内置 HTTP 错误页。", .macOS, .boolean, "true"),
        platformOption("always-raw-tcp-keywords", "Raw TCP 关键字", "主机名包含任一关键字时跳过协议嗅探。", .macOS, .list, "", "关键字列表"),
        platformOption("debug-cpu-usage", "CPU 调试模式", "会降低性能，仅在排障时开启。", .macOS, .boolean, "false"),
        platformOption("debug-memory-usage", "内存调试模式", "会降低性能，仅在排障时开启。", .macOS, .boolean, "false")
    ]

    public static func options(for platform: RelayPlatform) -> [ProfileOptionDescriptor] {
        common + (platform == .macOS ? macOSOnly : iOSOnly)
    }

    public static func platformOnlyOptions(for platform: RelayPlatform) -> [ProfileOptionDescriptor] {
        platform == .macOS ? macOSOnly : iOSOnly
    }

    public static func descriptor(section: String, key: String) -> ProfileOptionDescriptor? {
        let section = section.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return (common + macOSOnly + iOSOnly).first {
            $0.section.caseInsensitiveCompare(section) == .orderedSame
                && $0.key.caseInsensitiveCompare(key) == .orderedSame
        }
    }

    private static func option(
        _ key: String,
        _ title: String,
        _ detail: String,
        _ valueKind: ProfileOptionValueKind,
        _ defaultValue: String,
        _ placeholder: String = ""
    ) -> ProfileOptionDescriptor {
        ProfileOptionDescriptor(
            key: key,
            title: title,
            detail: detail,
            scope: .common,
            valueKind: valueKind,
            defaultValue: defaultValue,
            placeholder: placeholder
        )
    }

    private static func platformOption(
        _ key: String,
        _ title: String,
        _ detail: String,
        _ scope: ProfileOptionScope,
        _ valueKind: ProfileOptionValueKind,
        _ defaultValue: String,
        _ placeholder: String = ""
    ) -> ProfileOptionDescriptor {
        ProfileOptionDescriptor(
            key: key,
            title: title,
            detail: detail,
            scope: scope,
            valueKind: valueKind,
            defaultValue: defaultValue,
            placeholder: placeholder
        )
    }
}
