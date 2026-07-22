import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubRepositoryLocation: Hashable, Sendable {
    public var owner: String
    public var repository: String
    public var reference: String?
    public var path: String?
    public var selectsSingleFile: Bool

    public init(
        owner: String,
        repository: String,
        reference: String? = nil,
        path: String? = nil,
        selectsSingleFile: Bool = false
    ) {
        self.owner = owner
        self.repository = repository
        self.reference = reference
        self.path = path
        self.selectsSingleFile = selectsSingleFile
    }
}

public struct GitHubRuleFile: Identifiable, Hashable, Sendable {
    public var path: String
    public var downloadURL: String
    public var size: Int?
    public var suggestedFormat: RuleSourceFormat

    public var id: String { path }
    public var fileName: String { URL(filePath: path).lastPathComponent }
    public var sourceName: String {
        let name = URL(filePath: fileName).deletingPathExtension().lastPathComponent
        return name.isEmpty ? fileName : name
    }

    public init(
        path: String,
        downloadURL: String,
        size: Int? = nil,
        suggestedFormat: RuleSourceFormat = .automatic
    ) {
        self.path = path
        self.downloadURL = downloadURL
        self.size = size
        self.suggestedFormat = suggestedFormat
    }
}

public struct GitHubRuleRepositorySnapshot: Hashable, Sendable {
    public var owner: String
    public var repository: String
    public var reference: String
    public var files: [GitHubRuleFile]

    public init(owner: String, repository: String, reference: String, files: [GitHubRuleFile]) {
        self.owner = owner
        self.repository = repository
        self.reference = reference
        self.files = files
    }
}

public enum GitHubRuleRepositoryError: LocalizedError, Sendable {
    case invalidRepositoryURL
    case invalidResponse
    case httpStatus(Int, String)
    case rateLimited
    case repositoryTreeTruncated
    case noRuleFiles

    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            "请输入 GitHub 仓库、tree 目录或 blob 文件 URL。"
        case .invalidResponse:
            "GitHub 没有返回有效响应。"
        case .httpStatus(let status, let message):
            "GitHub 返回 HTTP \(status)：\(message)"
        case .rateLimited:
            "GitHub 未登录 API 额度已用完，请稍后重试。"
        case .repositoryTreeTruncated:
            "仓库文件树过大，GitHub 返回了截断结果；请粘贴更具体的 tree 目录 URL。"
        case .noRuleFiles:
            "仓库或所选目录中没有找到支持的规则文件。"
        }
    }
}

public enum GitHubRepositoryURLParser {
    public static func parse(_ value: String) throws -> GitHubRepositoryLocation {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            throw GitHubRuleRepositoryError.invalidRepositoryURL
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw GitHubRuleRepositoryError.invalidRepositoryURL
        }
        let owner = parts[0]
        var repository = parts[1]
        if repository.lowercased().hasSuffix(".git") {
            repository.removeLast(4)
        }
        guard isSafeComponent(owner), isSafeComponent(repository), !repository.isEmpty else {
            throw GitHubRuleRepositoryError.invalidRepositoryURL
        }

        if parts.count == 2 {
            return GitHubRepositoryLocation(owner: owner, repository: repository)
        }
        guard parts.count >= 4, parts[2] == "tree" || parts[2] == "blob" else {
            throw GitHubRuleRepositoryError.invalidRepositoryURL
        }
        let path = parts.dropFirst(4).joined(separator: "/")
        return GitHubRepositoryLocation(
            owner: owner,
            repository: repository,
            reference: parts[3],
            path: path.isEmpty ? nil : path,
            selectsSingleFile: parts[2] == "blob"
        )
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }
    }
}

public protocol GitHubRuleRepositoryDiscovering: Sendable {
    func discover(repositoryURL: String) async throws -> GitHubRuleRepositorySnapshot
}

public struct GitHubRuleRepositoryClient: GitHubRuleRepositoryDiscovering, Sendable {
    public init() {}

