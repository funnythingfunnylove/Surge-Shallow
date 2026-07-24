import Foundation

public struct RelaySettings: Codable, Hashable, Sendable {
    public var outputDirectory: String
    public var automaticallyRefresh: Bool
    public var refreshOnLaunch: Bool
    public var refreshIntervalMinutes: Int
    public var validateWithSurgeCLI: Bool
    public var launchAtLogin: Bool
    public var requestTimeoutSeconds: Int
    public var maximumSourceSizeMB: Int

    public init(
        outputDirectory: String = RelayPaths.defaultSurgeICloudDirectory.path,
        automaticallyRefresh: Bool = true,
        refreshOnLaunch: Bool = true,
        refreshIntervalMinutes: Int = 60,
        validateWithSurgeCLI: Bool = true,
        launchAtLogin: Bool = false,
        requestTimeoutSeconds: Int = 30,
        maximumSourceSizeMB: Int = 10
    ) {
        self.outputDirectory = outputDirectory
        self.automaticallyRefresh = automaticallyRefresh
        self.refreshOnLaunch = refreshOnLaunch
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.validateWithSurgeCLI = validateWithSurgeCLI
        self.launchAtLogin = launchAtLogin
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.maximumSourceSizeMB = maximumSourceSizeMB
    }
}

public struct UpdateRecord: Identifiable, Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case success
        case warning
        case failure
    }

    public var id: UUID
    public var date: Date
    public var outcome: Outcome
    public var title: String
    public var details: String
    public var ruleCount: Int
    public var duplicateCount: Int

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        outcome: Outcome,
        title: String,
        details: String,
        ruleCount: Int = 0,
        duplicateCount: Int = 0
    ) {
        self.id = id
        self.date = date
        self.outcome = outcome
        self.title = title
        self.details = details
        self.ruleCount = ruleCount
        self.duplicateCount = duplicateCount
    }
}

public struct RelayDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 7

    public var schemaVersion: Int
    public var sources: [RuleSource]
    public var sharedProfile: SharedProfile
    public var targets: [TargetProfile]
    public var settings: RelaySettings
    public var history: [UpdateRecord]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sources: [RuleSource] = [],
        sharedProfile: SharedProfile = .defaults,
        targets: [TargetProfile] = RelayPlatform.allCases.map(TargetProfile.defaults),
        settings: RelaySettings = RelaySettings(),
        history: [UpdateRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.sources = sources
        self.sharedProfile = sharedProfile
        self.targets = targets
        self.settings = settings
        self.history = history
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sources
        case sharedProfile
        case targets
        case settings
        case history
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sources = try container.decodeIfPresent([RuleSource].self, forKey: .sources) ?? []
        targets = try container.decodeIfPresent([TargetProfile].self, forKey: .targets)
            ?? RelayPlatform.allCases.map(TargetProfile.defaults)
        settings = try container.decodeIfPresent(RelaySettings.self, forKey: .settings) ?? RelaySettings()
        history = try container.decodeIfPresent([UpdateRecord].self, forKey: .history) ?? []
        if let decodedShared = try container.decodeIfPresent(SharedProfile.self, forKey: .sharedProfile) {
            sharedProfile = decodedShared
        } else {
            sharedProfile = SharedProfile.migratingLegacyTargets(&targets)
        }
        schemaVersion = max(decodedVersion, Self.currentSchemaVersion)
    }

    public mutating func appendHistory(_ record: UpdateRecord) {
        history.insert(record, at: 0)
        if history.count > 200 {
            history.removeLast(history.count - 200)
        }
    }
}

public enum RelayPaths {
    public static var defaultSurgeICloudDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/iCloud~com~nssurge~inc/Documents", directoryHint: .isDirectory)
    }

    public static var fallbackICloudDriveDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
            .appending(path: "Surge Profile Relay", directoryHint: .isDirectory)
    }

    public static var localApplicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Surge Profile Relay", directoryHint: .isDirectory)
    }
}
