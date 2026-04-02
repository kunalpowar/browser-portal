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
func configReturnsFirstMatchingRule() throws {
    let config = ChooseBrowserConfig(
        defaultProfileEmail: "personal@example.com",
        rules: [
            URLRule(pattern: "https://github.com/my-org/*", profileEmail: "work@example.com"),
            URLRule(pattern: "https://github.com/*", profileEmail: "personal@example.com"),
        ]
    )

    let url = try #require(URL(string: "https://github.com/my-org/repo"))
    let rule = try #require(config.matchingRule(for: url))

    #expect(rule.profileEmail == "work@example.com")
}

@Test
func chromeLocalStateParserExtractsProfilesAndLastUsedDirectory() throws {
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

    let catalog = try ChromeLocalStateParser.parse(data: data)

    #expect(catalog.lastUsedDirectoryName == "Profile 3")
    #expect(catalog.directoryName(forEmail: "work@example.com") == "Profile 3")
    #expect(catalog.email(forDirectoryName: "Default") == "personal@example.com")
    #expect(catalog.availableEmails == ["personal@example.com", "work@example.com"])
}

@Test
func resolverFallsBackToLastUsedDirectoryWhenNoEmailProvided() throws {
    let catalog = ChromeProfileCatalog(
        lastUsedDirectoryName: "Profile 7",
        profiles: [
            ChromeProfile(
                directoryName: "Profile 7",
                displayName: "Default",
                email: "default@example.com",
                hostedDomain: nil,
                isManaged: false
            )
        ]
    )

    let directory = try ProfileDirectoryResolver.resolveDirectory(preferredEmail: nil, catalog: catalog)

    #expect(directory == "Profile 7")
}

@Test
func resolverThrowsHelpfulErrorForUnknownEmail() throws {
    let catalog = ChromeProfileCatalog(
        lastUsedDirectoryName: "Default",
        profiles: [
            ChromeProfile(
                directoryName: "Default",
                displayName: "Personal",
                email: "personal@example.com",
                hostedDomain: nil,
                isManaged: false
            )
        ]
    )

    #expect(throws: ChooseBrowserError.self) {
        _ = try ProfileDirectoryResolver.resolveDirectory(preferredEmail: "work@example.com", catalog: catalog)
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
        defaultProfileEmail: " personal@example.com ",
        rules: [
            URLRule(pattern: " https://example.com/* ", profileEmail: " work@example.com ")
        ]
    )

    try manager.save(config: config)
    let reloaded = try manager.loadOrCreate(defaultProfileEmail: nil)

    #expect(reloaded.defaultProfileEmail == "personal@example.com")
    #expect(reloaded.rules == [URLRule(pattern: "https://example.com/*", profileEmail: "work@example.com")])
}
