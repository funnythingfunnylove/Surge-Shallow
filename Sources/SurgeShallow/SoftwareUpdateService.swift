import Foundation
import Observation

actor GitHubSoftwareUpdateService {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/funnythingfunnylove/Surge-Shallow/releases/latest"
    )!

    private let session: URLSession
    private let decoder: GitHubReleaseDecoder

    init(session: URLSession = .shared, decoder: GitHubReleaseDecoder = GitHubReleaseDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    func check(installedVersion: SemanticVersion) async throws -> SoftwareUpdateCheckResult {
        var request = URLRequest(
            url: Self.latestReleaseURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Surge-Shallow/\(installedVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SoftwareUpdateError.invalidReleaseResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw SoftwareUpdateError.githubRequestFailed(httpResponse.statusCode)
        }
        guard data.count <= 1_048_576 else {
            throw SoftwareUpdateError.releaseResponseTooLarge
        }

        let release = try decoder.decode(data)
        return release.version > installedVersion ? .updateAvailable(release) : .upToDate(release)
    }
}

@MainActor
@Observable
final class SoftwareUpdateController {
    static let automaticChecksEnabledKey = "SurgeShallow.softwareUpdate.checksOnLaunch"
    static let lastCheckDateKey = "SurgeShallow.softwareUpdate.lastCheckDate"

    private(set) var phase: SoftwareUpdatePhase = .idle
    private(set) var latestRelease: SoftwareRelease?
    private(set) var lastCheckedAt: Date?
    var presentedRelease: SoftwareRelease?
    var automaticChecksEnabled: Bool {
        didSet {
            defaults.set(automaticChecksEnabled, forKey: Self.automaticChecksEnabledKey)
        }
    }

    let currentVersion: String
    let currentBuild: String
    let installedVersion: SemanticVersion

    private let service: GitHubSoftwareUpdateService
    private let installer: SoftwareUpdateInstaller
    private let defaults: UserDefaults

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        service: GitHubSoftwareUpdateService = GitHubSoftwareUpdateService(),
        installer: SoftwareUpdateInstaller = SoftwareUpdateInstaller()
    ) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        currentVersion = version ?? "0.0.0-development"
        installedVersion = SemanticVersion(currentVersion) ?? SemanticVersion("0.0.0-development")!
        currentBuild = build ?? "开发构建"
        self.defaults = defaults
        self.service = service
        self.installer = installer
        lastCheckedAt = defaults.object(forKey: Self.lastCheckDateKey) as? Date
        if defaults.object(forKey: Self.automaticChecksEnabledKey) == nil {
            automaticChecksEnabled = true
        } else {
            automaticChecksEnabled = defaults.bool(forKey: Self.automaticChecksEnabledKey)
        }
    }

    var isBusy: Bool { phase.isBusy }

    var shouldCheckAutomatically: Bool {
        automaticChecksEnabled && SoftwareUpdateSchedule.shouldCheck(lastCheck: lastCheckedAt)
    }

    var availableUpdate: SoftwareRelease? {
        guard let latestRelease,
              latestRelease.version > installedVersion else {
            return nil
        }
        return latestRelease
    }

    var statusText: String {
        if case .available = phase, let latestRelease {
            return "发现 Surge Shallow \(latestRelease.version)"
        }
        return phase.statusText
    }

    @discardableResult
    func checkForUpdates() async throws -> SoftwareUpdateCheckResult {
        guard !phase.isBusy else { throw SoftwareUpdateError.updateAlreadyInProgress }
        phase = .checking
        do {
            let result = try await service.check(installedVersion: installedVersion)
            let checkedAt = Date()
            lastCheckedAt = checkedAt
            defaults.set(checkedAt, forKey: Self.lastCheckDateKey)
            switch result {
            case .upToDate(let release):
                latestRelease = release
                phase = .upToDate(checkedAt)
            case .updateAvailable(let release):
                latestRelease = release
                presentedRelease = release
                phase = .available
            }
            return result
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }

    func dismissPresentedUpdate() {
        guard !phase.isBusy else { return }
        presentedRelease = nil
    }

    func presentForVerification(_ release: SoftwareRelease) {
        latestRelease = release
        presentedRelease = release
        phase = .available
    }

    func presentAvailableUpdate() {
        guard let release = availableUpdate, !phase.isBusy else { return }
        presentedRelease = release
        phase = .available
    }

    func install(
        _ release: SoftwareRelease,
        currentApplicationURL: URL,
        processIdentifier: Int32
    ) async throws {
        guard !phase.isBusy else { throw SoftwareUpdateError.updateAlreadyInProgress }
        phase = .downloading
        do {
            let prepared = try await installer.downloadAndPrepare(release) { [weak self] phase in
                await MainActor.run { self?.phase = phase }
            }
            phase = .installing
            try await installer.scheduleInstallation(
                prepared,
                currentApplicationURL: currentApplicationURL,
                processIdentifier: processIdentifier
            )
            phase = .restarting
        } catch {
            phase = .failed(error.localizedDescription)
            throw error
        }
    }
}
