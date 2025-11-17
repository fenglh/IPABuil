import Foundation
import ServiceManagement

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

    private let legacyManager = LegacyLaunchAgentManager()

    private init() {}

    func isEnabled(bundleIdentifier: String) -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return legacyManager.isEnabled(bundleIdentifier: bundleIdentifier)
        }
    }

    func setEnabled(_ enabled: Bool, bundleIdentifier: String, appPath: String) throws {
        if #available(macOS 13.0, *) {
            try updateUsingSMAppService(enabled: enabled)
        } else {
            try legacyManager.setEnabled(enabled, bundleIdentifier: bundleIdentifier, appPath: appPath)
        }
    }

    @available(macOS 13.0, *)
    private func updateUsingSMAppService(enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LaunchAtLoginError.cannotRegister(error.localizedDescription)
        }
    }
}

private final class LegacyLaunchAgentManager {
    private let fileManager = FileManager.default

    func isEnabled(bundleIdentifier: String) -> Bool {
        fileManager.fileExists(atPath: plistURL(for: bundleIdentifier).path)
    }

    func setEnabled(_ enabled: Bool, bundleIdentifier: String, appPath: String) throws {
        let plistURL = plistURL(for: bundleIdentifier)
        let directory = plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        if enabled {
            let data = try launchAgentPlist(bundleIdentifier: bundleIdentifier, appPath: appPath)
            try data.write(to: plistURL, options: .atomic)
            _ = try? runLaunchctl(["unload", plistURL.path])
            try runLaunchctl(["load", "-w", plistURL.path])
        } else {
            if fileManager.fileExists(atPath: plistURL.path) {
                _ = try? runLaunchctl(["unload", plistURL.path])
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

    private func launchAgentPlist(bundleIdentifier: String, appPath: String) throws -> Data {
        let dict: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": ["/usr/bin/open", appPath],
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
}
