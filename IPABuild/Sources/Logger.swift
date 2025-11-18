import Foundation

enum LogLevel: String {
    case info = "INFO"
    case error = "ERROR"
}

final class LogManager {
    static let shared = LogManager()

    private let queue = DispatchQueue(label: "com.certificate.reminder.logger", qos: .background)
    private let logURL: URL

    private init() {
        let logsDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("CertificateReminder")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("certificate-reminder.log")
    }

    func log(_ message: String, level: LogLevel = .info) {
        let entry = "[\(level.rawValue)] \(DateFormatter.logFormatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = entry.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: self.logURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.logURL) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(data)
                }
            } else {
                try? data.write(to: self.logURL, options: .atomic)
            }
        }
    }
    
    func currentLogContents() -> String {
        (try? String(contentsOf: logURL)) ?? ""
    }
    
    func clearLogs(completion: (() -> Void)? = nil) {
        queue.async {
            do {
                if FileManager.default.fileExists(atPath: self.logURL.path) {
                    try Data().write(to: self.logURL, options: .atomic)
                }
            } catch {
                // ignore
            }
            completion?()
        }
    }
}

private extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
