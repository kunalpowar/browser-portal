# Browser Portal

Browser Portal is a small macOS utility that catches web links, matches them against your rules, and re-opens them in the right Google Chrome profile.

If a link belongs to work, it should land in your work Chrome profile. If it belongs to personal life, it should land in your personal profile. No browser chooser, no manual profile switching, no extra clicks.

## Personal Note

This is a personal project.

It was written entirely with AI assistance, and it has only been tested on macOS so far.

If you use it, treat it like a practical side project rather than polished production software.

Unsigned release builds are supported. That keeps the project cheap to ship, but macOS may warn that the app is from an unidentified developer the first time someone opens it.

## What It Does

- Supports Google Chrome only, for now.
- Routes `http` and `https` links using user-defined rules.
- Maps rules to Chrome profiles by signed-in profile email address.
- Runs quietly as a lightweight menu bar utility.
- Opens a native macOS configuration window when launched directly.
- Warns you when it is not set as the default browser.

## How It Works

1. macOS sends a web link to Browser Portal.
2. Browser Portal checks your saved rules from top to bottom.
3. The first matching rule wins.
4. The app resolves the selected email address to the real Chrome profile directory.
5. Chrome opens the link in that profile.

## Rule Matching

Rules are matched in order.

Plain URLs are treated as prefixes, so this rule:

```text
https://gitlab.com/eslfaceitgroup
```

also matches:

```text
https://gitlab.com/eslfaceitgroup/project
https://gitlab.com/eslfaceitgroup/another-repo/-/issues
```

If you want explicit wildcard matching, you can also use:

- `*` for any number of characters
- `?` for a single character

## Install From A Release

The easiest path is to download the latest `.zip` from GitHub Releases, extract it, and move `Browser Portal.app` into `Applications`.

Because the app is not signed or notarized, macOS may show a warning the first time it launches. If that happens:

1. Open `System Settings > Privacy & Security`
2. Find the blocked app warning for Browser Portal
3. Click `Open Anyway`

You can also right-click the app in Finder and choose `Open` the first time.

## Install With Homebrew

Once the Homebrew tap is published, installs look like this:

```bash
brew tap kunalpowar/tap
brew install --cask browser-portal
```

Homebrew will install the same unsigned app bundle from GitHub Releases, so the same macOS warning may still appear on first launch.

## Clone The Repo

If you want to build it yourself:

```bash
git clone <your-repo-url> browser-portal
cd browser-portal
```

If you already have the repo locally, you can skip this and just work from your existing checkout.

## Build And Test

```bash
swift test
./scripts/build-app.sh
```

That produces:

```text
dist/Browser Portal.app
```

## Install Locally

```bash
./scripts/install.sh
```

This installs:

```text
~/Applications/Browser Portal.app
```

Existing configs from the old `ChooseBrowser` name are migrated automatically to the new config location the first time the app loads them.

## Use It

1. Launch `Browser Portal.app`.
2. Add URL rules and choose the Chrome profile email for each rule.
3. Set Browser Portal as the default browser in macOS System Settings.
4. Open links normally from other apps.

Once Browser Portal is the default browser, macOS will send links to it first, and it will forward them into the matching Chrome profile.

## Config File

Browser Portal stores its config here:

```text
~/Library/Application Support/BrowserPortal/config.json
```

Example:

```json
{
  "defaultProfileEmail": "personal@example.com",
  "rules": [
    {
      "pattern": "https://mail.google.com/*",
      "profileEmail": "work@example.com"
    },
    {
      "pattern": "https://gitlab.com/my-company",
      "profileEmail": "work@example.com"
    },
    {
      "pattern": "https://github.com/my-personal-org/*",
      "profileEmail": "personal@example.com"
    }
  ]
}
```

## Helpful Commands

List detected Chrome profiles:

```bash
.build/release/BrowserPortal --list-profiles
```

Print the config path:

```bash
.build/release/BrowserPortal --print-config-path
```

Test a URL manually:

```bash
.build/release/BrowserPortal https://mail.google.com
```

## Uninstall

To remove the installed app and its local config:

```bash
./scripts/uninstall.sh
```

The app UI also includes an uninstall option.

If Browser Portal is your current default browser, switch macOS back to another browser after uninstalling it.

## Release Flow

This repo includes a GitHub Actions release workflow for unsigned builds.

To cut a release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

That workflow will:

- run `swift test`
- build `Browser Portal.app`
- package `Browser.Portal-v0.1.0.zip`
- generate a SHA256 file for the zip
- generate a ready-to-publish Homebrew cask file
- attach all three files to the GitHub Release

The release packager can also be run locally:

```bash
./scripts/make-release.sh v0.1.0
```

Generated release files land in:

```text
dist/release/
```

## Homebrew Tap Setup

Browser Portal is set up to publish into a shared tap repository:

```text
kunalpowar/homebrew-tap
```

After a release is created, copy the generated cask file into:

```text
Casks/browser-portal.rb
```

inside the tap repo, then push that repo.

If you want the cask to update automatically after each release, add a repository secret named `HOMEBREW_TAP_TOKEN` to this repo. That token should have write access to `kunalpowar/homebrew-tap`.

The cask template used to generate release-ready values lives here:

```text
packaging/homebrew/Casks/browser-portal.rb.template
```

## Current Scope

- macOS only
- Chrome only
- Local install only
- Built and tested for one machine first

That narrow scope is intentional. This tool is meant to do one job well before it grows.

## Next Steps

- Add support for more browsers, while keeping profile routing simple.
- Improve the Homebrew tap flow so the cask can be updated automatically after each release.
- Add signed and notarized builds later if the project grows enough to justify Apple Developer Program costs.
- Add import/export for rules and a cleaner onboarding flow.
- Improve rule matching with hostname/path helpers instead of raw pattern strings.
- Add a lightweight update story for people already running the app.
