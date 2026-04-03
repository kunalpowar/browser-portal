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
