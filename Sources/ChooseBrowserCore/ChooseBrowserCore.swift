import Foundation

public enum AppIdentity {
    public static let displayName = "Browser Portal"
    public static let executableName = "BrowserPortal"
    public static let supportDirectoryName = "BrowserPortal"
    public static let legacySupportDirectoryName = "ChooseBrowser"
    public static let bundleIdentifier = "app.browserportal.mac"
}

public enum ManagedBrowser: String, Codable, CaseIterable, Equatable, Sendable {
    case chrome
    case brave

    public var displayName: String {
        switch self {
        case .chrome:
            return "Google Chrome"
        case .brave:
            return "Brave"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .chrome:
            return "Chrome"
        case .brave:
            return "Brave"
        }
    }

    var applicationName: String {
        switch self {
        case .chrome:
            return "Google Chrome.app"
        case .brave:
            return "Brave Browser.app"
        }
    }

    var executableName: String {
        switch self {
        case .chrome:
            return "Google Chrome"
        case .brave:
            return "Brave Browser"
        }
    }

    var supportPathComponents: [String] {
        switch self {
        case .chrome:
            return ["Google", "Chrome"]
        case .brave:
            return ["BraveSoftware", "Brave-Browser"]
        }
    }
}

public struct URLRule: Codable, Equatable, Sendable {
    public let pattern: String
    public let browser: ManagedBrowser
    public let profileEmail: String

    enum CodingKeys: String, CodingKey {
        case pattern
        case browser
        case profileEmail
    }

    public init(pattern: String, profileEmail: String, browser: ManagedBrowser = .chrome) {
        self.pattern = pattern
        self.browser = browser
        self.profileEmail = profileEmail
    }

    func normalized() -> URLRule {
        URLRule(
            pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
            profileEmail: profileEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            browser: browser
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pattern = try container.decode(String.self, forKey: .pattern)
        browser = try container.decodeIfPresent(ManagedBrowser.self, forKey: .browser) ?? .chrome
        profileEmail = try container.decode(String.self, forKey: .profileEmail)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(browser, forKey: .browser)
        try container.encode(profileEmail, forKey: .profileEmail)
    }
}

public enum UnmatchedLinkBehaviorMode: String, Codable, CaseIterable, Equatable, Sendable {
    case lastActiveBrowser
    case browserLastUsed
    case browserProfile

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "lastActiveBrowser":
            self = .lastActiveBrowser
        case "chromeLastUsed", "browserLastUsed":
            self = .browserLastUsed
        case "chromeProfile", "browserProfile":
            self = .browserProfile
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown unmatched link behavior mode: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ChooseBrowserConfig: Codable, Equatable, Sendable {
    public let unmatchedLinkBehaviorMode: UnmatchedLinkBehaviorMode?
    public let defaultBrowser: ManagedBrowser?
    public let defaultProfileEmail: String?
    public let rules: [URLRule]

    enum CodingKeys: String, CodingKey {
        case unmatchedLinkBehaviorMode
        case defaultBrowser
        case defaultProfileEmail
        case rules
    }

    public init(
        unmatchedLinkBehaviorMode: UnmatchedLinkBehaviorMode? = nil,
        defaultBrowser: ManagedBrowser? = nil,
        defaultProfileEmail: String?,
        rules: [URLRule]
    ) {
        self.unmatchedLinkBehaviorMode = unmatchedLinkBehaviorMode
        self.defaultBrowser = defaultBrowser
        self.defaultProfileEmail = defaultProfileEmail
        self.rules = rules
    }

    public func matchingRule(for url: URL) -> URLRule? {
        let candidate = url.absoluteString
        return rules.first { RuleMatcher.matches($0.pattern, value: candidate) }
    }

    func normalized() -> ChooseBrowserConfig {
        ChooseBrowserConfig(
            unmatchedLinkBehaviorMode: unmatchedLinkBehaviorMode,
            defaultBrowser: defaultBrowser,
            defaultProfileEmail: defaultProfileEmail?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNilIfEmpty,
            rules: rules.map { $0.normalized() }
        )
    }

    public var effectiveUnmatchedLinkBehaviorMode: UnmatchedLinkBehaviorMode {
        if let unmatchedLinkBehaviorMode {
            return unmatchedLinkBehaviorMode
        }

        if defaultProfileEmail?.trimmedNilIfEmpty != nil {
            return .browserProfile
        }

        return .lastActiveBrowser
    }

    public var effectiveDefaultBrowser: ManagedBrowser {
        defaultBrowser ?? .chrome
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unmatchedLinkBehaviorMode = try container.decodeIfPresent(UnmatchedLinkBehaviorMode.self, forKey: .unmatchedLinkBehaviorMode)
        defaultBrowser = try container.decodeIfPresent(ManagedBrowser.self, forKey: .defaultBrowser)
        defaultProfileEmail = try container.decodeIfPresent(String.self, forKey: .defaultProfileEmail)
        rules = try container.decodeIfPresent([URLRule].self, forKey: .rules) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(unmatchedLinkBehaviorMode, forKey: .unmatchedLinkBehaviorMode)
        try container.encodeIfPresent(defaultBrowser, forKey: .defaultBrowser)
        try container.encodeIfPresent(defaultProfileEmail, forKey: .defaultProfileEmail)
        try container.encode(rules, forKey: .rules)
    }
}

public struct ChromiumProfile: Equatable, Sendable {
    public let directoryName: String
    public let displayName: String?
    public let email: String?
    public let hostedDomain: String?
    public let isManaged: Bool?

