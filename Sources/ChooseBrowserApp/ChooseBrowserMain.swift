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
        app.setActivationPolicy(.prohibited)
        app.run()
    }
}

@MainActor
final class URLHandlerAppDelegate: NSObject, NSApplicationDelegate {
    private let router = BrowserRouter()
    private let uninstallService = UninstallService()
    private var pendingConfigurationWindowWorkItem: DispatchWorkItem?
    private var configurationWindowController: ConfigurationWindowController?
    private var statusItem: NSStatusItem?

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
        installStatusItem()

        let launchURLs = CommandLine.arguments.dropFirst().compactMap(URL.init(string:))
        if !launchURLs.isEmpty {
            route(urls: launchURLs)
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
            urls: [url]
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "ChooseBrowser")
        statusItem.button?.toolTip = "ChooseBrowser"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openConfigurationFromStatusItem(_:))
        self.statusItem = statusItem
    }

    @objc
    private func openConfigurationFromStatusItem(_ sender: Any?) {
        showConfigurationWindow()
    }

    private func showConfigurationWindow() {
        NSApplication.shared.setActivationPolicy(.accessory)

        if configurationWindowController == nil {
            configurationWindowController = ConfigurationWindowController(
                router: router,
                onRequestQuit: { [weak self] in
                    self?.quitApplication()
                },
                onRequestUninstall: { [weak self] in
                    self?.confirmAndUninstall()
                }
            )
        }

        configurationWindowController?.showAndActivate()
    }

    private func route(urls: [URL]) {
        for url in urls {
            do {
                _ = try router.open(url: url)
            } catch {
                present(error: error)
                break
            }
        }
    }

    private func confirmAndUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall ChooseBrowser?"
        alert.informativeText = "This removes ChooseBrowser.app from Applications and deletes its local configuration data. Your git repo will be left alone."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        NSApplication.shared.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        do {
            try uninstallService.uninstallCurrentApp(
                configurationFileURL: router.configurationFileURL(),
                bundleIdentifier: Bundle.main.bundleIdentifier
            )
            quitApplication()
        } catch {
            present(error: error)
        }
    }

    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    private func present(error: Error) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "ChooseBrowser couldn't open the link"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
