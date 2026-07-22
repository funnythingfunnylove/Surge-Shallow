import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RuleSourceFetchError: LocalizedError, Sendable {
    case invalidURL
    case unsupportedScheme
    case invalidResponse
    case httpStatus(Int)
    case sourceTooLarge(Int)
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidURL: "规则源 URL 无效。"
        case .unsupportedScheme: "规则源只允许使用 HTTPS 或 HTTP。"
        case .invalidResponse: "上游没有返回有效的 HTTP 响应。"
        case .httpStatus(let status): "上游返回 HTTP \(status)。"
        case .sourceTooLarge(let megabytes): "规则源超过 \(megabytes) MB 安全上限。"
        case .invalidEncoding: "规则源不是有效的 UTF-8 文本。"
        }
    }
}

public enum RuleSourceFetchResult: Sendable {
    case notModified(checkedAt: Date)
    case modified(
        content: String,
        etag: String?,
        lastModified: String?,
        contentHash: String,
        checkedAt: Date
    )
}

public protocol RuleSourceFetching: Sendable {
    func fetch(
        source: RuleSource,
        timeoutSeconds: Int,
        maximumSizeMB: Int
    ) async throws -> RuleSourceFetchResult
}

public struct URLSessionRuleSourceFetcher: RuleSourceFetching, Sendable {
    public init() {}

    public func fetch(
        source: RuleSource,
        timeoutSeconds: Int,
        maximumSizeMB: Int
    ) async throws -> RuleSourceFetchResult {
        if let embeddedContent = source.embeddedContent {
            let data = Data(embeddedContent.utf8)
            let limit = max(1, maximumSizeMB) * 1_024 * 1_024
            guard data.count <= limit else {
                throw RuleSourceFetchError.sourceTooLarge(maximumSizeMB)
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return .modified(
                content: embeddedContent,
                etag: nil,
                lastModified: nil,
                contentHash: digest,
                checkedAt: .now
            )
        }

        let trimmed = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host != nil else {
            throw RuleSourceFetchError.invalidURL
        }
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else {
            throw RuleSourceFetchError.unsupportedScheme
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(max(5, timeoutSeconds))
        request.setValue("text/plain, text/yaml, application/yaml, */*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("SurgeShallow/1.5 (macOS)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = source.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = source.lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = TimeInterval(max(5, timeoutSeconds))
        configuration.timeoutIntervalForResource = TimeInterval(max(10, timeoutSeconds * 2))
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RuleSourceFetchError.invalidResponse
        }
        if http.statusCode == 304 {
            return .notModified(checkedAt: .now)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw RuleSourceFetchError.httpStatus(http.statusCode)
        }
        let limit = max(1, maximumSizeMB) * 1_024 * 1_024
        guard data.count <= limit else {
            throw RuleSourceFetchError.sourceTooLarge(maximumSizeMB)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw RuleSourceFetchError.invalidEncoding
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .modified(
            content: content,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            contentHash: digest,
            checkedAt: .now
        )
    }
}
