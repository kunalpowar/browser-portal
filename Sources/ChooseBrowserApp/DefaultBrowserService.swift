import AppKit
import Foundation

struct DefaultBrowserStatus: Equatable {
    let isDefaultForHTTP: Bool
    let isDefaultForHTTPS: Bool

    var isDefaultForWebLinks: Bool {
        isDefaultForHTTP && isDefaultForHTTPS
    }
}

struct DefaultBrowserService {
    func currentStatus(bundleIdentifier: String?) -> DefaultBrowserStatus {
        guard let bundleIdentifier else {
            return DefaultBrowserStatus(isDefaultForHTTP: false, isDefaultForHTTPS: false)
        }

        return DefaultBrowserStatus(
            isDefaultForHTTP: defaultHandler(forScheme: "http") == bundleIdentifier,
            isDefaultForHTTPS: defaultHandler(forScheme: "https") == bundleIdentifier
        )
    }

    func openSettings() {
        let workspace = NSWorkspace.shared

        if let desktopAndDockURL = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension"),
           workspace.open(desktopAndDockURL) {
            return
        }

        if let generalSettingsURL = URL(string: "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings"),
           workspace.open(generalSettingsURL) {
            return
        }

        workspace.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    private func defaultHandler(forScheme scheme: String) -> String? {
        guard let probeURL = URL(string: "\(scheme)://example.com") else {
            return nil
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else {
            return nil
        }

        return Bundle(url: appURL)?.bundleIdentifier
    }
}
