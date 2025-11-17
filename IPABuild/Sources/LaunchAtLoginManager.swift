import Foundation
import Darwin

enum LaunchAtLoginError: LocalizedError {
    case missingBundleIdentifier
    case cannotRegister(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "未能获取应用标识。"
        case .cannotRegister(let reason):
            return reason
        }
    }
}

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let agentManager = LaunchAgentManager()

    private init() {}

    func isEnabled(bundleIdentifier: String) -> Bool {
        agentManager.isEnabled(bundleIdentifier: bundleIdentifier)
    }

    func setEnabled(
        _ enabled: Bool,
        bundleIdentifier: String,
        executablePath: String,
        activateImmediately: Bool = true
    ) throws {
        try agentManager.setEnabled(
            enabled,
            bundleIdentifier: bundleIdentifier,
            executablePath: executablePath,
            activateImmediately: activateImmediately
        )
    }
}

private final class LaunchAgentManager {
    private let fileManager = FileManager.default

    func isEnabled(bundleIdentifier: String) -> Bool {
        fileManager.fileExists(atPath: plistURL(for: bundleIdentifier).path)
    }

    func setEnabled(
        _ enabled: Bool,
        bundleIdentifier: String,
        executablePath: String,
        activateImmediately: Bool
    ) throws {
        let plistURL = plistURL(for: bundleIdentifier)
        let directory = plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        if enabled {
            let data = try launchAgentPlist(bundleIdentifier: bundleIdentifier, executablePath: executablePath)
            try data.write(to: plistURL, options: .atomic)
            guard activateImmediately else { return }
            _ = try? runLaunchctl(["bootout", launchctlTarget(), plistURL.path])
            try runLaunchctl(["bootstrap", launchctlTarget(), plistURL.path])
        } else {
            if fileManager.fileExists(atPath: plistURL.path) {
                _ = try? runLaunchctl(["bootout", launchctlTarget(), plistURL.path])
                try fileManager.removeItem(at: plistURL)
            }
        }
    }

    private func plistURL(for bundleIdentifier: String) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(bundleIdentifier).launchagent.plist")
    }

    private func launchAgentPlist(bundleIdentifier: String, executablePath: String) throws -> Data {
        let dict: [String: Any] = [
            "Label": bundleIdentifier,
            "Program": executablePath,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "launchctl 执行失败"
            throw LaunchAtLoginError.cannotRegister(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return process.terminationStatus
    }

    private func launchctlTarget() -> String {
        let uid = getuid()
        return "gui/\(uid)"
    }
}
