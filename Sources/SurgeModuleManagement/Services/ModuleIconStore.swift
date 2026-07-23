import Foundation

actor ModuleIconStore {
    nonisolated static var directoryURL: URL {
        PersistenceStore.cacheDirectoryURL
            .appending(path: "Icons", directoryHint: .isDirectory)
    }

    nonisolated static func cachedURL(for moduleID: UUID) -> URL {
        directoryURL.appending(path: moduleID.uuidString.lowercased())
    }

    private nonisolated static func legacyCachedURL(for moduleID: UUID) -> URL {
        directoryURL.appending(path: moduleID.uuidString.lowercased() + ".image")
    }

    func cacheIcon(from url: URL, for moduleID: UUID, force: Bool = false) async throws {
        if !force, FileManager.default.fileExists(atPath: Self.cachedURL(for: moduleID).path) {
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
        request.setValue("SurgeRelay/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), !data.isEmpty, data.count <= 5 * 1024 * 1024 else {
            throw RelayError.httpFailure(status: status, message: "模块图标下载失败。")
        }
        try FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        try data.write(to: Self.cachedURL(for: moduleID), options: .atomic)
        try? FileManager.default.removeItem(at: Self.legacyCachedURL(for: moduleID))
    }

    func removeIcon(for moduleID: UUID) throws {
        let url = Self.cachedURL(for: moduleID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let legacyURL = Self.legacyCachedURL(for: moduleID)
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.removeItem(at: legacyURL)
        }
    }
}
