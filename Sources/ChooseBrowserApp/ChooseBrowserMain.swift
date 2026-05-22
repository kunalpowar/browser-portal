import AppKit
import AuthenticationServices
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
    private let logStore = AppLogStore.shared
    private let launchAtLoginService = LaunchAtLoginService()
    private let browserFallbackService = BrowserFallbackService()
    private let uninstallService = UninstallService()
    private lazy var authenticationSessionService = AuthenticationSessionService { [weak self] in
        self?.ensureBackgroundPresence()
    }
    private var pendingConfigurationWindowWorkItem: DispatchWorkItem?
    private var configurationWindowController: ConfigurationWindowController?
    private var statusItem: NSStatusItem?
    private var hasHandledExternalOpen = false

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
        logStore.append("Application launched.")
        let launchAtLoginState = launchAtLoginService.ensureConfiguredOnFirstRun()
        logStore.append("Launch at login state: \(launchAtLoginState.description)")
        browserFallbackService.startTracking()
        authenticationSessionService.installSessionHandler()

        logStore.append("AuthenticationServices launch flag: \(authenticationSessionService.wasLaunchedByAuthenticationServices).")
        if authenticationSessionService.wasLaunchedByAuthenticationServices {
            return
        }

        let launchURLs = CommandLine.arguments.dropFirst().compactMap(URL.init(string:))
        if !launchURLs.isEmpty {
            logStore.append("Received launch URLs: \(launchURLs.map(\.absoluteString).joined(separator: ", ")).")
            route(urls: launchURLs)
            ensureBackgroundPresence()
            return
        }

        scheduleConfigurationWindowForManualLaunch()
    }

    @objc
    private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        prepareForExternalOpen()

        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL)
        else {
            logStore.append("Received invalid URL event payload.")
            present(error: ChooseBrowserError.invalidURL("(missing URL event payload)"))
            if configurationWindowController == nil {
                NSApplication.shared.terminate(nil)
            }
            return
        }

        logStore.append("Received URL event: \(url.absoluteString)")
        route(
            urls: [url]
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        prepareForExternalOpen()

        let fileURLs = filenames.map { URL(fileURLWithPath: $0) }
        logStore.append("Received file open event: \(fileURLs.map(\.absoluteString).joined(separator: ", "))")
        route(urls: fileURLs)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        prepareForExternalOpen()

        logStore.append("Received URL/file open event: \(urls.map(\.absoluteString).joined(separator: ", "))")
        route(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showConfigurationWindow()
        return false
    }

    private func scheduleConfigurationWindowForManualLaunch() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.hasHandledExternalOpen else {
                return
            }

            self.showConfigurationWindow()
        }
        pendingConfigurationWindowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: workItem)
    }

    private func prepareForExternalOpen() {
        hasHandledExternalOpen = true
        pendingConfigurationWindowWorkItem?.cancel()
    }

    private func installStatusItem() {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = BrandAssets.statusBarImage()
        statusItem.button?.toolTip = AppIdentity.displayName
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openConfigurationFromStatusItem(_:))
        self.statusItem = statusItem
    }

    private func ensureBackgroundPresence() {
        NSApplication.shared.setActivationPolicy(.accessory)
        installStatusItem()
    }

    @objc
    private func openConfigurationFromStatusItem(_ sender: Any?) {
        showConfigurationWindow()
    }

    private func showConfigurationWindow() {
        logStore.append("Showing configuration window.")
        ensureBackgroundPresence()

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
            let startTime = Date()
            do {
                switch try router.plan(for: url) {
                case let .routeInChrome(decision):
                    if decision.matchedRule != nil {
                        logStore.append("Routing matched URL to Chrome profile \(decision.profileEmail ?? decision.profileDirectoryName): \(decision.url.absoluteString)")
                    } else {
                        logStore.append("Routing unmatched URL to configured Chrome destination \(decision.profileEmail ?? decision.profileDirectoryName): \(decision.url.absoluteString)")
                    }
                    try router.open(decision)
                case let .fallbackToSystem(fallbackURL):
                    logStore.append("Falling back to system browser for unmatched URL: \(fallbackURL.absoluteString)")
                    try browserFallbackService.open(url: fallbackURL)
                }
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startTime) * 1_000)
                logStore.append("Finished routing in \(elapsedMilliseconds)ms: \(url.absoluteString)")
            } catch {
                let elapsedMilliseconds = Int(Date().timeIntervalSince(startTime) * 1_000)
                logStore.append("Routing failed for \(url.absoluteString): \(error.localizedDescription)")
                logStore.append("Failed routing after \(elapsedMilliseconds)ms: \(url.absoluteString)")
                present(error: error)
                break
            }
        }
    }

    private func confirmAndUninstall() {
        logStore.append("Uninstall requested from app UI.")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall \(AppIdentity.displayName)?"
        alert.informativeText = "This removes \(AppIdentity.displayName).app from Applications and deletes its local configuration data."
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
        logStore.append("Presenting error alert: \(error.localizedDescription)")
        ensureBackgroundPresence()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(AppIdentity.displayName) couldn't open the link"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
