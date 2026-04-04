import Foundation
import Testing
@testable import ChooseBrowserCore

@Test
func wildcardMatcherSupportsBasicGlobPatterns() {
    #expect(WildcardMatcher.matches("https://*.example.com/*", value: "https://docs.example.com/page"))
    #expect(WildcardMatcher.matches("https://example.com/?", value: "https://example.com/a"))
    #expect(!WildcardMatcher.matches("https://example.com/*", value: "https://other.com/a"))
}

@Test
func ruleMatcherTreatsPlainUrlsAsPrefixes() {
    #expect(RuleMatcher.matches("https://gitlab.com/eslfaceitgroup", value: "https://gitlab.com/eslfaceitgroup"))
    #expect(RuleMatcher.matches("https://gitlab.com/eslfaceitgroup", value: "https://gitlab.com/eslfaceitgroup/browser/repo"))
    #expect(!RuleMatcher.matches("https://gitlab.com/eslfaceitgroup", value: "https://gitlab.com/other-group/project"))
}

@Test
func configReturnsFirstMatchingRule() throws {
    let config = ChooseBrowserConfig(
        defaultProfileEmail: "personal@example.com",
        rules: [
            URLRule(pattern: "https://github.com/my-org/*", profileEmail: "work@example.com"),
            URLRule(pattern: "https://github.com/*", profileEmail: "personal@example.com", browser: .brave),
        ]
    )

    let url = try #require(URL(string: "https://github.com/my-org/repo"))
    let rule = try #require(config.matchingRule(for: url))

    #expect(rule.profileEmail == "work@example.com")
}

@Test
func routingPlanFallsBackWhenNoRuleMatches() throws {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let configURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
    let configManager = ConfigManager(fileManager: fileManager, configurationFileURL: configURL)
    let environmentProvider = makeTemporaryEnvironmentProvider(in: directoryURL)
    let router = BrowserRouter(
        fileManager: fileManager,
        configManager: configManager,
        environmentProvider: environmentProvider
    )

    defer {
        try? fileManager.removeItem(at: directoryURL)
    }

    try configManager.save(
        config: ChooseBrowserConfig(
            unmatchedLinkBehaviorMode: .lastActiveBrowser,
            defaultProfileEmail: "personal@example.com",
            rules: [
                URLRule(pattern: "https://work.example.com/*", profileEmail: "work@example.com")
            ]
        )
    )

    let url = try #require(URL(string: "https://github.com/openai"))
    let plan = try router.plan(for: url)

    #expect(plan == .fallbackToSystem(url))
}

@Test
func routingPlanUsesConfiguredBrowserProfileForUnmatchedLinks() throws {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let configURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
    let configManager = ConfigManager(fileManager: fileManager, configurationFileURL: configURL)
    let localStateURL = directoryURL
        .appending(path: "Google", directoryHint: .isDirectory)
        .appending(path: "Chrome", directoryHint: .isDirectory)
        .appending(path: "Local State", directoryHint: .notDirectory)
    let router = BrowserRouter(
        fileManager: fileManager,
        configManager: configManager,
        environmentProvider: makeTemporaryEnvironmentProvider(in: directoryURL, localStateURLs: [.chrome: localStateURL])
    )

    defer {
        try? fileManager.removeItem(at: directoryURL)
    }

    let localStateDirectoryURL = localStateURL.deletingLastPathComponent()

    try fileManager.createDirectory(at: localStateDirectoryURL, withIntermediateDirectories: true)

    try Data(
        """
        {
          "profile": {
            "last_used": "Default",
            "info_cache": {
              "Default": {
                "name": "Personal",
                "user_name": "personal@example.com"
              },
              "Profile 4": {
                "name": "Work",
                "user_name": "work@example.com"
              }
            }
          }
        }
        """.utf8
    )
    .write(to: localStateURL, options: .atomic)

    try configManager.save(
        config: ChooseBrowserConfig(
            unmatchedLinkBehaviorMode: .browserProfile,
            defaultBrowser: .chrome,
            defaultProfileEmail: "work@example.com",
            rules: []
        )
    )

    let url = try #require(URL(string: "https://github.com/openai"))
    let plan = try router.plan(for: url)

    guard case let .routeInManagedBrowser(decision) = plan else {
        Issue.record("Expected unmatched links to route into a managed browser.")
        return
    }

    #expect(decision.matchedRule == nil)
    #expect(decision.browser == .chrome)
    #expect(decision.profileEmail == "work@example.com")
    #expect(decision.profileDirectoryName == "Profile 4")
}

