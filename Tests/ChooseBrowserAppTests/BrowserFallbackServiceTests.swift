import Foundation
import Testing
@testable import ChooseBrowserApp

@MainActor
@Test
func nativeBrowserLaunchFailureIsReturnedToTheCaller() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let logStore = AppLogStore(logFileURL: directory.appendingPathComponent("app.log"))
    let service = BrowserFallbackService(logStore: logStore)
    var didFail = false
    do {
        try await service.open(url: URL(string: "https://example.com")!, in: directory.appendingPathComponent("Missing.app"))
    } catch {
        didFail = true
    }
    await logStore.flush()
    #expect(didFail)
}
