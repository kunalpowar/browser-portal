import AppKit
import ChooseBrowserCore
import Foundation

@MainActor
final class BrowserFallbackService {
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

        if let bundleIdentifier = bundle.bundleIdentifier, bundleIdentifier == appBundleIdentifier {
            return false
        }

        let infoDictionary = bundle.infoDictionary ?? [:]

        if let userActivityTypes = infoDictionary["NSUserActivityTypes"] as? [String],
           userActivityTypes.contains("NSUserActivityTypeBrowsingWeb") {
            return true
        }

        if let urlTypes = infoDictionary["CFBundleURLTypes"] as? [[String: Any]] {
            for urlType in urlTypes {
                let schemes = urlType["CFBundleURLSchemes"] as? [String] ?? []
                if schemes.contains("http") || schemes.contains("https") {
                    return true
                }
            }
        }

        if let documentTypes = infoDictionary["CFBundleDocumentTypes"] as? [[String: Any]] {
            for documentType in documentTypes {
                let contentTypes = documentType["LSItemContentTypes"] as? [String] ?? []
                if contentTypes.contains("public.html") || contentTypes.contains("public.xhtml") {
                    return true
                }
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
