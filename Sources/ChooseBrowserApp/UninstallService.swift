import AppKit
import ChooseBrowserCore
import Foundation

struct UninstallPlan {
    let appBundleURL: URL
    let configDirectoryURL: URL
    let logsDirectoryURL: URL
    let preferencesURL: URL?
    let savedStateURL: URL?
    let cachesURL: URL?
    let legacyAppBundleURL: URL
    let legacyConfigDirectoryURL: URL
    let launchServicesRegisterURL: URL

    static func current(configurationFileURL: URL, bundleIdentifier: String?) -> UninstallPlan {
        let fileManager = FileManager.default
        let libraryDirectory = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library", directoryHint: .isDirectory)
        let applicationsDirectory = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Applications", directoryHint: .isDirectory)
        let effectiveBundleIdentifier = bundleIdentifier ?? AppIdentity.bundleIdentifier

        let preferencesURL =
            libraryDirectory
                .appending(path: "Preferences", directoryHint: .isDirectory)
                .appending(path: "\(effectiveBundleIdentifier).plist", directoryHint: .notDirectory)
        let savedStateURL =
            libraryDirectory
                .appending(path: "Saved Application State", directoryHint: .isDirectory)
                .appending(path: "\(effectiveBundleIdentifier).savedState", directoryHint: .isDirectory)
        let cachesURL =
            libraryDirectory
                .appending(path: "Caches", directoryHint: .isDirectory)
                .appending(path: effectiveBundleIdentifier, directoryHint: .isDirectory)

        return UninstallPlan(
            appBundleURL: Bundle.main.bundleURL,
            configDirectoryURL: configurationFileURL.deletingLastPathComponent(),
            logsDirectoryURL: AppLogStore.defaultLogFileURL(fileManager: fileManager).deletingLastPathComponent(),
            preferencesURL: preferencesURL,
            savedStateURL: savedStateURL,
            cachesURL: cachesURL,
            legacyAppBundleURL: applicationsDirectory
                .appending(path: "ChooseBrowser.app", directoryHint: .isDirectory),
            legacyConfigDirectoryURL: ConfigManager.legacyConfigurationFileURL(fileManager: fileManager)
                .deletingLastPathComponent(),
            launchServicesRegisterURL: URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        )
    }
}

struct UninstallService {
    func uninstallCurrentApp(configurationFileURL: URL, bundleIdentifier: String?) throws {
        let plan = UninstallPlan.current(
            configurationFileURL: configurationFileURL,
            bundleIdentifier: bundleIdentifier
        )

        let shellScript = makeShellScript(for: plan)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellScript]

        do {
            try process.run()
        } catch {
            throw ChooseBrowserError.uninstallFailed(error.localizedDescription)
        }
    }

    private func makeShellScript(for plan: UninstallPlan) -> String {
        let removalTargets = [
            plan.appBundleURL,
            plan.configDirectoryURL,
            plan.logsDirectoryURL,
            plan.preferencesURL,
            plan.savedStateURL,
            plan.cachesURL,
            plan.legacyAppBundleURL,
            plan.legacyConfigDirectoryURL,
        ]
        .compactMap { $0 }
        .map { quoted($0.path(percentEncoded: false)) }
        .joined(separator: " ")

        let launchServicesTool = quoted(plan.launchServicesRegisterURL.path(percentEncoded: false))
        let appBundlePath = quoted(plan.appBundleURL.path(percentEncoded: false))
        let legacyAppBundlePath = quoted(plan.legacyAppBundleURL.path(percentEncoded: false))

        return """
        sleep 1
        if [ -x \(launchServicesTool) ]; then
          \(launchServicesTool) -u \(appBundlePath) >/dev/null 2>&1 || true
          \(launchServicesTool) -u \(legacyAppBundlePath) >/dev/null 2>&1 || true
        fi
        rm -rf \(removalTargets)
        """
    }

    private func quoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
