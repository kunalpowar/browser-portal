import Foundation
import ServiceManagement

struct LaunchAtLoginState: Equatable {
    let isEnabled: Bool
    let requiresApproval: Bool
    let description: String
}

@MainActor
final class LaunchAtLoginService {
    private let userDefaults: UserDefaults
    private let logStore: AppLogStore
    private let initializationKey = "LaunchAtLoginInitialized"

    init(
        userDefaults: UserDefaults = .standard,
        logStore: AppLogStore = .shared
    ) {
        self.userDefaults = userDefaults
        self.logStore = logStore
    }

    func ensureConfiguredOnFirstRun() -> LaunchAtLoginState {
        guard #available(macOS 13.0, *) else {
            return LaunchAtLoginState(
                isEnabled: false,
                requiresApproval: false,
                description: "Launch at login is unavailable on this macOS version."
            )
        }

        let service = SMAppService.mainApp
        if !userDefaults.bool(forKey: initializationKey) {
            let status = service.status

            if status == .enabled || status == .requiresApproval {
                userDefaults.set(true, forKey: initializationKey)
                return currentState()
            }

            if status == .notFound {
                logStore.append("Launch at login is unavailable until Browser Portal is installed in Applications.")
                return currentState()
            }

            logStore.append("Configuring launch at login for the first time.")
            do {
                if status == .notRegistered {
                    try service.register()
                    logStore.append("Launch at login was enabled automatically.")
                }
                userDefaults.set(true, forKey: initializationKey)
            } catch {
                logStore.append("Launch at login auto-enable failed: \(error.localizedDescription)")
            }
        }

        return currentState()
    }

    func currentState() -> LaunchAtLoginState {
        guard #available(macOS 13.0, *) else {
            return LaunchAtLoginState(
                isEnabled: false,
                requiresApproval: false,
                description: "Launch at login is unavailable on this macOS version."
            )
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return LaunchAtLoginState(
                isEnabled: true,
                requiresApproval: false,
                description: "Browser Portal will start automatically when you log in."
            )
        case .requiresApproval:
            return LaunchAtLoginState(
                isEnabled: false,
                requiresApproval: true,
                description: "macOS needs approval before Browser Portal can start at login."
            )
        case .notFound:
            return LaunchAtLoginState(
                isEnabled: false,
                requiresApproval: false,
                description: "Launch at login is only available for the installed app in Applications."
            )
        case .notRegistered:
            return LaunchAtLoginState(
                isEnabled: false,
                requiresApproval: false,
                description: "Browser Portal will not start automatically when you log in."
            )
        @unknown default:
            return LaunchAtLoginState(
                isEnabled: false,
                requiresApproval: false,
                description: "Launch at login status is unknown."
            )
        }
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
        guard #available(macOS 13.0, *) else {
            return currentState()
        }

        let service = SMAppService.mainApp
        if enabled {
            try service.register()
            logStore.append("Launch at login enabled from settings.")
        } else {
            try service.unregister()
            logStore.append("Launch at login disabled from settings.")
        }

        userDefaults.set(true, forKey: initializationKey)
        return currentState()
    }
}
