import AppKit
import ChooseBrowserCore
import Foundation

@MainActor
final class BrowserFallbackService {
    private static let knownBrowserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "org.torproject.torbrowser",
        "com.kagi.kagimacOS",
        "app.zen-browser.zen",
    ]

    private let logStore: AppLogStore
    private let workspace: NSWorkspace
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let appBundleIdentifier: String
    private let rememberedBrowserURLKey = "LastUsedFallbackBrowserURL"

    init(
        logStore: AppLogStore = .shared,
        workspace: NSWorkspace = .shared,
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        appBundleIdentifier: String = AppIdentity.bundleIdentifier
    ) {
        self.logStore = logStore
        self.workspace = workspace
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.appBundleIdentifier = appBundleIdentifier
    }

    func startTracking() {
        logStore.append("Started tracking active browser applications.")
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
    }

    func open(url: URL) throws {
        guard let applicationURL = preferredBrowserApplicationURL() else {
            logStore.append("No fallback browser available for unmatched URL: \(url.absoluteString)")
            throw ChooseBrowserError.noFallbackBrowser
        }

        logStore.append("Opening unmatched URL in fallback browser \(applicationURL.lastPathComponent): \(url.absoluteString)")
        let configuration = NSWorkspace.OpenConfiguration()
        workspace.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in
                    AppLogStore.shared.append("Fallback browser launch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc
    private func handleApplicationDidActivate(_ notification: Notification) {
        guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        logStore.append("App activated: \(describe(runningApplication))")

        guard
            let bundleIdentifier = runningApplication.bundleIdentifier,
            bundleIdentifier != appBundleIdentifier,
            let bundleURL = runningApplication.bundleURL,
            isBrowserApplication(at: bundleURL)
        else {
            return
        }

        userDefaults.set(bundleURL.path(percentEncoded: false), forKey: rememberedBrowserURLKey)
        logStore.append("Remembered active browser: \(bundleURL.lastPathComponent)")
    }

    @objc
    private func handleApplicationDidLaunch(_ notification: Notification) {
        guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        logStore.append("App launched: \(describe(runningApplication))")
    }

    private func preferredBrowserApplicationURL() -> URL? {
        if let rememberedPath = userDefaults.string(forKey: rememberedBrowserURLKey) {
            let rememberedURL = URL(fileURLWithPath: rememberedPath)
            if rememberedURL.path != Bundle.main.bundleURL.path, isBrowserApplication(at: rememberedURL) {
                logStore.append("Using remembered fallback browser: \(rememberedURL.lastPathComponent)")
                return rememberedURL
            }

            userDefaults.removeObject(forKey: rememberedBrowserURLKey)
            logStore.append("Discarded remembered fallback browser because it is not a supported browser: \(rememberedURL.lastPathComponent)")
        }

        if
            let frontmostApplication = workspace.frontmostApplication,
            let bundleIdentifier = frontmostApplication.bundleIdentifier,
            bundleIdentifier != appBundleIdentifier,
            let bundleURL = frontmostApplication.bundleURL,
            isBrowserApplication(at: bundleURL)
        {
            logStore.append("Using frontmost fallback browser: \(describe(frontmostApplication))")
            return bundleURL
        }

        let runningBrowserURL = workspace.runningApplications
            .filter { runningApplication in
                guard let bundleIdentifier = runningApplication.bundleIdentifier else {
                    return false
                }

                return bundleIdentifier != appBundleIdentifier
                    && runningApplication.bundleURL != nil
                    && isBrowserApplication(runningApplication)
            }
            .max(by: { lhs, rhs in
                lhs.processIdentifier < rhs.processIdentifier
            })?
            .bundleURL

        if let runningBrowserURL {
            logStore.append("Using running fallback browser: \(runningBrowserURL.lastPathComponent)")
        } else {
            logStore.append("No remembered, frontmost, or running fallback browser candidate was found.")
        }

        return runningBrowserURL
    }

    private func isBrowserApplication(at bundleURL: URL) -> Bool {
        guard let bundle = Bundle(url: bundleURL) else {
            return false
        }

        if let bundleIdentifier = bundle.bundleIdentifier {
            if bundleIdentifier == appBundleIdentifier {
                return false
            }

            if Self.knownBrowserBundleIdentifiers.contains(bundleIdentifier) {
                return true
            }
        }

        let infoDictionary = bundle.infoDictionary ?? [:]
        let hasBrowsableWebSchemes = hasPrimaryWebURLSchemes(in: infoDictionary)
        let hasBrowsingUserActivity = (infoDictionary["NSUserActivityTypes"] as? [String])?.contains("NSUserActivityTypeBrowsingWeb") == true
        let hasWebBrowserDocumentClaim = hasWebBrowserDocumentClaim(in: infoDictionary)

        if hasBrowsableWebSchemes && (hasBrowsingUserActivity || hasWebBrowserDocumentClaim) {
            return true
        }

        return false
    }

    private func hasPrimaryWebURLSchemes(in infoDictionary: [String: Any]) -> Bool {
        guard let urlTypes = infoDictionary["CFBundleURLTypes"] as? [[String: Any]] else {
            return false
        }

        for urlType in urlTypes {
            let schemes = Set(urlType["CFBundleURLSchemes"] as? [String] ?? [])
            guard schemes.contains("http") || schemes.contains("https") else {
                continue
            }

            let handlerRank = (urlType["LSHandlerRank"] as? String)?.lowercased()
            if handlerRank == "alternate" || handlerRank == "none" {
                continue
            }

            return true
        }

        return false
    }

    private func hasWebBrowserDocumentClaim(in infoDictionary: [String: Any]) -> Bool {
        guard let documentTypes = infoDictionary["CFBundleDocumentTypes"] as? [[String: Any]] else {
            return false
        }

        for documentType in documentTypes {
            let contentTypes = Set(documentType["LSItemContentTypes"] as? [String] ?? [])
            if contentTypes.contains("com.apple.default-app.web-browser") {
                return true
            }
        }

        return false
    }

    private func isBrowserApplication(_ runningApplication: NSRunningApplication) -> Bool {
        guard let bundleURL = runningApplication.bundleURL else {
            return false
        }

        return isBrowserApplication(at: bundleURL)
    }

    private func describe(_ runningApplication: NSRunningApplication) -> String {
        let name = runningApplication.localizedName ?? "(unknown)"
        let bundleIdentifier = runningApplication.bundleIdentifier ?? "(no bundle id)"
        let bundlePath = runningApplication.bundleURL?.lastPathComponent ?? "(no bundle)"
        return "\(name) [\(bundleIdentifier)] via \(bundlePath)"
    }
}
