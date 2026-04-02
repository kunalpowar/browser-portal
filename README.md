# ChooseBrowser

ChooseBrowser is a tiny macOS utility that catches web links, matches them against your rules, and re-opens them in the correct Google Chrome profile.

The whole point is simple: if a link belongs to work, open it in your work Chrome profile. If it belongs to personal stuff, open it in your personal profile. No browser chooser, no manual switching, no extra clicks.

## Personal Note

This is a personal project.

It was written entirely with AI assistance, and it has only been tested on macOS so far.

If you use it, treat it like a practical side-project tool rather than polished production software.

## What It Does

- Supports Google Chrome only.
- Routes `http` and `https` links based on user-defined rules.
- Maps rules to Chrome profiles using profile email addresses instead of brittle names like `Profile 3`.
- Runs as a lightweight menu bar utility.
- Opens a native macOS config window when launched directly.

## How It Works

1. macOS sends a web link to ChooseBrowser.
2. ChooseBrowser checks your saved rules from top to bottom.
3. It resolves the matching email to the real Chrome profile directory.
4. It launches Chrome with that profile and opens the URL.

## Rule Matching

Rules are matched in order. The first match wins.

Plain URLs are treated as prefixes.

That means this rule:

```text
https://gitlab.com/eslfaceitgroup
```

will also match:

```text
https://gitlab.com/eslfaceitgroup/project
https://gitlab.com/eslfaceitgroup/another-repo/-/issues
```

If you want explicit wildcard matching, you can also use:

- `*` for any number of characters
- `?` for a single character

## Config File

ChooseBrowser stores its config here:

```text
~/Library/Application Support/ChooseBrowser/config.json
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

## Install

Build and install the app:

```bash
./scripts/install.sh
```

This installs:

```text
~/Applications/ChooseBrowser.app
```

After that, set `ChooseBrowser` as your default browser in macOS System Settings.

ChooseBrowser also shows a warning in the app UI if it is not currently set as the default browser.

## Build Only

If you only want the app bundle:

```bash
./scripts/build-app.sh
```

## Uninstall

To remove the installed app and its local config:

```bash
./scripts/uninstall.sh
```

The app UI also includes an uninstall option.

If ChooseBrowser is your current default browser, switch macOS back to another browser after uninstalling it.

## Helpful Commands

List detected Chrome profiles:

```bash
.build/release/ChooseBrowser --list-profiles
```

Print the config path:

```bash
.build/release/ChooseBrowser --print-config-path
```

Test a URL manually:

```bash
.build/release/ChooseBrowser https://mail.google.com
```

## Current Scope

- macOS only
- Chrome only
- Built for one machine first, then cleaned up

That narrow scope is intentional. This tool is meant to do one job well.
