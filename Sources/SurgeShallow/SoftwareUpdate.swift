import CryptoKit
import Foundation

struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        let versionAndBuild = normalized.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let versionAndPrerelease = versionAndBuild[0].split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let core = versionAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(core.count),
              core.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        let numbers = core.compactMap { Int($0) }
        guard numbers.count == core.count else { return nil }
        major = numbers[0]
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0

        if versionAndPrerelease.count == 2 {
            let identifiers = versionAndPrerelease[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty,
                  identifiers.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
            prerelease = identifiers.map(String.init)
        } else {
            prerelease = []
        }
    }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : "\(core)-\(prerelease.joined(separator: "."))"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore {
            return lhsCore.lexicographicallyPrecedes(rhsCore)
        }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (.some(leftNumber), .some(rightNumber)):
                return leftNumber < rightNumber
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
struct SoftwareUpdateAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let sha256: String
    let size: Int64
}

struct SoftwareRelease: Identifiable, Equatable, Sendable {
    var id: String { tagName }

    let tagName: String
    let version: SemanticVersion
    let title: String
    let notes: String
    let pageURL: URL
    let publishedAt: Date?
    let asset: SoftwareUpdateAsset
}

enum SoftwareUpdateError: LocalizedError, Equatable {
    case invalidReleaseResponse
    case githubRequestFailed(Int)
    case releaseResponseTooLarge
    case checksumMismatch
    case invalidApplicationBundle
    case unexpectedApplicationIdentifier
    case unexpectedApplicationVersion
    case unsupportedReleaseTag(String)
    case releaseIsNotPublic
    case missingVerifiedMacOSAsset
    case updateAlreadyInProgress
    case downloadFailed(Int)
    case downloadSizeMismatch
    case archiveExtractionFailed
    case invalidCodeSignature
    case applicationNotInstalled
    case installationCouldNotStart

    var errorDescription: String? {
        switch self {
        case .invalidReleaseResponse:
            "GitHub 返回了无法识别的 Release 信息。"
        case .githubRequestFailed(let statusCode):
            "GitHub 更新检查失败（HTTP \(statusCode)）。"
        case .releaseResponseTooLarge:
            "GitHub Release 信息超过允许大小。"
        case .checksumMismatch:
            "更新包校验失败，下载内容与 GitHub Release 的 SHA-256 不一致。"
        case .invalidApplicationBundle:
            "更新包中没有有效的 Surge Shallow 应用。"
        case .unexpectedApplicationIdentifier:
            "更新包中的应用标识与 Surge Shallow 不一致。"
        case .unexpectedApplicationVersion:
            "更新包中的应用版本与 GitHub Release 标签不一致。"
        case .unsupportedReleaseTag(let tag):
            "Release 标签 \(tag) 不是有效版本号。"
        case .releaseIsNotPublic:
            "GitHub 最新 Release 尚未正式发布。"
        case .missingVerifiedMacOSAsset:
            "Release 中没有带 SHA-256 校验值的 macOS 更新包。"
        case .updateAlreadyInProgress:
            "软件更新正在进行中。"
        case .downloadFailed(let statusCode):
            "更新包下载失败（HTTP \(statusCode)）。"
        case .downloadSizeMismatch:
            "更新包大小与 GitHub Release 记录不一致。"
        case .archiveExtractionFailed:
            "更新包解压失败。"
        case .invalidCodeSignature:
            "更新包中的应用签名校验失败。"
        case .applicationNotInstalled:
            "请先将 Surge Shallow.app 移到本机磁盘后再使用一键更新。"
        case .installationCouldNotStart:
            "更新安装器没有成功启动。"
        }
    }
}

enum SoftwareUpdatePackageVerifier {
    static func verifySHA256(of fileURL: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw SoftwareUpdateError.checksumMismatch
        }
    }

    static func validateApplication(
        at applicationURL: URL,
        expectedVersion: SemanticVersion,
        expectedBundleIdentifier: String
    ) throws {
        let plistURL = applicationURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "Info.plist")
        guard applicationURL.pathExtension == "app",
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any],
              let bundleIdentifier = values["CFBundleIdentifier"] as? String,
              let versionString = values["CFBundleShortVersionString"] as? String,
              let applicationVersion = SemanticVersion(versionString) else {
            throw SoftwareUpdateError.invalidApplicationBundle
        }
        guard bundleIdentifier == expectedBundleIdentifier else {
            throw SoftwareUpdateError.unexpectedApplicationIdentifier
        }
        guard applicationVersion == expectedVersion else {
            throw SoftwareUpdateError.unexpectedApplicationVersion
        }
    }
}

