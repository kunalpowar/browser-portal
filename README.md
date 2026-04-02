# Browser Portal

Browser Portal is a small macOS utility that catches web links, matches them against your rules, and re-opens them in the right Google Chrome profile.

If a link belongs to work, it should land in your work Chrome profile. If it belongs to personal life, it should land in your personal profile. No browser chooser, no manual profile switching, no extra clicks.

## Personal Note

This is a personal project.

It was written entirely with AI assistance, and it has only been tested on macOS so far.

If you use it, treat it like a practical side project rather than polished production software.

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

## Clone The Repo

There is no packaged release flow yet, so today the intended path is: clone, build, install locally.

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

## Current Scope

- macOS only
- Chrome only
- Local install only
- Built and tested for one machine first

That narrow scope is intentional. This tool is meant to do one job well before it grows.

## Next Steps

- Add support for more browsers, while keeping profile routing simple.
- Package signed installable app builds instead of relying on local scripts.
- Add import/export for rules and a cleaner onboarding flow.
- Improve rule matching with hostname/path helpers instead of raw pattern strings.
- Add release automation, versioned builds, and a lightweight update story.
