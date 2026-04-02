import Foundation

public struct URLRule: Codable, Equatable, Sendable {
    public let pattern: String
    public let profileEmail: String

    public init(pattern: String, profileEmail: String) {
        self.pattern = pattern
        self.profileEmail = profileEmail
    }

    func normalized() -> URLRule {
        URLRule(
            pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
            profileEmail: profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public struct ChooseBrowserConfig: Codable, Equatable, Sendable {
    public let defaultProfileEmail: String?
    public let rules: [URLRule]

    public init(defaultProfileEmail: String?, rules: [URLRule]) {
        self.defaultProfileEmail = defaultProfileEmail
        self.rules = rules
    }

    public func matchingRule(for url: URL) -> URLRule? {
        let candidate = url.absoluteString
        return rules.first { RuleMatcher.matches($0.pattern, value: candidate) }
    }

    func normalized() -> ChooseBrowserConfig {
        ChooseBrowserConfig(
            defaultProfileEmail: defaultProfileEmail?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNilIfEmpty,
            rules: rules.map { $0.normalized() }
        )
    }
}

public struct ChromeProfile: Equatable, Sendable {
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

public struct ChromeProfileCatalog: Equatable, Sendable {
    public let lastUsedDirectoryName: String?
    public let profiles: [ChromeProfile]

    public init(lastUsedDirectoryName: String?, profiles: [ChromeProfile]) {
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
    public let profileDirectoryName: String
    public let profileEmail: String?
    public let matchedRule: URLRule?

    public init(
        url: URL,
        profileDirectoryName: String,
        profileEmail: String?,
        matchedRule: URLRule?
    ) {
        self.url = url
        self.profileDirectoryName = profileDirectoryName
        self.profileEmail = profileEmail
        self.matchedRule = matchedRule
    }
}

public enum ChooseBrowserError: LocalizedError {
    case invalidConfiguration(String)
    case chromeNotFound
    case invalidURL(String)
    case unknownProfileEmail(String, availableEmails: [String])
    case cannotLaunchChrome(URL)
    case uninstallFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message):
            return "Configuration error: \(message)"
        case .chromeNotFound:
            return "Google Chrome.app was not found. Install Chrome in /Applications or ~/Applications."
        case let .invalidURL(value):
            return "\"\(value)\" is not a valid URL."
        case let .unknownProfileEmail(email, availableEmails):
            if availableEmails.isEmpty {
                return "No Chrome profile with email \(email) was found, and Chrome did not report any signed-in profile emails."
            }

            return "No Chrome profile with email \(email) was found. Available emails: \(availableEmails.joined(separator: ", "))."
        case let .cannotLaunchChrome(url):
            return "ChooseBrowser could not launch Chrome for \(url.absoluteString)."
        case let .uninstallFailed(message):
            return "ChooseBrowser could not uninstall itself. \(message)"
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
        let directoryURL = configurationFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: configurationFileURL.fileSystemPath) else {
            let starterConfig = ChooseBrowserConfig(defaultProfileEmail: defaultProfileEmail, rules: [])
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
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        return homeDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "ChooseBrowser", directoryHint: .isDirectory)
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
}

public struct ChromeEnvironment: Sendable {
    public let appURL: URL
    public let binaryURL: URL
    public let localStateURL: URL

    public init(appURL: URL, binaryURL: URL, localStateURL: URL) {
        self.appURL = appURL
        self.binaryURL = binaryURL
        self.localStateURL = localStateURL
    }

    public static func discover(fileManager: FileManager = .default) throws -> ChromeEnvironment {
        let candidateAppURLs = [
            URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            fileManager.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory)
                .appending(path: "Google Chrome.app", directoryHint: .isDirectory),
        ]

        guard let appURL = candidateAppURLs.first(where: { fileManager.fileExists(atPath: $0.fileSystemPath) }) else {
            throw ChooseBrowserError.chromeNotFound
        }

        return ChromeEnvironment(
            appURL: appURL,
            binaryURL: appURL
                .appending(path: "Contents", directoryHint: .isDirectory)
                .appending(path: "MacOS", directoryHint: .isDirectory)
                .appending(path: "Google Chrome", directoryHint: .notDirectory),
            localStateURL: fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library", directoryHint: .isDirectory)
                .appending(path: "Application Support", directoryHint: .isDirectory)
                .appending(path: "Google", directoryHint: .isDirectory)
                .appending(path: "Chrome", directoryHint: .isDirectory)
                .appending(path: "Local State", directoryHint: .notDirectory)
        )
    }

    public func loadProfileCatalog(fileManager: FileManager = .default) throws -> ChromeProfileCatalog {
        guard fileManager.fileExists(atPath: localStateURL.fileSystemPath) else {
            return ChromeProfileCatalog(lastUsedDirectoryName: nil, profiles: [])
        }

        let data = try Data(contentsOf: localStateURL)
        return try ChromeLocalStateParser.parse(data: data)
    }
}

public enum ChromeLocalStateParser {
    public static func parse(data: Data) throws -> ChromeProfileCatalog {
        let object = try JSONSerialization.jsonObject(with: data)

        guard
            let root = object as? [String: Any],
            let profileSection = root["profile"] as? [String: Any]
        else {
            throw ChooseBrowserError.invalidConfiguration("Chrome Local State did not contain a profile section.")
        }

        let lastUsedDirectoryName = profileSection["last_used"] as? String
        let infoCache = profileSection["info_cache"] as? [String: Any] ?? [:]

        let profiles = infoCache.compactMap { directoryName, rawProfile -> ChromeProfile? in
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

            return ChromeProfile(
                directoryName: directoryName,
                displayName: (profile["name"] as? String)?.trimmedNilIfEmpty,
                email: (profile["user_name"] as? String)?.trimmedNilIfEmpty,
                hostedDomain: (profile["hosted_domain"] as? String)?.trimmedNilIfEmpty,
                isManaged: isManaged
            )
        }
        .sorted { $0.directoryName < $1.directoryName }

        return ChromeProfileCatalog(lastUsedDirectoryName: lastUsedDirectoryName, profiles: profiles)
    }
}

public enum ProfileDirectoryResolver {
    public static func resolveDirectory(
        preferredEmail: String?,
        catalog: ChromeProfileCatalog
    ) throws -> String {
        if let preferredEmail = preferredEmail?.trimmedNilIfEmpty {
            if let directoryName = catalog.directoryName(forEmail: preferredEmail) {
                return directoryName
            }

            throw ChooseBrowserError.unknownProfileEmail(preferredEmail, availableEmails: catalog.availableEmails)
        }

        return catalog.lastUsedDirectoryName ?? "Default"
    }
}

public struct ChromeLauncher: Sendable {
    public let environment: ChromeEnvironment

    public init(environment: ChromeEnvironment) {
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
            throw ChooseBrowserError.cannotLaunchChrome(url)
        }
    }
}

public final class BrowserRouter {
    private let fileManager: FileManager
    private let configManager: ConfigManager

