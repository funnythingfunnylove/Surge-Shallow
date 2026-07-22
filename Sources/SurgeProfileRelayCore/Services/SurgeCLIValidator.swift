import Foundation

public struct SurgeValidationResult: Sendable {
    public var isAvailable: Bool
    public var isValid: Bool
    public var message: String

    public init(isAvailable: Bool, isValid: Bool, message: String) {
        self.isAvailable = isAvailable
        self.isValid = isValid
        self.message = message
    }
}

public enum SurgeCLIValidator {
    public static var executableURL: URL? {
        let candidates = [
            "/Applications/Surge.app/Contents/Applications/surge-cli",
            "/usr/local/bin/surge-cli",
            "/opt/homebrew/bin/surge-cli"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(filePath: $0) }
    }

    public static func validate(profileAt url: URL) async -> SurgeValidationResult {
        guard let executableURL else {
            return SurgeValidationResult(
                isAvailable: false,
                isValid: true,
                message: "未安装 Surge CLI，已仅执行内置结构检查。"
            )
        }
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executableURL
            process.arguments = ["--check", url.path]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let valid = process.terminationStatus == 0
                let message = output.isEmpty
                    ? (valid ? "Surge CLI 校验通过。" : "Surge CLI 校验失败。")
                    : output
                return SurgeValidationResult(isAvailable: true, isValid: valid, message: message)
            } catch {
                return SurgeValidationResult(
                    isAvailable: true,
                    isValid: false,
                    message: "无法运行 Surge CLI：\(error.localizedDescription)"
                )
            }
        }.value
    }
}