@Test
func routingPlanUsesMatchedRuleBrowser() throws {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let configURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
    let configManager = ConfigManager(fileManager: fileManager, configurationFileURL: configURL)
    let braveLocalStateURL = directoryURL
        .appending(path: "BraveSoftware", directoryHint: .isDirectory)
        .appending(path: "Brave-Browser", directoryHint: .isDirectory)
        .appending(path: "Local State", directoryHint: .notDirectory)
    let router = BrowserRouter(
        fileManager: fileManager,
        configManager: configManager,
        environmentProvider: makeTemporaryEnvironmentProvider(in: directoryURL, localStateURLs: [.brave: braveLocalStateURL])
    )

    defer {
        try? fileManager.removeItem(at: directoryURL)
    }

    try fileManager.createDirectory(at: braveLocalStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(
        """
        {
          "profile": {
            "last_used": "Default",
            "info_cache": {
              "Default": {
                "name": "Brave Work",
                "user_name": "work@example.com"
              }
            }
          }
        }
        """.utf8
    )
    .write(to: braveLocalStateURL, options: .atomic)

    try configManager.save(
        config: ChooseBrowserConfig(
            defaultProfileEmail: nil,
            rules: [
                URLRule(pattern: "https://gitlab.example.com/*", profileEmail: "work@example.com", browser: .brave)
            ]
        )
    )

    let plan = try router.plan(for: try #require(URL(string: "https://gitlab.example.com/group/repo")))

    guard case let .routeInManagedBrowser(decision) = plan else {
        Issue.record("Expected a managed browser route.")
        return
    }

    #expect(decision.browser == .brave)
    #expect(decision.profileEmail == "work@example.com")
    #expect(decision.profileDirectoryName == "Default")
}

private func makeTemporaryEnvironmentProvider(
    in directoryURL: URL,
    localStateURLs: [ManagedBrowser: URL] = [:]
) -> (ManagedBrowser) throws -> ChromiumEnvironment {
    { browser in
        let appURL = directoryURL.appending(path: browser.applicationName, directoryHint: .isDirectory)
        let binaryURL = appURL
            .appending(path: "Contents", directoryHint: .isDirectory)
            .appending(path: "MacOS", directoryHint: .isDirectory)
            .appending(path: browser.executableName, directoryHint: .notDirectory)

        return ChromiumEnvironment(
            browser: browser,
            appURL: appURL,
            binaryURL: binaryURL,
            localStateURL: localStateURLs[browser] ?? directoryURL.appending(path: "\(browser.rawValue)-Local State", directoryHint: .notDirectory)
        )
    }
}

@Test
func chromiumLocalStateParserExtractsProfilesAndLastUsedDirectory() throws {
    let data = Data(
        """
        {
          "profile": {
            "last_used": "Profile 3",
            "info_cache": {
              "Default": {
                "name": "Personal",
                "user_name": "personal@example.com",
                "hosted_domain": "NO_HOSTED_DOMAIN",
                "is_managed": 0
              },
              "Profile 3": {
                "name": "Work",
                "user_name": "work@example.com",
                "hosted_domain": "example.com",
                "is_managed": 1
              }
            }
          }
        }
        """.utf8
    )

    let catalog = try ChromiumLocalStateParser.parse(data: data)

    #expect(catalog.lastUsedDirectoryName == "Profile 3")
    #expect(catalog.directoryName(forEmail: "work@example.com") == "Profile 3")
    #expect(catalog.email(forDirectoryName: "Default") == "personal@example.com")
    #expect(catalog.availableEmails == ["personal@example.com", "work@example.com"])
}

@Test
func resolverFallsBackToLastUsedDirectoryWhenNoEmailProvided() throws {
    let catalog = ChromiumProfileCatalog(
        lastUsedDirectoryName: "Profile 7",
        profiles: [
            ChromiumProfile(
                directoryName: "Profile 7",
                displayName: "Default",
                email: "default@example.com",
                hostedDomain: nil,
                isManaged: false
            )
        ]
    )

    let directory = try ProfileDirectoryResolver.resolveDirectory(preferredEmail: nil, catalog: catalog, browser: .chrome)

    #expect(directory == "Profile 7")
}

@Test
func resolverThrowsHelpfulErrorForUnknownEmail() throws {
    let catalog = ChromiumProfileCatalog(
        lastUsedDirectoryName: "Default",
        profiles: [
            ChromiumProfile(
                directoryName: "Default",
                displayName: "Personal",
                email: "personal@example.com",
                hostedDomain: nil,
                isManaged: false
            )
        ]
    )

    #expect(throws: ChooseBrowserError.self) {
        _ = try ProfileDirectoryResolver.resolveDirectory(preferredEmail: "work@example.com", catalog: catalog, browser: .chrome)
    }
}

@Test
func configManagerSavesAndReloadsNormalizedConfig() throws {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let configURL = directoryURL.appending(path: "config.json", directoryHint: .notDirectory)
    let manager = ConfigManager(fileManager: fileManager, configurationFileURL: configURL)

    defer {
        try? fileManager.removeItem(at: directoryURL)
    }

    let config = ChooseBrowserConfig(
        defaultBrowser: .brave,
        defaultProfileEmail: " personal@example.com ",
        rules: [
            URLRule(pattern: " https://example.com/* ", profileEmail: " work@example.com ", browser: .brave)
        ]
    )

    try manager.save(config: config)
    let reloaded = try manager.loadOrCreate(defaultProfileEmail: nil)

    #expect(reloaded.defaultProfileEmail == "personal@example.com")
    #expect(reloaded.defaultBrowser == .brave)
    #expect(reloaded.rules == [URLRule(pattern: "https://example.com/*", profileEmail: "work@example.com", browser: .brave)])
}

@Test
func legacyChromeConfigStillDecodes() throws {
    let data = Data(
        """
        {
          "unmatchedLinkBehaviorMode": "chromeProfile",
          "defaultProfileEmail": "work@example.com",
          "rules": [
            {
              "pattern": "https://example.com/*",
              "profileEmail": "work@example.com"
            }
          ]
        }
        """.utf8
    )

    let config = try JSONDecoder().decode(ChooseBrowserConfig.self, from: data)

    #expect(config.effectiveUnmatchedLinkBehaviorMode == .browserProfile)
    #expect(config.effectiveDefaultBrowser == .chrome)
    #expect(config.rules.first?.browser == .chrome)
}