    public init(
        directoryName: String,
        displayName: String?,
        email: String?,
        hostedDomain: String?,
        isManaged: Bool?
    ) {
        self.directoryName = directoryName
        self.displayName = displayName
        self.email = email
        self.hostedDomain = hostedDomain
        self.isManaged = isManaged
    }
}

public struct ChromiumProfileCatalog: Equatable, Sendable {
    public let lastUsedDirectoryName: String?
    public let profiles: [ChromiumProfile]

    public init(lastUsedDirectoryName: String?, profiles: [ChromiumProfile]) {
        self.lastUsedDirectoryName = lastUsedDirectoryName
        self.profiles = profiles
    }

    public var availableEmails: [String] {
        profiles.compactMap(\.email).sorted()
    }

    public func directoryName(forEmail email: String) -> String? {
        let normalized = email.normalizedEmail
        return profiles.first { $0.email?.normalizedEmail == normalized }?.directoryName
    }

    public func email(forDirectoryName directoryName: String?) -> String? {
        guard let directoryName else {
            return nil
        }

        return profiles.first { $0.directoryName == directoryName }?.email
    }
}

public struct BrowserRoutingDecision: Equatable, Sendable {
    public let url: URL
    public let browser: ManagedBrowser
    public let profileDirectoryName: String
    public let profileEmail: String?
    public let matchedRule: URLRule?

    public init(
        url: URL,
        browser: ManagedBrowser,
        profileDirectoryName: String,
        profileEmail: String?,
        matchedRule: URLRule?
    ) {
        self.url = url
        self.browser = browser
        self.profileDirectoryName = profileDirectoryName
        self.profileEmail = profileEmail
        self.matchedRule = matchedRule
    }
}

public enum BrowserRoutingPlan: Equatable, Sendable {
    case routeInManagedBrowser(BrowserRoutingDecision)
    case fallbackToSystem(URL)
}

public enum ChooseBrowserError: LocalizedError {
    case invalidConfiguration(String)
    case browserNotFound(ManagedBrowser)
    case invalidURL(String)
    case unknownProfileEmail(ManagedBrowser, String, availableEmails: [String])
    case cannotLaunchBrowser(ManagedBrowser, URL)
    case noFallbackBrowser
    case uninstallFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Configuration error: \(message)"
        case let .browserNotFound(browser):
            return "\(browser.applicationName) was not found. Install \(browser.shortDisplayName) in /Applications or ~/Applications."
        case let .invalidURL(value):
            return "\"\(value)\" is not a valid URL."
        case let .unknownProfileEmail(browser, email, availableEmails):
            if availableEmails.isEmpty {
                return "No \(browser.shortDisplayName) profile with email \(email) was found, and \(browser.shortDisplayName) did not report any signed-in profile emails."
            }

