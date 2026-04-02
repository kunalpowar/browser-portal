# ChooseBrowser

ChooseBrowser is a tiny macOS URL handler that always opens links in Google Chrome, but picks the Chrome profile from rules you define.

It is meant to become your default browser app on macOS. When any `http` or `https` URL is opened, macOS launches ChooseBrowser, ChooseBrowser matches the URL against your rules, and then launches Chrome with the right profile directory.

ChooseBrowser now behaves like a menu bar utility. If you launch `ChooseBrowser.app` directly, it opens a configuration window where you can add, remove, and save rules. After launch, it stays in the menu bar, and clicking the menu bar icon reopens the window.

## What it does

- Supports Google Chrome only.
- Maps URL wildcard patterns to Chrome profile emails.
- Reads the actual Chrome profile directory names from Chrome's `Local State` file, so you can configure rules with stable emails instead of `Profile 3`.
- Creates a starter config automatically on first run.
- Stays in the macOS menu bar so it can keep handling links in the background.

## Config

The config file lives at:

```text
~/Library/Application Support/ChooseBrowser/config.json
```

Example:

```json
{
  "defaultProfileEmail": "kunalpowar1203@gmail.com",
  "rules": [
    {
      "pattern": "https://mail.google.com/*",
      "profileEmail": "kunal@stronk.works"
    },
    {
      "pattern": "https://*.stronk.works/*",
      "profileEmail": "kunal@stronk.works"
    },
    {
      "pattern": "https://github.com/my-personal-org/*",
      "profileEmail": "kunalpowar1203@gmail.com"
    }
  ]
}
```

Rules are evaluated in order. The first matching pattern wins.

Pattern syntax:

- `*` matches any number of characters.
- `?` matches a single character.
- Match against the full URL string.

## Build and install

```bash
./scripts/install.sh
```

That installs the app to `~/Applications/ChooseBrowser.app`.

You can also just build the app bundle without installing it:

```bash
./scripts/build-app.sh
```

To uninstall the installed app and remove its local config data:

```bash
./scripts/uninstall.sh
```

The in-app configuration window also includes an uninstall button.
If ChooseBrowser is your current default browser, switch macOS back to another browser after uninstalling it.

## Set it as your default browser

After installing, set `ChooseBrowser` as the default browser app in macOS System Settings.

## Helpful commands

List Chrome profiles and the emails currently attached to them:

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
