import AppKit
import ChooseBrowserCore
import Foundation

struct AppLogEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let message: String
}

final class AppLogStore: Sendable {
    static let shared = AppLogStore()
    static let maximumLogBytes = 1_048_576
    private static let tailBytes = 524_288
    private static let maximumEntries = 1_000
    private static let urlPattern = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.-]*:(?://)?[^\s]+"#)

    let logFileURL: URL
    private let queue = DispatchQueue(label: "app.browserportal.log", qos: .utility)

    init(fileManager: FileManager = .default, logFileURL: URL? = nil) {
        self.logFileURL = logFileURL ?? Self.defaultLogFileURL(fileManager: fileManager)
    }

    static func defaultLogFileURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Logs", directoryHint: .isDirectory)
            .appending(path: AppIdentity.supportDirectoryName, directoryHint: .isDirectory)
            .appending(path: "app.log", directoryHint: .notDirectory)
    }

    // Keep only the origin. URL paths, credentials, queries, and fragments can contain secrets.
    static func redactedMessage(_ message: String) -> String {
        let result = NSMutableString(string: message)
        let range = NSRange(message.startIndex..., in: message)
        for match in urlPattern.matches(in: message, range: range).reversed() {
            let rawURL = (message as NSString).substring(with: match.range)
            let components = URLComponents(string: rawURL)
            let origin: String
            if let scheme = components?.scheme, let host = components?.host, scheme != "file" {
                let port = components?.port.map { ":\($0)" } ?? ""
                origin = "\(scheme)://\(host)\(port)/<redacted>"
            } else {
                origin = "<redacted URL>"
            }
            result.replaceCharacters(in: match.range, with: origin)
        }
        return result as String
    }

    func append(_ message: String) {
        let date = Date()
        queue.async { [self] in
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let safeMessage = Self.redactedMessage(message)
                let line = "[\(formatter.string(from: date))] \(String(safeMessage.prefix(8_192)))\n"
                let data = Data(line.utf8)
                if !fileManager.fileExists(atPath: logFileURL.path(percentEncoded: false)) {
                    try data.write(to: logFileURL, options: .atomic)
                    return
                }
                let handle = try FileHandle(forUpdating: logFileURL)
                defer { try? handle.close() }
                let size = try handle.seekToEnd()
                if size + UInt64(data.count) > UInt64(Self.maximumLogBytes) {
                    let tail = try readTail()
                    try handle.seek(toOffset: 0)
                    try handle.write(contentsOf: tail)
                    try handle.truncate(atOffset: UInt64(tail.count))
                }
                try handle.write(contentsOf: data)
            } catch {
                NSLog("Browser Portal logging failed: %@", Self.redactedMessage(error.localizedDescription))
            }
        }
    }

    func loadEntries() async -> [AppLogEntry] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let data = (try? readTail()) ?? Data()
                let entries = String(decoding: data, as: UTF8.self)
                    .split(whereSeparator: \.isNewline)
                    .suffix(Self.maximumEntries)
                    .reversed()
                    .map { AppLogEntry(message: Self.redactedMessage(String($0))) }
                continuation.resume(returning: entries)
            }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func readTail() throws -> Data {
        let handle = try FileHandle(forReadingFrom: logFileURL)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: Self.tailBytes) ?? Data()
        if offset > 0, let newline = data.firstIndex(of: 10) {
            return Data(data.suffix(from: data.index(after: newline)))
        }
        return offset == 0 ? data : Data()
    }

    @MainActor
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }
}