            return "No \(browser.shortDisplayName) profile with email \(email) was found. Available emails: \(availableEmails.joined(separator: ", "))."
        case let .cannotLaunchBrowser(browser, url):
            return "\(AppIdentity.displayName) could not launch \(browser.shortDisplayName) for \(url.absoluteString)."
        case .noFallbackBrowser:
            return "Open another browser once so \(AppIdentity.displayName) can hand unmatched links back to it."
        case let .uninstallFailed(message):
            return "\(AppIdentity.displayName) could not uninstall itself. \(message)"
        }
    }
}

public enum RuleMatcher {
    public static func matches(_ pattern: String, value: String) -> Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPattern.isEmpty else {
            return false
        }

        if trimmedPattern.contains("*") || trimmedPattern.contains("?") {
            return WildcardMatcher.matches(trimmedPattern, value: value)
        }

        return value.hasPrefix(trimmedPattern)
    }
}

public enum WildcardMatcher {
    public static func matches(_ pattern: String, value: String) -> Bool {
        let regex = anchoredRegex(from: pattern)
        return value.range(of: regex, options: .regularExpression) != nil
    }

    private static func anchoredRegex(from pattern: String) -> String {
        var regex = "^"

        for character in pattern {
            switch character {
            case "*":
                regex.append(".*")
            case "?":
                regex.append(".")
            case ".", "\\", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|":
                regex.append("\\")
                regex.append(character)
            default:
                regex.append(character)
            }
        }

        regex.append("$")
        return regex
    }
}

public final class ConfigManager {
    public let configurationFileURL: URL
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default, configurationFileURL: URL? = nil) {
        self.fileManager = fileManager
        self.configurationFileURL = configurationFileURL ?? Self.defaultConfigurationFileURL(fileManager: fileManager)
    }

    public func loadOrCreate(defaultProfileEmail: String?) throws -> ChooseBrowserConfig {
        try migrateLegacyConfigIfNeeded()

        let directoryURL = configurationFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: configurationFileURL.fileSystemPath) else {
            let starterConfig = ChooseBrowserConfig(
                unmatchedLinkBehaviorMode: .lastActiveBrowser,
                defaultProfileEmail: defaultProfileEmail,
                rules: []
            )
            try write(config: starterConfig)
            return starterConfig
        }

        do {
            let data = try Data(contentsOf: configurationFileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(ChooseBrowserConfig.self, from: data)
        } catch {
            throw ChooseBrowserError.invalidConfiguration(
                "Could not decode \(configurationFileURL.fileSystemPath). \(error.localizedDescription)"
            )
        }
    }

    public func save(config: ChooseBrowserConfig) throws {
        try fileManager.createDirectory(
            at: configurationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let normalizedConfig = config.normalized()
        try validate(config: normalizedConfig)
        try write(config: normalizedConfig)
    }

    public static func defaultConfigurationFileURL(fileManager: FileManager = .default) -> URL {
        configurationFileURL(
            directoryName: AppIdentity.supportDirectoryName,
            fileManager: fileManager
        )
    }

    public static func legacyConfigurationFileURL(fileManager: FileManager = .default) -> URL {
        configurationFileURL(
            directoryName: AppIdentity.legacySupportDirectoryName,
            fileManager: fileManager
        )
    }

    private static func configurationFileURL(directoryName: String, fileManager: FileManager) -> URL {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        return homeDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: directoryName, directoryHint: .isDirectory)
            .appending(path: "config.json", directoryHint: .notDirectory)
    }

    private func write(config: ChooseBrowserConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configurationFileURL, options: .atomic)
    }

    private func validate(config: ChooseBrowserConfig) throws {
        for (index, rule) in config.rules.enumerated() {
            if rule.pattern.trimmedNilIfEmpty == nil {
                throw ChooseBrowserError.invalidConfiguration("Rule \(index + 1) is missing a URL pattern.")
            }

            if rule.profileEmail.trimmedNilIfEmpty == nil {
                throw ChooseBrowserError.invalidConfiguration("Rule \(index + 1) is missing a profile email.")
            }
        }
    }

    private func migrateLegacyConfigIfNeeded() throws {
        guard !fileManager.fileExists(atPath: configurationFileURL.fileSystemPath) else {
            return
        }

        let legacyConfigurationFileURL = Self.legacyConfigurationFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyConfigurationFileURL.fileSystemPath) else {
            return
        }

        try fileManager.createDirectory(
            at: configurationFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: legacyConfigurationFileURL, to: configurationFileURL)
    }
}

