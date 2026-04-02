import AppKit
import ChooseBrowserCore
import Foundation

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
    private var pendingConfigurationWindowWorkItem: DispatchWorkItem?
    private var configurationWindowController: ConfigurationWindowController?

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
            route(urls: launchURLs, shouldTerminateAfterRouting: true)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.showConfigurationWindow()
        }
        pendingConfigurationWindowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    @objc
    private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        pendingConfigurationWindowWorkItem?.cancel()

        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL)
        else {
            present(error: ChooseBrowserError.invalidURL("(missing URL event payload)"))
            if configurationWindowController == nil {
                NSApplication.shared.terminate(nil)
            }
            return
        }

        route(
            urls: [url],
            shouldTerminateAfterRouting: configurationWindowController == nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func showConfigurationWindow() {
        NSApplication.shared.setActivationPolicy(.regular)

        if configurationWindowController == nil {
            configurationWindowController = ConfigurationWindowController(router: router)
        }

        configurationWindowController?.showAndActivate()
    }

    private func route(urls: [URL], shouldTerminateAfterRouting: Bool) {
        for url in urls {
            do {
                _ = try router.open(url: url)
            } catch {
                present(error: error)
                break
            }
        }

        if shouldTerminateAfterRouting {
            NSApplication.shared.terminate(nil)
        }
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