    public init(fileManager: FileManager = .default, configManager: ConfigManager? = nil) {
        self.fileManager = fileManager
        self.configManager = configManager ?? ConfigManager(fileManager: fileManager)
    }

    public func configurationFileURL() -> URL {
        configManager.configurationFileURL
    }

    public func loadConfig() throws -> ChooseBrowserConfig {
        let catalog = try availableProfiles()
        let defaultEmail = catalog.email(forDirectoryName: catalog.lastUsedDirectoryName)
        return try configManager.loadOrCreate(defaultProfileEmail: defaultEmail)
    }

    public func saveConfig(_ config: ChooseBrowserConfig) throws {
        try configManager.save(config: config)
    }

    public func availableProfiles() throws -> ChromeProfileCatalog {
        let environment = try ChromeEnvironment.discover(fileManager: fileManager)
        return try environment.loadProfileCatalog(fileManager: fileManager)
    }

    @discardableResult
    public func open(url: URL) throws -> BrowserRoutingDecision {
        let environment = try ChromeEnvironment.discover(fileManager: fileManager)
        let catalog = try environment.loadProfileCatalog(fileManager: fileManager)
        let config = try loadConfig()
        let matchedRule = config.matchingRule(for: url)
        let preferredEmail = matchedRule?.profileEmail ?? config.defaultProfileEmail
        let profileDirectoryName = try ProfileDirectoryResolver.resolveDirectory(
            preferredEmail: preferredEmail,
            catalog: catalog
        )

        let launcher = ChromeLauncher(environment: environment)
        try launcher.open(url: url, inProfileDirectory: profileDirectoryName)

        return BrowserRoutingDecision(
            url: url,
            profileDirectoryName: profileDirectoryName,
            profileEmail: preferredEmail,
            matchedRule: matchedRule
        )
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
                let catalog = try router.availableProfiles()
                if catalog.profiles.isEmpty {
                    writeLine("No Chrome profiles with metadata were found.", to: standardOutput)
                    return 0
                }

                for profile in catalog.profiles {
                    let email = profile.email ?? "(no signed-in email)"
                    let marker = profile.directoryName == catalog.lastUsedDirectoryName ? " [last used]" : ""
                    writeLine("\(profile.directoryName)\t\(email)\t\(profile.displayName ?? "(unnamed)")\(marker)", to: standardOutput)
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
        ChooseBrowser

        Usage:
          ChooseBrowser --list-profiles
          ChooseBrowser --print-config-path
          ChooseBrowser <url> [more urls...]

        When run without arguments inside the app bundle, ChooseBrowser waits for macOS URL events.
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