public struct ChromiumEnvironment: Sendable {
    public let browser: ManagedBrowser
    public let appURL: URL
    public let binaryURL: URL
    public let localStateURL: URL

    public init(browser: ManagedBrowser, appURL: URL, binaryURL: URL, localStateURL: URL) {
        self.browser = browser
        self.appURL = appURL
        self.binaryURL = binaryURL
        self.localStateURL = localStateURL
    }

    public static func discover(browser: ManagedBrowser, fileManager: FileManager = .default) throws -> ChromiumEnvironment {
        let candidateAppURLs = [
            URL(fileURLWithPath: "/Applications/\(browser.applicationName)"),
            fileManager.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory)
                .appending(path: browser.applicationName, directoryHint: .isDirectory),
        ]

        guard let appURL = candidateAppURLs.first(where: { fileManager.fileExists(atPath: $0.fileSystemPath) }) else {
            throw ChooseBrowserError.browserNotFound(browser)
        }

        return ChromiumEnvironment(
            browser: browser,
            appURL: appURL,
            binaryURL: appURL
                .appending(path: "Contents", directoryHint: .isDirectory)
                .appending(path: "MacOS", directoryHint: .isDirectory)
                .appending(path: browser.executableName, directoryHint: .notDirectory),
            localStateURL: fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: browser.supportPathComponents[0], directoryHint: .isDirectory)
                .appending(path: browser.supportPathComponents[1], directoryHint: .isDirectory)
                .appending(path: "Local State", directoryHint: .notDirectory)
        )
    }

    public func loadProfileCatalog(fileManager: FileManager = .default) throws -> ChromiumProfileCatalog {
        guard fileManager.fileExists(atPath: localStateURL.fileSystemPath) else {
            return ChromiumProfileCatalog(lastUsedDirectoryName: nil, profiles: [])
        }

        let data = try Data(contentsOf: localStateURL)
        return try ChromiumLocalStateParser.parse(data: data)
    }
}

public enum ChromiumLocalStateParser {
    public static func parse(data: Data) throws -> ChromiumProfileCatalog {
        let object = try JSONSerialization.jsonObject(with: data)

        guard
            let root = object as? [String: Any],
            let profileSection = root["profile"] as? [String: Any]
        else {
            throw ChooseBrowserError.invalidConfiguration("Chromium Local State did not contain a profile section.")
        }

        let lastUsedDirectoryName = profileSection["last_used"] as? String
        let infoCache = profileSection["info_cache"] as? [String: Any] ?? [:]

        let profiles = infoCache.compactMap { directoryName, rawProfile -> ChromiumProfile? in
            guard let profile = rawProfile as? [String: Any] else {
                return nil
            }

            let isManaged: Bool?
            if let value = profile["is_managed"] as? Bool {
                isManaged = value
            } else if let value = profile["is_managed"] as? Int {
                isManaged = value != 0
            } else {
                isManaged = nil
            }

            return ChromiumProfile(
                directoryName: directoryName,
                displayName: (profile["name"] as? String)?.trimmedNilIfEmpty,
                email: (profile["user_name"] as? String)?.trimmedNilIfEmpty,
                hostedDomain: (profile["hosted_domain"] as? String)?.trimmedNilIfEmpty,
                isManaged: isManaged
            )
        }
        .sorted { $0.directoryName < $1.directoryName }

        return ChromiumProfileCatalog(lastUsedDirectoryName: lastUsedDirectoryName, profiles: profiles)
    }
}

public enum ProfileDirectoryResolver {
    public static func resolveDirectory(
        preferredEmail: String?,
        catalog: ChromiumProfileCatalog,
        browser: ManagedBrowser
    ) throws -> String {
        if let preferredEmail = preferredEmail?.trimmedNilIfEmpty {
            if let directoryName = catalog.directoryName(forEmail: preferredEmail) {
                return directoryName
            }

            throw ChooseBrowserError.unknownProfileEmail(browser, preferredEmail, availableEmails: catalog.availableEmails)
        }

        return catalog.lastUsedDirectoryName ?? "Default"
    }
}