enum SoftwareUpdateCheckResult: Equatable, Sendable {
    case upToDate(SoftwareRelease)
    case updateAvailable(SoftwareRelease)
}

enum SoftwareUpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate(Date)
    case available
    case downloading
    case verifying
    case installing
    case restarting
    case failed(String)

    var presentation: SoftwareUpdatePhasePresentation {
        switch self {
        case .idle:
            .init(text: "尚未检查软件更新", symbol: "clock", tone: .neutral, isBusy: false)
        case .checking:
            .init(
                text: "正在检查 GitHub Release…",
                symbol: "arrow.trianglehead.2.clockwise.rotate.90",
                tone: .accent,
                isBusy: true
            )
        case .upToDate:
            .init(text: "当前已是最新版本", symbol: "checkmark.circle.fill", tone: .success, isBusy: false)
        case .available:
            .init(text: "发现新版本", symbol: "arrow.down.circle.fill", tone: .accent, isBusy: false)
        case .downloading:
            .init(text: "正在下载更新包…", symbol: "arrow.down.circle", tone: .accent, isBusy: true)
        case .verifying:
            .init(text: "正在校验并准备更新…", symbol: "checkmark.shield", tone: .accent, isBusy: true)
        case .installing:
            .init(text: "正在准备替换应用…", symbol: "shippingbox", tone: .accent, isBusy: true)
        case .restarting:
            .init(text: "即将重新启动…", symbol: "arrow.clockwise.circle", tone: .accent, isBusy: true)
        case .failed(let message):
            .init(text: message, symbol: "exclamationmark.triangle.fill", tone: .danger, isBusy: false)
        }
    }

    var isBusy: Bool { presentation.isBusy }
    var statusText: String { presentation.text }
}

enum SoftwareUpdateStatusTone: Sendable {
    case neutral
    case accent
    case success
    case danger
}

struct SoftwareUpdatePhasePresentation: Sendable {
    let text: String
    let symbol: String
    let tone: SoftwareUpdateStatusTone
    let isBusy: Bool
}

enum SoftwareUpdateSchedule {
    static let automaticCheckInterval: TimeInterval = 6 * 60 * 60

    static func shouldCheck(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= automaticCheckInterval
    }
}

struct GitHubReleaseDecoder: Sendable {
    func decode(_ data: Data) throws -> SoftwareRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: GitHubReleasePayload
        do {
            payload = try decoder.decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw SoftwareUpdateError.invalidReleaseResponse
        }

        guard !payload.draft, !payload.prerelease else {
            throw SoftwareUpdateError.releaseIsNotPublic
        }
        guard let version = SemanticVersion(payload.tagName) else {
            throw SoftwareUpdateError.unsupportedReleaseTag(payload.tagName)
        }
        guard let pageURL = validatedGitHubURL(payload.pageURL) else {
            throw SoftwareUpdateError.invalidReleaseResponse
        }

        guard let asset = payload.assets.lazy.compactMap({ asset in
            verifiedAsset(from: asset)
        }).first else {
            throw SoftwareUpdateError.missingVerifiedMacOSAsset
        }

        let title = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = payload.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SoftwareRelease(
            tagName: payload.tagName,
            version: version,
            title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Surge Shallow \(version)",
            notes: notes.flatMap { $0.isEmpty ? nil : $0 } ?? "此版本未提供更新日志。",
            pageURL: pageURL,
            publishedAt: payload.publishedAt,
            asset: asset
        )
    }

    private func verifiedAsset(from payload: GitHubReleasePayload.Asset) -> SoftwareUpdateAsset? {
        guard payload.state == "uploaded",
              payload.size > 0,
              payload.name.hasPrefix("Surge-Shallow-"),
              payload.name.hasSuffix("-macOS.zip"),
              payload.contentType == "application/zip" || payload.contentType == "application/x-zip-compressed",
              let downloadURL = validatedGitHubURL(payload.downloadURL),
              let digest = payload.digest?.lowercased(),
              digest.hasPrefix("sha256:") else {
            return nil
        }

        let sha256 = String(digest.dropFirst("sha256:".count))
        guard sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return SoftwareUpdateAsset(
            name: payload.name,
            downloadURL: downloadURL,
            sha256: sha256,
            size: payload.size
        )
    }

    private func validatedGitHubURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme == "https",
              url.host?.lowercased() == "github.com" else {
            return nil
        }
        return url
    }
}

private struct GitHubReleasePayload: Decodable {
    struct Asset: Decodable {
        let name: String
        let downloadURL: String
        let contentType: String
        let state: String
        let size: Int64
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case contentType = "content_type"
            case state
            case size
            case digest
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let pageURL: String
    let publishedAt: Date?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case pageURL = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
        case assets
    }
}
