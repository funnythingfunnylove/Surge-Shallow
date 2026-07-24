import Foundation

public enum RelayPersistenceError: LocalizedError, Sendable {
    case iCloudConflict(String)
    case corruptConfiguration(String)
    case unsafeDestination(String)
    case coordinationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .iCloudConflict(let file): "iCloud 中存在尚未解决的配置冲突：\(file)。请先在 Finder 中保留正确版本。"
        case .corruptConfiguration(let detail): "无法读取管理配置：\(detail)"
        case .unsafeDestination(let detail): detail
        case .coordinationFailed(let file): "iCloud 没有完成对 \(file) 的文件协调。"
        }
    }
}

public struct RelayPersistence: Sendable {
    public static let configurationFolderName = "Surge Profile Relay"
    public static let configurationFileName = "relay.json"

    public let outputDirectory: URL
    public let applicationSupportDirectory: URL

    private let maximumConflictChecks: Int
    private let conflictRetryDelay: TimeInterval
    private let unresolvedConflictCheck: @Sendable (URL) -> Bool
    private let conflictRetryWait: @Sendable (TimeInterval) -> Void

    public init(
        outputDirectory: URL = Self.selectedOutputDirectory,
        applicationSupportDirectory: URL = RelayPaths.localApplicationSupportDirectory
    ) {
        self.init(
            outputDirectory: outputDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            maximumConflictChecks: 21,
            conflictRetryDelay: 0.15,
            unresolvedConflictCheck: { url in
                !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
            },
            conflictRetryWait: { delay in
                Thread.sleep(forTimeInterval: delay)
            }
        )
    }

    init(
        outputDirectory: URL,
        applicationSupportDirectory: URL,
        maximumConflictChecks: Int,
        conflictRetryDelay: TimeInterval,
        unresolvedConflictCheck: @escaping @Sendable (URL) -> Bool,
        conflictRetryWait: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.outputDirectory = outputDirectory.standardizedFileURL
        self.applicationSupportDirectory = applicationSupportDirectory.standardizedFileURL
        self.maximumConflictChecks = maximumConflictChecks
        self.conflictRetryDelay = conflictRetryDelay
        self.unresolvedConflictCheck = unresolvedConflictCheck
        self.conflictRetryWait = conflictRetryWait
    }

    public static var selectedOutputDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "SurgeProfileRelay.outputDirectory.v1"),
           !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return RelayPaths.defaultSurgeICloudDirectory
    }

    public static func rememberOutputDirectory(_ url: URL) {
        UserDefaults.standard.set(
            url.standardizedFileURL.path,
            forKey: "SurgeProfileRelay.outputDirectory.v1"
        )
    }

    public var configurationDirectory: URL {
        outputDirectory.appending(path: Self.configurationFolderName, directoryHint: .isDirectory)
    }

    public var configurationURL: URL {
        configurationDirectory.appending(path: Self.configurationFileName)
    }

    public var backupURL: URL {
        configurationDirectory.appending(path: "relay.json.bak")
    }

    public var configurationExists: Bool {
        FileManager.default.fileExists(atPath: configurationURL.path)
    }

    public var cacheDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Cache", directoryHint: .isDirectory)
    }

    public var previewDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Preview", directoryHint: .isDirectory)
    }

    public func loadDocument() throws -> RelayDocument {
        try prepareDirectories()
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            var document = RelayDocument()
            document.settings.outputDirectory = outputDirectory.path
            return document
        }
        guard !hasPersistentConflict(at: configurationURL) else {
            throw RelayPersistenceError.iCloudConflict(configurationURL.lastPathComponent)
        }
        do {
            return try Self.decoder.decode(RelayDocument.self, from: Data(contentsOf: configurationURL))
        } catch {
            if let backupData = try? Data(contentsOf: backupURL),
               let backup = try? Self.decoder.decode(RelayDocument.self, from: backupData) {
                try? coordinatedWrite(backupData, to: configurationURL)
                return backup
            }
            throw RelayPersistenceError.corruptConfiguration(error.localizedDescription)
        }
    }

    public func saveDocument(_ document: RelayDocument) throws {
        try prepareDirectories()
        let data = try Self.encoder.encode(document)
        guard !hasPersistentConflict(at: configurationURL) else {
            throw RelayPersistenceError.iCloudConflict(configurationURL.lastPathComponent)
        }
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            let existing = try Data(contentsOf: configurationURL)
            guard existing != data else { return }
            try existing.write(to: backupURL, options: .atomic)
        }
        try coordinatedWrite(data, to: configurationURL)
    }

    public func cachedContent(for sourceID: UUID) throws -> String? {
        let url = cacheURL(for: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw RelayPersistenceError.corruptConfiguration("缓存 \(url.lastPathComponent) 不是 UTF-8 文本。")
        }
        return content
    }

    public func saveCachedContent(_ content: String, for sourceID: UUID) throws {
        try prepareDirectories()
        try Data(content.utf8).write(to: cacheURL(for: sourceID), options: .atomic)
    }

    public func removeCache(for sourceID: UUID) throws {
        let url = cacheURL(for: sourceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func previewURL(for platform: RelayPlatform) -> URL {
        previewDirectory
            .appending(path: "Surge-Profile-Relay-\(platform.rawValue).conf")
    }

    public func writePreview(_ content: String, for platform: RelayPlatform) throws -> URL {
        let url = previewURL(for: platform)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }

    public func sharedPreviewURL(fileName: String) -> URL {
        previewDirectory
            .appending(path: SharedProfile.sanitizedFileName(fileName))
    }

    public func writeSharedPreview(_ content: String, fileName: String) throws -> URL {
        let url = sharedPreviewURL(fileName: fileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }

    public func detachedPreviewURL(fileName: String) -> URL {
        previewDirectory.appending(path: fileName)
    }

    public func writeDetachedPreview(_ content: String, fileName: String) throws -> URL {
        let url = detachedPreviewURL(fileName: fileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url, options: .atomic)
        return url
    }

    private func cacheURL(for sourceID: UUID) -> URL {
        cacheDirectory.appending(path: "\(sourceID.uuidString.lowercased()).rules")
    }

    private func hasPersistentConflict(at url: URL) -> Bool {
        let checkCount = max(1, maximumConflictChecks)
        for index in 0..<checkCount {
            if !unresolvedConflictCheck(url) { return false }
            if index + 1 < checkCount {
                conflictRetryWait(conflictRetryDelay)
            }
        }
        return true
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeResult: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
            coordinatedURL in
            writeResult = Result {
                try data.write(to: coordinatedURL, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let writeResult else {
            throw RelayPersistenceError.coordinationFailed(url.lastPathComponent)
        }
        try writeResult.get()
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
