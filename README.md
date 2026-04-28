# Claude Usage Bar

A tiny macOS menu bar app that shows your Claude.ai usage at a glance: 5-hour session, weekly, and Sonnet weekly limits.

![icon](app/icon_1024.png)

## Features

- 🤖 Robot icon with current session percentage and a color progress bar (green / orange / red)
- Adapts to light, dark, and dynamic menu bar appearances
- Click for a popover with all three usage windows and reset times
- Background refresh every ~15 min (with jitter), plus refresh on wake and on open
- Optional notifications at 25% / 50% / 75% / 90% session usage
- Open at login

## Install

Requires macOS with the Swift toolchain (Xcode command line tools). Install them once with `xcode-select --install` if you don't have them.

```sh
git clone git@github.com:jesusalber1/claude-usage-bar.git
cd claude-usage-bar
bash app/build.sh
cp -R app/ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
```

## Setup

The app needs your Claude.ai session cookie to read your usage from the same private endpoint the website uses.

1. Open [claude.ai](https://claude.ai) in your browser, signed in.
2. Open DevTools → Application/Storage → Cookies → `https://claude.ai`.
3. Copy the entire `Cookie` header value (or just `sessionKey=...; lastActiveOrg=...`).
4. Click the menu bar icon → Settings → paste the cookie.

Your cookie is stored locally in `UserDefaults` and is only sent to `claude.ai`.

## Open at Login

To have Claude Usage Bar launch automatically when you sign in, click the menu bar icon → Settings and toggle **Open at Login**. This uses macOS's `SMAppService`, so you can also manage it from System Settings → General → Login Items.

## Privacy

This app talks to `claude.ai` and nothing else. No telemetry, no analytics, no third-party servers.

## License

MIT
