import Darwin
import Foundation
import XCTest

@testable import SurgeShallow

final class SoftwareUpdateInstallerShutdownTests: XCTestCase {
    func testInstallerTerminatesUnresponsiveOldApplicationBeforeReplacement() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let targetApplicationURL = fixtureRoot.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        let targetExecutableURL = targetApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        try fileManager.createDirectory(
            at: targetExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let termMarkerURL = fixtureRoot.appending(path: "received-term")
        try compileUnresponsiveApplication(
            at: targetExecutableURL,
            termMarkerURL: termMarkerURL
        )

        let oldApplication = Process()
        oldApplication.executableURL = targetExecutableURL
        oldApplication.arguments = ["--verification-mode"]
        oldApplication.standardOutput = FileHandle.nullDevice
        oldApplication.standardError = FileHandle.nullDevice
        try oldApplication.run()
        defer {
            if oldApplication.isRunning {
                _ = Darwin.kill(oldApplication.processIdentifier, SIGKILL)
                oldApplication.waitUntilExit()
            }
        }
        try waitUntilProcessCommandMatches(
            processIdentifier: oldApplication.processIdentifier,
            expectedCommand: targetExecutableURL.path
        )

        let workingDirectory = fixtureRoot.appending(
            path: "helper-work",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let helperURL = workingDirectory.appending(path: "install-update.sh")
        try Data(fastInstallationHelper.utf8).write(to: helperURL)

        let resultURL = fixtureRoot.appending(path: "result.txt")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            fixtureRoot.appending(path: "missing-staged.app").path,
            targetApplicationURL.resolvingSymlinksInPath().path,
            String(oldApplication.processIdentifier),
            workingDirectory.appending(path: "ready").path,
            resultURL.path,
            "2.2.0",
            fixtureRoot.appending(path: "confirmation").path
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        helper.waitUntilExit()

        let result = (try? String(contentsOf: resultURL, encoding: .utf8)) ?? "<missing>"
        XCTAssertEqual(helper.terminationStatus, 0, "helper result: \(result)")
        XCTAssertNotEqual(
            result,
            "failed\nshutdown-timeout\n",
            "The helper must escalate an unresponsive old process instead of abandoning the update."
        )
        let receivedSignals = (try? String(contentsOf: termMarkerURL, encoding: .utf8)) ?? ""
        XCTAssertEqual(
            receivedSignals,
            "TERM\n",
            "The unresponsive old process must receive SIGTERM before escalation."
        )
        XCTAssertFalse(
            oldApplication.isRunning,
            "A process that ignores SIGTERM must receive SIGKILL before replacement continues."
        )
    }

    func testInstallerRefusesReplacementWhileAnotherApplicationInstanceIsRunning() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let targetApplicationURL = fixtureRoot.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        let targetExecutableURL = targetApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        try fileManager.createDirectory(
            at: targetExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try compileUnresponsiveApplication(
            at: targetExecutableURL,
            termMarkerURL: fixtureRoot.appending(path: "received-term")
        )

        let firstInstance = Process()
        firstInstance.executableURL = targetExecutableURL
        firstInstance.standardOutput = FileHandle.nullDevice
        firstInstance.standardError = FileHandle.nullDevice
        try firstInstance.run()
        let secondInstance = Process()
        secondInstance.executableURL = targetExecutableURL
        secondInstance.standardOutput = FileHandle.nullDevice
        secondInstance.standardError = FileHandle.nullDevice
        try secondInstance.run()
        defer {
            for process in [firstInstance, secondInstance] where process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        try waitUntilProcessCommandMatches(
            processIdentifier: firstInstance.processIdentifier,
            expectedCommand: targetExecutableURL.path
        )
        try waitUntilProcessCommandMatches(
            processIdentifier: secondInstance.processIdentifier,
            expectedCommand: targetExecutableURL.path
        )

        let workingDirectory = fixtureRoot.appending(
            path: "helper-work",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let helperURL = workingDirectory.appending(path: "install-update.sh")
        try Data(shortenedInstallationHelper.utf8).write(to: helperURL)
        let resultURL = fixtureRoot.appending(path: "result.txt")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            fixtureRoot.appending(path: "missing-staged.app").path,
            targetApplicationURL.resolvingSymlinksInPath().path,
            String(firstInstance.processIdentifier),
            workingDirectory.appending(path: "ready").path,
            resultURL.path,
            "2.2.0",
            fixtureRoot.appending(path: "confirmation").path
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        helper.waitUntilExit()

        XCTAssertEqual(helper.terminationStatus, 11)
        XCTAssertEqual(
            try String(contentsOf: resultURL, encoding: .utf8),
            "failed\nmultiple-running-instances\n"
        )
        XCTAssertFalse(firstInstance.isRunning)
        XCTAssertTrue(secondInstance.isRunning)
        XCTAssertTrue(fileManager.fileExists(atPath: targetApplicationURL.path))
    }

    func testInstallerRecognizesSecondInstanceStartedThroughExecutableSymlink() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let targetApplicationURL = fixtureRoot.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        let targetExecutableURL = targetApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        try fileManager.createDirectory(
            at: targetExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try compileUnresponsiveApplication(
            at: targetExecutableURL,
            termMarkerURL: fixtureRoot.appending(path: "received-term")
        )

        let executableAliasURL = fixtureRoot.appending(path: "SurgeShallowAlias")
        try fileManager.createSymbolicLink(
            at: executableAliasURL,
            withDestinationURL: targetExecutableURL
        )

        let firstInstance = Process()
        firstInstance.executableURL = targetExecutableURL
        firstInstance.standardOutput = FileHandle.nullDevice
        firstInstance.standardError = FileHandle.nullDevice
        try firstInstance.run()
        let aliasedSecondInstance = Process()
        aliasedSecondInstance.executableURL = executableAliasURL
        aliasedSecondInstance.standardOutput = FileHandle.nullDevice
        aliasedSecondInstance.standardError = FileHandle.nullDevice
        try aliasedSecondInstance.run()
        defer {
            for process in [firstInstance, aliasedSecondInstance] where process.isRunning {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        try waitUntilProcessCommandMatches(
            processIdentifier: firstInstance.processIdentifier,
            expectedCommand: targetExecutableURL.path
        )
        try waitUntilProcessCommandMatches(
            processIdentifier: aliasedSecondInstance.processIdentifier,
            expectedCommand: executableAliasURL.path
        )

        let workingDirectory = fixtureRoot.appending(
            path: "helper-work",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let helperURL = workingDirectory.appending(path: "install-update.sh")
        try Data(shortenedInstallationHelper.utf8).write(to: helperURL)
        let resultURL = fixtureRoot.appending(path: "result.txt")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            fixtureRoot.appending(path: "missing-staged.app").path,
            targetApplicationURL.resolvingSymlinksInPath().path,
            String(firstInstance.processIdentifier),
            workingDirectory.appending(path: "ready").path,
            resultURL.path,
            "2.2.0",
            fixtureRoot.appending(path: "confirmation").path
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        helper.waitUntilExit()

        XCTAssertEqual(helper.terminationStatus, 11)
        XCTAssertEqual(
            try String(contentsOf: resultURL, encoding: .utf8),
            "failed\nmultiple-running-instances\n"
        )
        XCTAssertFalse(firstInstance.isRunning)
        XCTAssertTrue(aliasedSecondInstance.isRunning)
        XCTAssertTrue(fileManager.fileExists(atPath: targetApplicationURL.path))
        XCTAssertFalse(
            fileManager.fileExists(atPath: targetApplicationURL.path + ".update-backup")
        )
    }

    func testInstallerFailsClosedWhenProcessEnumerationFails() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let targetApplicationURL = fixtureRoot.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        let targetExecutableURL = targetApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        try fileManager.createDirectory(
            at: targetExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try compileUnresponsiveApplication(
            at: targetExecutableURL,
            termMarkerURL: fixtureRoot.appending(path: "unused-term-marker")
        )

        let failingLSOFURL = fixtureRoot.appending(path: "failing-lsof")
        let failingLSOF = #"""
        #!/bin/sh
        case " $* " in
            *" -p "*) exec /usr/sbin/lsof "$@" ;;
        esac
        echo "simulated target enumeration failure" >&2
        exit 1
        """#
        try Data(failingLSOF.utf8).write(to: failingLSOFURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: failingLSOFURL.path
        )
        let helperScript = shortenedInstallationHelper.replacingOccurrences(
            of: "/usr/sbin/lsof",
            with: failingLSOFURL.path
        )
        let workingDirectory = fixtureRoot.appending(
            path: "helper-work",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let helperURL = workingDirectory.appending(path: "install-update.sh")
        try Data(helperScript.utf8).write(to: helperURL)
        let resultURL = fixtureRoot.appending(path: "result.txt")

        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            fixtureRoot.appending(path: "missing-staged.app").path,
            targetApplicationURL.resolvingSymlinksInPath().path,
            "999999",
            workingDirectory.appending(path: "ready").path,
            resultURL.path,
            "2.2.0",
            fixtureRoot.appending(path: "confirmation").path
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        helper.waitUntilExit()

        XCTAssertEqual(helper.terminationStatus, 11)
        XCTAssertEqual(
            try String(contentsOf: resultURL, encoding: .utf8),
            "failed\nprocess-enumeration-failed\n"
        )
        XCTAssertTrue(fileManager.fileExists(atPath: targetApplicationURL.path))
        XCTAssertFalse(
            fileManager.fileExists(atPath: targetApplicationURL.path + ".update-backup")
        )
    }

    func testInstallerRollsBackWhenSecondInstanceStartsAfterTargetMovesToBackup() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let targetApplicationURL = fixtureRoot.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        let targetExecutableURL = targetApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        try fileManager.createDirectory(
            at: targetExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try compileUnresponsiveApplication(
            at: targetExecutableURL,
            termMarkerURL: fixtureRoot.appending(path: "unused-term-marker")
        )

        let dittoMarkerURL = fixtureRoot.appending(path: "ditto-was-called")
        let fakeDittoURL = fixtureRoot.appending(path: "recording-ditto")
        let fakeDitto = #"""
        #!/bin/sh
        /usr/bin/touch "\#(dittoMarkerURL.path)"
        exit 1
        """#
        try Data(fakeDitto.utf8).write(to: fakeDittoURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fakeDittoURL.path
        )
        let pauseAfterBackup = #"""
        fi

        /bin/sleep 1
        /bin/rm -f "$confirmation_file"
        """#
        let helperScript = shortenedInstallationHelper.replacingOccurrences(
            of: #"""
            fi

            /bin/rm -f "$confirmation_file"
            """#,
            with: pauseAfterBackup
        )
        .replacingOccurrences(of: "/usr/bin/ditto", with: fakeDittoURL.path)
        let workingDirectory = fixtureRoot.appending(
            path: "helper-work",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let helperURL = workingDirectory.appending(path: "install-update.sh")
        try Data(helperScript.utf8).write(to: helperURL)
        let resultURL = fixtureRoot.appending(path: "result.txt")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            fixtureRoot.appending(path: "missing-staged.app").path,
            targetApplicationURL.resolvingSymlinksInPath().path,
            "999999",
            workingDirectory.appending(path: "ready").path,
            resultURL.path,
            "2.2.0",
            fixtureRoot.appending(path: "confirmation").path
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()

        let backupApplicationURL = URL(filePath: targetApplicationURL.path + ".update-backup")
        try waitUntilFileExists(at: backupApplicationURL)
        let backupExecutableURL = backupApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        let lateSecondInstance = Process()
        lateSecondInstance.executableURL = backupExecutableURL
        lateSecondInstance.standardOutput = FileHandle.nullDevice
        lateSecondInstance.standardError = FileHandle.nullDevice
        try lateSecondInstance.run()
        defer {
            if lateSecondInstance.isRunning {
                _ = Darwin.kill(lateSecondInstance.processIdentifier, SIGKILL)
                lateSecondInstance.waitUntilExit()
            }
        }
        try waitUntilProcessCommandMatches(
            processIdentifier: lateSecondInstance.processIdentifier,
            expectedCommand: backupExecutableURL.path
        )

        helper.waitUntilExit()

        XCTAssertEqual(helper.terminationStatus, 11)
        XCTAssertEqual(
            try String(contentsOf: resultURL, encoding: .utf8),
            "failed\nmultiple-running-instances\n"
        )
        XCTAssertTrue(lateSecondInstance.isRunning)
        XCTAssertTrue(fileManager.fileExists(atPath: targetApplicationURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: backupApplicationURL.path))
        XCTAssertFalse(
            fileManager.fileExists(atPath: dittoMarkerURL.path),
            "检测到移动后启动的第二实例时绝不能开始复制新 App。"
        )
    }

    func testInstallerPerformsFinalScanImmediatelyBeforeDitto() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let targetApplicationURL = fixtureRoot.appending(
            path: "Surge Shallow.app",
            directoryHint: .isDirectory
        )
        let targetExecutableURL = targetApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        try fileManager.createDirectory(
            at: targetExecutableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try compileUnresponsiveApplication(
            at: targetExecutableURL,
            termMarkerURL: fixtureRoot.appending(path: "unused-term-marker")
        )

        let backupApplicationURL = URL(filePath: targetApplicationURL.path + ".update-backup")
        let backupExecutableURL = backupApplicationURL.appending(
            path: "Contents/MacOS/SurgeShallow"
        )
        let scanCountURL = fixtureRoot.appending(path: "backup-scan-count")
        let tenthScanCompleteURL = fixtureRoot.appending(path: "tenth-scan-complete")
        let releaseTenthScanURL = fixtureRoot.appending(path: "release-tenth-scan")
        let controlledLSOFURL = fixtureRoot.appending(path: "controlled-lsof")
        let controlledLSOF = """
        #!/bin/sh
        is_pid_query=0
        for argument in "$@"; do
            if [ "$argument" = "-p" ]; then
                is_pid_query=1
            fi
        done
        if [ "$is_pid_query" -eq 0 ]; then
            count=0
            if [ -f '\(scanCountURL.path)' ]; then
                count=$(/bin/cat '\(scanCountURL.path)')
            fi
            count=$((count + 1))
            /usr/bin/printf '%s\n' "$count" > '\(scanCountURL.path)'
            # Query 1 is the pre-move target scan; query 11 is the tenth
            # backup-vnode stability scan.
            if [ "$count" -eq 11 ]; then
                /usr/sbin/lsof "$@"
                result=$?
                /usr/bin/touch '\(tenthScanCompleteURL.path)'
                while [ ! -f '\(releaseTenthScanURL.path)' ]; do
                    /bin/sleep 0.01
                done
                exit "$result"
            fi
        fi
        exec /usr/sbin/lsof "$@"
        """
        try Data(controlledLSOF.utf8).write(to: controlledLSOFURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: controlledLSOFURL.path
        )

        let dittoMarkerURL = fixtureRoot.appending(path: "ditto-was-called")
        let fakeDittoURL = fixtureRoot.appending(path: "recording-ditto")
        let fakeDitto = """
        #!/bin/sh
        /usr/bin/touch '\(dittoMarkerURL.path)'
        exit 1
        """
        try Data(fakeDitto.utf8).write(to: fakeDittoURL)
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fakeDittoURL.path
        )

        let helperScript = shortenedInstallationHelper
            .replacingOccurrences(of: "/usr/sbin/lsof", with: controlledLSOFURL.path)
            .replacingOccurrences(of: "/usr/bin/ditto", with: fakeDittoURL.path)
        let workingDirectory = fixtureRoot.appending(
            path: "helper-work",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let helperURL = workingDirectory.appending(path: "install-update.sh")
        try Data(helperScript.utf8).write(to: helperURL)
        let resultURL = fixtureRoot.appending(path: "result.txt")
        let helper = Process()
        helper.executableURL = URL(filePath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            fixtureRoot.appending(path: "missing-staged.app").path,
            targetApplicationURL.resolvingSymlinksInPath().path,
            "999999",
            workingDirectory.appending(path: "ready").path,
            resultURL.path,
            "2.2.0",
            fixtureRoot.appending(path: "confirmation").path
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()

        try waitUntilFileExists(at: tenthScanCompleteURL)
        let finalWindowInstance = Process()
        finalWindowInstance.executableURL = backupExecutableURL
        finalWindowInstance.standardOutput = FileHandle.nullDevice
        finalWindowInstance.standardError = FileHandle.nullDevice
        try finalWindowInstance.run()
        defer {
            if finalWindowInstance.isRunning {
                _ = Darwin.kill(finalWindowInstance.processIdentifier, SIGKILL)
                finalWindowInstance.waitUntilExit()
            }
        }
        try waitUntilProcessCommandMatches(
            processIdentifier: finalWindowInstance.processIdentifier,
            expectedCommand: backupExecutableURL.path
        )
        try Data().write(to: releaseTenthScanURL)

        helper.waitUntilExit()

        XCTAssertEqual(helper.terminationStatus, 11)
        XCTAssertEqual(
            try String(contentsOf: resultURL, encoding: .utf8),
            "failed\nmultiple-running-instances\n"
        )
        XCTAssertTrue(finalWindowInstance.isRunning)
        XCTAssertTrue(fileManager.fileExists(atPath: targetApplicationURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: backupApplicationURL.path))
        XCTAssertFalse(
            fileManager.fileExists(atPath: dittoMarkerURL.path),
            "最终 backup executable 枚举必须发生在 ditto 紧邻之前。"
        )
    }

    private var fastInstallationHelper: String {
        shortenedInstallationHelper
            .replacingOccurrences(
                of: #"/bin/rm -rf "$backup_app""#,
                with: "exit 0\n\n" + #"/bin/rm -rf "$backup_app""#,
                options: [],
                range: nil
            )
    }

    private var shortenedInstallationHelper: String {
        SoftwareUpdateInstaller.installationHelper
            .replacingOccurrences(of: #"[ "$attempts" -ge 600 ]"#, with: #"[ "$attempts" -ge 2 ]"#)
            .replacingOccurrences(of: #"[ "$attempts" -ge 100 ]"#, with: #"[ "$attempts" -ge 2 ]"#)
            .replacingOccurrences(of: #"[ "$attempts" -ge 50 ]"#, with: #"[ "$attempts" -ge 2 ]"#)
            .replacingOccurrences(of: #"[ "$attempts" -ge 20 ]"#, with: #"[ "$attempts" -ge 2 ]"#)
    }

    private func compileUnresponsiveApplication(at executableURL: URL, termMarkerURL: URL) throws {
        let sourceURL = executableURL.deletingLastPathComponent().appending(path: "fixture.c")
        let marker = termMarkerURL.path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = #"""
        #include <fcntl.h>
        #include <signal.h>
        #include <unistd.h>

        static int marker_fd = -1;

        static void record_term(int signal_number) {
            (void)signal_number;
            const char marker[] = "TERM\n";
            if (marker_fd >= 0) {
                (void)write(marker_fd, marker, sizeof(marker) - 1);
                (void)fsync(marker_fd);
            }
        }

        int main(void) {
            marker_fd = open("\#(marker)", O_WRONLY | O_CREAT | O_TRUNC, 0600);
            struct sigaction action = {0};
            action.sa_handler = record_term;
            sigemptyset(&action.sa_mask);
            sigaction(SIGTERM, &action, NULL);
            for (;;) pause();
        }
        """#
        try Data(source.utf8).write(to: sourceURL)

        let compiler = Process()
        let output = Pipe()
        compiler.executableURL = URL(filePath: "/usr/bin/clang")
        compiler.arguments = [sourceURL.path, "-o", executableURL.path]
        compiler.standardOutput = output
        compiler.standardError = output
        try compiler.run()
        compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else {
            let diagnostics = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            XCTFail("Could not compile updater process fixture: \(diagnostics)")
            return
        }
    }

    private func waitUntilProcessCommandMatches(
        processIdentifier: Int32,
        expectedCommand: String
    ) throws {
        for _ in 0..<50 {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(filePath: "/bin/ps")
            process.arguments = ["-p", String(processIdentifier), "-o", "command="]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            let command = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            if command == expectedCommand || command?.hasPrefix(expectedCommand + " ") == true {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("Fixture process did not expose the expected executable command.")
    }

    private func waitUntilFileExists(at url: URL) throws {
        for _ in 0..<500 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTFail("Expected file did not appear: \(url.path)")
    }

}