public struct ChromiumLauncher: Sendable {
    public let environment: ChromiumEnvironment

    public init(environment: ChromiumEnvironment) {
        self.environment = environment
    }

    public func open(url: URL, inProfileDirectory directoryName: String) throws {
        let process = Process()
        process.executableURL = environment.binaryURL
        process.arguments = [
            "--profile-directory=\(directoryName)",
            "--new-tab",
            url.absoluteString,
        ]

        do {
            try process.run()
        } catch {
            throw ChooseBrowserError.cannotLaunchBrowser(environment.browser, url)
        }
    }
}

public final class BrowserRouter {
    private let fileManager: FileManager
    private let configManager: ConfigManager
    private let environmentProvider: (ManagedBrowser) throws -> ChromiumEnvironment

    public init(
        fileManager: FileManager = .default,
        configManager: ConfigManager? = nil,
        environmentProvider: ((ManagedBrowser) throws -> ChromiumEnvironment)? = nil
    ) {
        self.fileManager = fileManager
        self.configManager = configManager ?? ConfigManager(fileManager: fileManager)
        self.environmentProvider = environmentProvider ?? { browser in
            try ChromiumEnvironment.discover(browser: browser, fileManager: fileManager)
        }
    }

    public func configurationFileURL() -> URL {
        configManager.configurationFileURL
    }

    public func loadConfig() throws -> ChooseBrowserConfig {
        let catalog = (try? availableProfiles(for: .chrome)) ?? ChromiumProfileCatalog(lastUsedDirectoryName: nil, profiles: [])
        let defaultEmail = catalog.email(forDirectoryName: catalog.lastUsedDirectoryName)
        return try configManager.loadOrCreate(defaultProfileEmail: defaultEmail)
    }

    public func saveConfig(_ config: ChooseBrowserConfig) throws {
        try configManager.save(config: config)
    }

    public func availableProfiles(for browser: ManagedBrowser) throws -> ChromiumProfileCatalog {
        let environment = try environmentProvider(browser)
        return try environment.loadProfileCatalog(fileManager: fileManager)
    }

    public func availableProfilesByBrowser() throws -> [ManagedBrowser: ChromiumProfileCatalog] {
        var catalogs: [ManagedBrowser: ChromiumProfileCatalog] = [:]

        for browser in ManagedBrowser.allCases {
            do {
                catalogs[browser] = try availableProfiles(for: browser)
            } catch let ChooseBrowserError.browserNotFound(missingBrowser) where missingBrowser == browser {
                catalogs[browser] = ChromiumProfileCatalog(lastUsedDirectoryName: nil, profiles: [])
            }
        }

        return catalogs
    }

    public func installedBrowsers() -> [ManagedBrowser] {
        ManagedBrowser.allCases.filter { browser in
            (try? environmentProvider(browser)) != nil
        }
    }

    public func plan(for url: URL) throws -> BrowserRoutingPlan {
        let config = try loadConfig()
        let matchedRule = config.matchingRule(for: url)

        guard let matchedRule else {
            switch config.effectiveUnmatchedLinkBehaviorMode {
            case .lastActiveBrowser:
                return .fallbackToSystem(url)
            case .browserLastUsed:
                let browser = config.effectiveDefaultBrowser
                let catalog = try availableProfiles(for: browser)
                let profileDirectoryName = try ProfileDirectoryResolver.resolveDirectory(
                    preferredEmail: nil,
                    catalog: catalog,
                    browser: browser
                )

                return .routeInManagedBrowser(
                    BrowserRoutingDecision(
                        url: url,
                        browser: browser,
                        profileDirectoryName: profileDirectoryName,
                        profileEmail: nil,
                        matchedRule: nil
                    )
                )
            case .browserProfile:
                let browser = config.effectiveDefaultBrowser
                let catalog = try availableProfiles(for: browser)
                let profileDirectoryName = try ProfileDirectoryResolver.resolveDirectory(
                    preferredEmail: config.defaultProfileEmail,
                    catalog: catalog,
                    browser: browser
                )

                return .routeInManagedBrowser(
                    BrowserRoutingDecision(
                        url: url,
                        browser: browser,
                        profileDirectoryName: profileDirectoryName,
                        profileEmail: config.defaultProfileEmail,
                        matchedRule: nil
                    )
                )
            }
        }

        let browser = matchedRule.browser
        let catalog = try availableProfiles(for: browser)
        let preferredEmail = matchedRule.profileEmail
        let profileDirectoryName = try ProfileDirectoryResolver.resolveDirectory(
            preferredEmail: preferredEmail,
            catalog: catalog,
            browser: browser
        )

        return .routeInManagedBrowser(
            BrowserRoutingDecision(
                url: url,
                browser: browser,
                profileDirectoryName: profileDirectoryName,
                profileEmail: preferredEmail,
                matchedRule: matchedRule
            )
        )
    }

