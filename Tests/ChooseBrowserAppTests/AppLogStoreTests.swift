import Foundation
import Testing
@testable import ChooseBrowserApp

@Test
func logsRedactCredentialsPathsQueriesFragmentsAndCustomCallbacks() {
    let message = "Open https://user:password@example.com/private?code=secret#token and portal:callback?code=secret"
    let safe = AppLogStore.redactedMessage(message)
    #expect(safe.contains("https://example.com/<redacted>"))
    for secret in ["user", "password", "private", "secret", "token", "callback"] {
        #expect(!safe.contains(secret))
    }
}

@Test
func logsRemainBoundedAndKeepRecentEntriesInOrder() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("app.log")
    // Exercise migration of an existing oversized log as well as normal writes.
    try Data(String(repeating: "old entry\n", count: 250_000).utf8).write(to: file)
    let store = AppLogStore(logFileURL: file)
    store.append("First https://example.com/?code=secret")
    store.append("Second")
    let entries = await store.loadEntries()
    #expect(entries.count <= 1_000)
    #expect(entries.first?.message.hasSuffix("Second") == true)
    #expect(entries.dropFirst().first?.message.hasSuffix("First https://example.com/<redacted>") == true)
    let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as! NSNumber
    #expect(size.intValue <= AppLogStore.maximumLogBytes)
    let contents = try String(contentsOf: file, encoding: .utf8)
    #expect(!contents.contains("secret"))
}
