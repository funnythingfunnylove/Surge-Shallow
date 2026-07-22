import Foundation

public struct ProxyDefinition: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case definition
        case rawLine
    }

    public var id: UUID
    public var name: String
    public var type: String
    public var parameters: String
    public var kind: Kind
    public var presetID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        type: String,
        parameters: String,
        kind: Kind = .definition,
        presetID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.parameters = parameters
        self.kind = kind
        self.presetID = presetID
    }

    public static func rawLine(id: UUID = UUID(), _ line: String) -> ProxyDefinition {
        ProxyDefinition(id: id, name: "", type: "", parameters: line, kind: .rawLine)
    }

    public var presetValidationIssue: String? {
        guard kind == .definition, presetID == "snell-v6" else { return nil }
        guard type.caseInsensitiveCompare("snell") == .orderedSame else {
            return "Snell v6 预设必须使用 snell 协议。"
        }
        guard parameter(named: "version") == "6" else {
            return "Snell v6 参数必须包含 version=6。"
        }
        return nil
    }

    public var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedParameters = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .definition:
            return !trimmedName.isEmpty
                && !trimmedType.isEmpty
                && !trimmedParameters.isEmpty
                && !trimmedName.contains("=")
                && !trimmedName.contains(",")
                && !trimmedName.contains("\n")
                && !trimmedName.contains("\r")
                && !trimmedType.contains(",")
                && !trimmedType.contains("\n")
                && !trimmedType.contains("\r")
                && !parameters.contains("\n")
                && !parameters.contains("\r")
                && presetValidationIssue == nil
        case .rawLine:
            return !trimmedParameters.isEmpty
                && !parameters.contains("\n")
                && !parameters.contains("\r")
                && ProfileDifferenceCodec.sectionName(inRawLine: trimmedParameters) == nil
        }
    }

    public var renderedLine: String? {
        guard isValid else { return nil }
        switch kind {
        case .definition:
            let suffix = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name.trimmingCharacters(in: .whitespacesAndNewlines)) = \(type.trimmingCharacters(in: .whitespacesAndNewlines))"
                + (suffix.isEmpty ? "" : ", \(suffix)")
        case .rawLine:
            return parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func parameter(named name: String) -> String? {
        RuleParser.splitTopLevelCSV(parameters).compactMap { token -> (String, String)? in
            let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (
                parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        .first { $0.0 == name.lowercased() }?
        .1
    }
}

public struct ProxyTypeDescriptor: Identifiable, Hashable, Sendable {
    public var id: String
    public var type: String
    public var title: String
    public var placeholder: String
    public var detail: String

    public init(
        id: String? = nil,
        type: String,
        title: String,
        placeholder: String,
        detail: String
    ) {
        self.id = id ?? type
        self.type = type
        self.title = title
        self.placeholder = placeholder
        self.detail = detail
    }
}

public enum ProxyDefinitionCatalog {
    public static let proxyTypes: [ProxyTypeDescriptor] = [
        .init(type: "http", title: "HTTP", placeholder: "server.example.com, 8080, username, password", detail: "标准 HTTP 代理。"),
        .init(type: "https", title: "HTTPS", placeholder: "server.example.com, 443, username, password", detail: "通过 TLS 连接的 HTTP 代理。"),
        .init(type: "h2-connect", title: "HTTP/2 CONNECT", placeholder: "server.example.com, 443", detail: "HTTP/2 CONNECT；当前文档标注为 Surge Mac 6.6.0+。"),
        .init(type: "socks5", title: "SOCKS5", placeholder: "server.example.com, 1080, username, password", detail: "标准 SOCKS5 代理。"),
        .init(type: "socks5-tls", title: "SOCKS5 TLS", placeholder: "server.example.com, 443, username, password", detail: "通过 TLS 连接的 SOCKS5。"),
        .init(type: "ssh", title: "SSH", placeholder: "server.example.com, 22, username=user, private-key=key-name", detail: "通过 SSH 建立代理连接。"),
        .init(type: "wireguard", title: "WireGuard", placeholder: "section-name=wireguard-section", detail: "把 WireGuard L3 VPN 作为代理策略。"),
        .init(type: "tailscale", title: "Tailscale", placeholder: "section-name=my-tailnet", detail: "引用 Tailscale section；当前文档标注为 iOS 5.20.0+ / Mac 6.7.0+。"),
        .init(type: "snell", title: "Snell", placeholder: "server.example.com, 8000, psk=password, version=4", detail: "Surge Snell 协议，可填写 version=4 或 version=5。"),
        .init(id: "snell-v6", type: "snell", title: "Snell v6", placeholder: "server.example.com, 8000, psk=password, version=6", detail: "Snell v6 预设，要求 version=6；需要 iOS 5.20.0+ / Mac 6.7.0+。"),
        .init(type: "ss", title: "Shadowsocks", placeholder: "server.example.com, 8000, encrypt-method=chacha20-ietf-poly1305, password=...", detail: "Shadowsocks 代理。"),
        .init(type: "vmess", title: "VMess", placeholder: "server.example.com, 443, username=UUID", detail: "VMess 代理。"),
        .init(type: "trojan", title: "Trojan", placeholder: "server.example.com, 443, password=...", detail: "Trojan 代理。"),
        .init(type: "tuic", title: "TUIC", placeholder: "server.example.com, 443, token=..., alpn=h3", detail: "TUIC 代理。"),
        .init(type: "hysteria2", title: "Hysteria 2", placeholder: "server.example.com, 443, password=..., download-bandwidth=100", detail: "Hysteria 2 代理。"),
        .init(type: "anytls", title: "AnyTLS", placeholder: "server.example.com, 443, password=...", detail: "AnyTLS 代理。"),
        .init(type: "trust-tunnel", title: "Trust Tunnel", placeholder: "server.example.com, 443, username=..., password=...", detail: "AdGuard Trust Tunnel；当前文档标注为 Surge Mac 6.4.4+。")
    ]

    public static let groupTypes: [ProxyTypeDescriptor] = [
        .init(type: "select", title: "手动选择", placeholder: "ProxyA, ProxyB, DIRECT", detail: "由用户手动选择当前策略。"),
        .init(type: "url-test", title: "自动测速", placeholder: "ProxyA, ProxyB, url=http://www.gstatic.com/generate_204", detail: "选择延迟测试结果最好的策略。"),
        .init(type: "fallback", title: "故障转移", placeholder: "ProxyA, ProxyB", detail: "按顺序选择第一个可用策略。"),
        .init(type: "load-balance", title: "负载均衡", placeholder: "ProxyA, ProxyB", detail: "在多个可用策略之间分配请求。"),
        .init(type: "subnet", title: "网络环境", placeholder: "default = DIRECT, TYPE:WIFI = ProxyA", detail: "根据网络类型、SSID 等当前网络环境选择策略。"),
        .init(type: "smart", title: "智能选择", placeholder: "ProxyA, ProxyB, policy-priority=\"Premium:0.9\"", detail: "Smart Group 会根据实时连接表现自动选择策略；需要 iOS 5.11.0+ / Mac 5.7.0+。")
    ]

    public static func proxyDescriptor(for type: String) -> ProxyTypeDescriptor? {
        proxyTypes.first { $0.type.caseInsensitiveCompare(type) == .orderedSame }
    }

    public static func proxyDescriptor(for definition: ProxyDefinition) -> ProxyTypeDescriptor? {
        if let presetID = definition.presetID,
           let preset = proxyTypes.first(where: { $0.id == presetID }) {
            return preset
        }
        if inferredProxyPresetID(type: definition.type, parameters: definition.parameters) == "snell-v6" {
            return proxyTypes.first { $0.id == "snell-v6" }
        }
        return proxyDescriptor(for: definition.type)
    }

    public static func groupDescriptor(for type: String) -> ProxyTypeDescriptor? {
        groupTypes.first { $0.type.caseInsensitiveCompare(type) == .orderedSame }
    }

    public static func inferredProxyPresetID(type: String, parameters: String) -> String? {
        guard type.caseInsensitiveCompare("snell") == .orderedSame else { return nil }
        let definition = ProxyDefinition(name: "inferred", type: type, parameters: parameters)
        return definition.parameter(named: "version") == "6" ? "snell-v6" : nil
    }
}

public enum ProxyDefinitionCodec {
    public static func parse(profile: String, section: String) -> [ProxyDefinition] {
        ProfileDifferenceCodec.parse(profile)
            .filter { $0.normalizedSection.caseInsensitiveCompare(section) == .orderedSame }
            .map { item in
                switch item.kind {
                case .keyValue:
                    let tokens = RuleParser.splitTopLevelCSV(item.value)
                    let type = tokens.first ?? ""
                    let parameters = tokens.dropFirst().joined(separator: ", ")
                    let presetID = section.caseInsensitiveCompare("Proxy") == .orderedSame
                        ? ProxyDefinitionCatalog.inferredProxyPresetID(
                            type: type,
                            parameters: parameters
                        )
                        : nil
                    return ProxyDefinition(
                        name: item.key,
                        type: type,
                        parameters: parameters,
                        presetID: presetID
                    )
                case .rawLine:
                    return .rawLine(item.value)
                }
            }
    }

    public static func render(section: String, items: [ProxyDefinition]) -> String {
        let lines = items.compactMap(\.renderedLine)
        return (["[\(section)]"] + lines).joined(separator: "\n") + "\n"
    }
}