    @discardableResult
    public func open(url: URL) throws -> BrowserRoutingDecision {
        switch try plan(for: url) {
        case let .routeInManagedBrowser(decision):
            let environment = try environmentProvider(decision.browser)
            let launcher = ChromiumLauncher(environment: environment)
            try launcher.open(url: url, inProfileDirectory: decision.profileDirectoryName)
            return decision
        case .fallbackToSystem:
            throw ChooseBrowserError.invalidConfiguration("A system fallback plan cannot be opened directly as a managed browser routing decision.")
        }
    }
}

public struct CommandLineInterface {
    private let router: BrowserRouter
    private let standardOutput: FileHandle
    private let standardError: FileHandle

    public init(
        router: BrowserRouter = BrowserRouter(),
        standardOutput: FileHandle = .standardOutput,
        standardError: FileHandle = .standardError
    ) {
        self.router = router
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func run(arguments: [String]) -> Int32? {
        guard let firstArgument = arguments.first else {
            return nil
        }

        switch firstArgument {
        case "--help", "-h":
            writeLine(helpText, to: standardOutput)
            return 0
        case "--print-config-path":
            writeLine(router.configurationFileURL().fileSystemPath, to: standardOutput)
            return 0
        case "--list-profiles":
            do {
                let catalogs = try router.availableProfilesByBrowser()
                let installedBrowsers = router.installedBrowsers()

                if installedBrowsers.isEmpty {
                    writeLine("No supported browsers were found.", to: standardOutput)
                    return 0
                }

                for browser in installedBrowsers {
                    let catalog = catalogs[browser] ?? ChromiumProfileCatalog(lastUsedDirectoryName: nil, profiles: [])
                    writeLine("[\(browser.shortDisplayName)]", to: standardOutput)

                    if catalog.profiles.isEmpty {
                        writeLine("  No signed-in profiles found.", to: standardOutput)
                        continue
                    }

                    for profile in catalog.profiles {
                        let email = profile.email ?? "(no signed-in email)"
                        let marker = profile.directoryName == catalog.lastUsedDirectoryName ? " [last used]" : ""
                        writeLine("  \(profile.directoryName)\t\(email)\t\(profile.displayName ?? "(unnamed)")\(marker)", to: standardOutput)
                    }
                }
                return 0
            } catch {
                writeLine(error.localizedDescription, to: standardError)
                return 1
            }
        default:
            do {
                let urls = try arguments.map(Self.parseURL(_:))
                for url in urls {
                    _ = try router.open(url: url)
                }
                return 0
            } catch {
                writeLine(error.localizedDescription, to: standardError)
                return 1
            }
        }
    }

    private static func parseURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), url.scheme != nil else {
            throw ChooseBrowserError.invalidURL(value)
        }

        return url
    }

    private func writeLine(_ value: String, to handle: FileHandle) {
        guard let data = "\(value)\n".data(using: .utf8) else {
            return
        }

        try? handle.write(contentsOf: data)
    }

    private var helpText: String {
        """
        \(AppIdentity.displayName)

        Usage:
          \(AppIdentity.executableName) --list-profiles
          \(AppIdentity.executableName) --print-config-path
          \(AppIdentity.executableName) <url> [more urls...]

        When run without arguments inside the app bundle, \(AppIdentity.displayName) waits for macOS URL events.
        """
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedEmail: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension URL {
    var fileSystemPath: String {
        path(percentEncoded: false)
    }
}
