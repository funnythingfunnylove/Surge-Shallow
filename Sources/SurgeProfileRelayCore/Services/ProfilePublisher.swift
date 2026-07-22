import Foundation

public struct ProfilePublisher: Sendable {
    public init() {}

    @discardableResult
    public func publish(content: String, target: TargetProfile, directory: URL) throws -> URL {
        let fileName = TargetProfile.sanitizedFileName(target.outputFileName, platform: target.platform)
        return try publish(content: content, fileName: fileName, directory: directory)
    }

    @discardableResult
    public func publish(content: String, sharedProfile: SharedProfile, directory: URL) throws -> URL {
        try publish(
            content: content,
            fileName: SharedProfile.sanitizedFileName(sharedProfile.outputFileName),
            directory: directory
        )
    }

    public func validateDestination(for target: TargetProfile, directory: URL) throws {
        let name = TargetProfile.sanitizedFileName(target.outputFileName, platform: target.platform)
        try validateDestination(fileName: name, directory: directory)
    }

    public func validateDestination(for sharedProfile: SharedProfile, directory: URL) throws {
        try validateDestination(
            fileName: SharedProfile.sanitizedFileName(sharedProfile.outputFileName),
            directory: directory
        )
    }

    private func publish(content: String, fileName: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: fileName)
        let data = Data(content.utf8)
        guard Self.isManaged(data) else {
            throw RelayPersistenceError.unsafeDestination(
                "拒绝发布缺少 Surge Shallow 所有权标记的内容。"
            )
        }

        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: destination) ?? []
        for version in conflicts {
            let conflictData = try Data(contentsOf: version.url)
            guard Self.isManaged(conflictData) else {
                throw RelayPersistenceError.unsafeDestination(
                    "\(fileName) 存在不属于 Surge Shallow 的 iCloud 冲突版本，已停止写入。"
                )
            }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            guard Self.isManaged(existing) else {
                throw RelayPersistenceError.unsafeDestination(
                    "目标文件 \(fileName) 已存在且不是本应用生成，已停止覆盖。请更换输出文件名。"
                )
            }
            if existing == data, conflicts.isEmpty { return destination }
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeResult: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) {
            coordinatedURL in
            writeResult = Result {
                try data.write(to: coordinatedURL, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let writeResult else {
            throw RelayPersistenceError.coordinationFailed(fileName)
        }
        try writeResult.get()
        for version in conflicts { version.isResolved = true }
        if !conflicts.isEmpty { try NSFileVersion.removeOtherVersionsOfItem(at: destination) }
        return destination
    }

    private func validateDestination(fileName: String, directory: URL) throws {
        let destination = directory.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        let existing = try Data(contentsOf: destination)
        guard Self.isManaged(existing) else {
            throw RelayPersistenceError.unsafeDestination(
                "目标文件 \(fileName) 已存在且不是本应用生成，已停止覆盖。请更换输出文件名。"
            )
        }
    }

    private static func isManaged(_ data: Data) -> Bool {
        guard let content = String(data: data, encoding: .utf8) else { return false }
        return content.contains(ProfileAssembler.ownershipMarker)
    }
}
