# Browser Portal

## ❓ What It Does

Browser Portal is a small macOS utility that catches web links and re-opens them in the right Google Chrome profile based on your rules.

- Route links into different Chrome profiles by signed-in profile email
- Handle normal `http` and `https` links
- Run as a lightweight menu bar app
- Open a native macOS configuration window for editing rules

## ⚠️ Warning

This is a personal project.

It was written entirely with AI assistance and has only been tested on macOS.

It is also currently unsigned, so macOS may show extra security warnings on first launch.

## 🚀 Installation

### 🍺 Option 1: Homebrew

```bash
brew tap kunalpowar/tap
brew install --cask browser-portal
```

Because the app is unsigned, macOS may block the first launch.

If that happens, try one of these:

1. Right-click `Browser Portal.app` in Finder and choose `Open`
2. Or remove quarantine manually:

```bash
sudo xattr -dr com.apple.quarantine "/Applications/Browser Portal.app"
```

### 🛠️ Option 2: Build From Source

```bash
git clone https://github.com/kunalpowar/browser-portal.git
cd browser-portal
swift test
./scripts/install.sh
```

That installs the app locally and avoids the Homebrew path entirely.

## 📝 Caveats

- Chrome only
- macOS only
- No support for other browsers yet
- Unsigned builds, so first-launch friction is expected

## Link Handling and Logs

Chrome's last-used-profile mode uses the native macOS URL open request. Rules for a specific profile use the native macOS application launch request with a new launch instance so Chrome receives the profile and URL arguments, including when it is already running. Chrome forwards the command to its existing process. Browser Portal also yields focus to Chrome on macOS 14 and later and requests activation of an existing Chrome instance after macOS accepts the launch. Launch acceptance does not confirm that the tab has appeared.

The event log records dispatch time, not the time when a tab appears or a page loads. Log writes run in the background. The log is limited to 1 MiB, and the Logs tab shows up to 1,000 recent entries. URL paths, credentials, queries, and fragments are removed from log messages. Authentication sessions are logged by request ID.