    public func discover(repositoryURL: String) async throws -> GitHubRuleRepositorySnapshot {
        let location = try GitHubRepositoryURLParser.parse(repositoryURL)
        let reference: String
        if let selectedReference = location.reference {
            reference = selectedReference
        } else {
            reference = try await fetchDefaultBranch(for: location)
        }
        let response: TreeResponse = try await request(
            pathSegments: [
                "repos", location.owner, location.repository, "git", "trees", reference
            ],
            queryItems: [URLQueryItem(name: "recursive", value: "1")]
        )
        guard !response.truncated else {
            throw GitHubRuleRepositoryError.repositoryTreeTruncated
        }
        let files = Self.ruleFiles(
            from: response.tree,
            location: location,
            reference: reference
        )
        guard !files.isEmpty else { throw GitHubRuleRepositoryError.noRuleFiles }
        return GitHubRuleRepositorySnapshot(
            owner: location.owner,
            repository: location.repository,
            reference: reference,
            files: files
        )
    }

    static func ruleFiles(
        from entries: [TreeEntry],
        location: GitHubRepositoryLocation,
        reference: String
    ) -> [GitHubRuleFile] {
        entries.compactMap { entry -> GitHubRuleFile? in
            guard entry.type == "blob", isIncluded(entry.path, for: location) else { return nil }
            guard let format = suggestedFormat(for: entry.path) else { return nil }
            guard let downloadURL = rawURL(
                owner: location.owner,
                repository: location.repository,
                reference: reference,
                path: entry.path
            ) else { return nil }
            return GitHubRuleFile(
                path: entry.path,
                downloadURL: downloadURL.absoluteString,
                size: entry.size,
                suggestedFormat: format
            )
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func fetchDefaultBranch(for location: GitHubRepositoryLocation) async throws -> String {
        let repository: RepositoryResponse = try await request(
            pathSegments: ["repos", location.owner, location.repository]
        )
        return repository.defaultBranch
    }

    private func request<Response: Decodable>(
        pathSegments: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/" + pathSegments.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw GitHubRuleRepositoryError.invalidRepositoryURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SurgeShallow/1.5 (macOS)", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubRuleRepositoryError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 403,
               http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubRuleRepositoryError.rateLimited
            }
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw GitHubRuleRepositoryError.httpStatus(http.statusCode, detail)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GitHubRuleRepositoryError.invalidResponse
        }
    }

    private static func isIncluded(_ path: String, for location: GitHubRepositoryLocation) -> Bool {
        guard let selectedPath = location.path, !selectedPath.isEmpty else { return true }
        if location.selectsSingleFile { return path == selectedPath }
        return path == selectedPath || path.hasPrefix(selectedPath + "/")
    }

    private static func suggestedFormat(for path: String) -> RuleSourceFormat? {
        let fileName = URL(filePath: path).lastPathComponent.lowercased()
        let excludedNames = ["readme", "license", "changelog", "contributing"]
        if excludedNames.contains(where: { fileName.hasPrefix($0) }) { return nil }
        return switch URL(filePath: fileName).pathExtension.lowercased() {
        case "yaml", "yml": .clashPayload
        case "conf": .surgeProfile
        case "list", "rule", "rules", "ruleset", "txt": .automatic
        default: nil
        }
    }

    private static func rawURL(
        owner: String,
        repository: String,
        reference: String,
        path: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "raw.githubusercontent.com"
        components.path = "/" + ([owner, repository, reference] + path.split(separator: "/").map(String.init))
            .joined(separator: "/")
        return components.url
    }
}

struct RepositoryResponse: Decodable {
    var defaultBranch: String

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
    }
}

struct TreeResponse: Decodable {
    var tree: [TreeEntry]
    var truncated: Bool
}

struct TreeEntry: Decodable {
    var path: String
    var type: String
    var size: Int?
}

private struct ErrorResponse: Decodable {
    var message: String
}
