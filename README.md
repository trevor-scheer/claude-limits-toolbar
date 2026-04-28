# Claude Limits Toolbar

A tiny macOS menu bar app that shows your current Claude usage limits and time until reset.

The bar item shows the 5-hour limit utilization and how long until that window resets, e.g. `47% · 2h 13m`. Click to see all four limits (5-hour, 7-day, 7-day Sonnet, 7-day Opus) with progress bars and reset countdowns.

Optional notifications fire when any limit crosses configurable thresholds (default 75% / 90%).

## How it works

The app reads your Claude Code OAuth token from the macOS Keychain (the same entry Claude Code itself uses) and calls the undocumented `https://api.anthropic.com/api/oauth/usage` endpoint, which returns the same data Claude Code shows in `/limits`. No data leaves your machine.

## Requirements

- macOS 13 (Ventura) or later
- Claude Code installed and signed in (the app reads its keychain entry)
- Swift 5.9+ toolchain (Command Line Tools or full Xcode) to build from source

## Install

### Build from source

```bash
git clone https://github.com/trevorscheer/claude-limits-toolbar.git
cd claude-limits-toolbar
make app
open "dist/Claude Limits.app"
```

`make app` runs `swift build -c release` and wraps the binary into `dist/Claude Limits.app`. To install it, drag the `.app` into `/Applications`.

To produce a universal (arm64 + x86_64) binary, you need full Xcode installed:

```bash
UNIVERSAL=1 make app
```

### Pre-built DMG

Download the latest DMG from [Releases](https://github.com/trevorscheer/claude-limits-toolbar/releases), open it, and drag `Claude Limits.app` to `/Applications`.

The DMG is **unsigned** — Gatekeeper will refuse to launch it on first run. To allow it:

```bash
xattr -dr com.apple.quarantine "/Applications/Claude Limits.app"
```

…or right-click the app, choose **Open**, and confirm in the dialog.

### Homebrew cask

```bash
brew install --cask trevorscheer/tap/claude-limits-toolbar
```

(Tap not yet published — coming soon.)

## Configuration

Click the menu bar item, then **Preferences…** to set:

- **Alert thresholds** — toggle low/high alerts and pick percentages (50–95%, default 75/90)
- **Refresh interval** — 60 s, 2 min (default), 5 / 10 / 15 / 30 min, or 1 hour
- **Launch at login** — opt-in checkbox, on by default after first launch

Settings are stored in `~/Library/Preferences/com.trevorscheer.claude-limits-toolbar.plist`.

## Development

```bash
swift build      # debug build
swift test       # run the test suite (Swift Testing)
make app         # release build + .app bundle in dist/
make run         # build the .app and open it
make clean       # wipe .build and dist/
```

## Troubleshooting

**The bar shows ⚠️ with "No Claude Code credentials".**
Sign in to Claude Code (`claude /login`) and click Refresh in the popover.

**The bar shows ⚠️ with "token rejected (401)".**
Your Claude Code session expired or was revoked. Run `claude /login` again.

**The bar is stuck on `…`.**
First fetch is in flight. If it stays this way, check **Console.app** for `ClaudeLimitsToolbar` log lines.

**No notifications appear.**
macOS prompts for notification permission on first launch. If you missed the prompt, allow notifications for **Claude Limits** in **System Settings → Notifications**.

**Gatekeeper says the app is damaged or unsigned.**
The pre-built DMG is unsigned. See the install section above for the `xattr` command.

## License

MIT
