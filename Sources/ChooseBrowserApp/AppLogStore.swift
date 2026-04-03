import AppKit
import ChooseBrowserCore
import Foundation

struct AppLogEntry: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class AppLogStore {
    static let shared = AppLogStore()

    let logFileURL: URL
    private let fileManager: FileManager
    private let iso8601Formatter: ISO8601DateFormatter

    init(fileManager: FileManager = .default, logFileURL: URL? = nil) {
        self.fileManager = fileManager
        self.logFileURL = logFileURL ?? Self.defaultLogFileURL(fileManager: fileManager)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601Formatter = formatter
    }

    nonisolated static func defaultLogFileURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: AppIdentity.supportDirectoryName, directoryHint: .isDirectory)
            .appending(path: "app.log", directoryHint: .notDirectory)
    }

    func append(_ message: String) {
        do {
            try fileManager.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let timestamp = iso8601Formatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let data = Data(line.utf8)

            if fileManager.fileExists(atPath: logFileURL.path(percentEncoded: false)) {
                let handle = try FileHandle(forWritingTo: logFileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logFileURL, options: .atomic)
            }
        } catch {
            NSLog("Browser Portal logging failed: %@", error.localizedDescription)
        }
    }

    func loadEntries() -> [AppLogEntry] {
        guard let data = try? Data(contentsOf: logFileURL),
              let contents = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .reversed()
            .map(AppLogEntry.init(message:))
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }
}
