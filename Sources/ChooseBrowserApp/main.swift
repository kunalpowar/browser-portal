import AppKit
import Foundation
import ChooseBrowserCore

@main
struct ChooseBrowserMain {
    static func main() {
        let cli = CommandLineInterface()

        if let exitCode = cli.run(arguments: Array(CommandLine.arguments.dropFirst())) {
            Foundation.exit(exitCode)
        }

        let app = NSApplication.shared
        let delegate = URLHandlerAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class URLHandlerAppDelegate: NSObject, NSApplicationDelegate {
    private let router = BrowserRouter()
    private var idleExitWorkItem: DispatchWorkItem?

    override init() {
        super.init()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchURLs = CommandLine.arguments.dropFirst().compactMap(URL.init(string:))
        if !launchURLs.isEmpty {
            routeAndExit(for: launchURLs)
            return
        }

        let workItem = DispatchWorkItem { NSApplication.shared.terminate(nil) }
        idleExitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    @objc
    private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        idleExitWorkItem?.cancel()

        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL)
        else {
            present(error: ChooseBrowserError.invalidURL("(missing URL event payload)"))
            NSApplication.shared.terminate(nil)
            return
        }

        routeAndExit(for: [url])
    }

    private func routeAndExit(for urls: [URL]) {
        for url in urls {
            do {
                _ = try router.open(url: url)
            } catch {
                present(error: error)
                break
            }
        }

        NSApplication.shared.terminate(nil)
    }

    private func present(error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ChooseBrowser couldn't open the link"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
