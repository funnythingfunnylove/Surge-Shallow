import Foundation

public struct TargetProfile: Identifiable, Codable, Hashable, Sendable {
    public var platform: RelayPlatform
    public var isEnabled: Bool
    public var outputFileName: String
    public var finalPolicy: String
    public var platformDifferences: [ProfileDifferenceItem]
    public var lastGeneratedAt: Date?
    public var lastRuleCount: Int
    public var lastValidationMessage: String?

    public var id: RelayPlatform { platform }

    public var platformProfile: String {
        get { ProfileDifferenceCodec.render(platformDifferences) }
        set { platformDifferences = ProfileDifferenceCodec.parse(newValue) }
    }

    public init(
        platform: RelayPlatform,
        isEnabled: Bool = true,
        outputFileName: String,
        finalPolicy: String = "DIRECT",
        platformProfile: String = "",
        platformDifferences: [ProfileDifferenceItem]? = nil,
        lastGeneratedAt: Date? = nil,
        lastRuleCount: Int = 0,
        lastValidationMessage: String? = nil
    ) {
        self.platform = platform
        self.isEnabled = isEnabled
        self.outputFileName = Self.sanitizedFileName(outputFileName, platform: platform)
        self.finalPolicy = finalPolicy
        self.platformDifferences = platformDifferences ?? ProfileDifferenceCodec.parse(platformProfile)
        self.lastGeneratedAt = lastGeneratedAt
        self.lastRuleCount = lastRuleCount
        self.lastValidationMessage = lastValidationMessage
    }

    public static func defaults(for platform: RelayPlatform) -> TargetProfile {
        return TargetProfile(
            platform: platform,
            outputFileName: "Surge-Profile-Relay-\(platform.rawValue).conf"
        )
    }

    public static func sanitizedFileName(_ value: String, platform: RelayPlatform) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = value.components(separatedBy: invalid).filter { !$0.isEmpty }
        let base = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Surge-Profile-Relay-\(platform.rawValue)"
        let name = base.isEmpty ? fallback : base
        return name.lowercased().hasSuffix(".conf") ? name : "\(name).conf"
    }

    private enum CodingKeys: String, CodingKey {
        case platform
        case isEnabled
        case outputFileName
        case finalPolicy
        case platformDifferences
        case platformProfile
        case baseProfile
        case lastGeneratedAt
        case lastRuleCount
        case lastValidationMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(RelayPlatform.self, forKey: .platform)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        outputFileName = try container.decode(String.self, forKey: .outputFileName)
        finalPolicy = try container.decode(String.self, forKey: .finalPolicy)
        if let decodedDifferences = try container.decodeIfPresent(
            [ProfileDifferenceItem].self,
            forKey: .platformDifferences
        ) {
            platformDifferences = decodedDifferences.filter { !$0.isRuleSection }
        } else {
            let legacyProfile = try container.decodeIfPresent(String.self, forKey: .platformProfile)
                ?? container.decode(String.self, forKey: .baseProfile)
            platformDifferences = ProfileDifferenceCodec.parse(legacyProfile)
        }
        lastGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .lastGeneratedAt)
        lastRuleCount = try container.decodeIfPresent(Int.self, forKey: .lastRuleCount) ?? 0
        lastValidationMessage = try container.decodeIfPresent(String.self, forKey: .lastValidationMessage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(platform, forKey: .platform)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(outputFileName, forKey: .outputFileName)
        try container.encode(finalPolicy, forKey: .finalPolicy)
        try container.encode(platformDifferences.filter { !$0.isRuleSection }, forKey: .platformDifferences)
        try container.encodeIfPresent(lastGeneratedAt, forKey: .lastGeneratedAt)
        try container.encode(lastRuleCount, forKey: .lastRuleCount)
        try container.encodeIfPresent(lastValidationMessage, forKey: .lastValidationMessage)
    }
}
