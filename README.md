# TabDock

A tiny macOS menu bar app that treats your favorite web apps like real apps. Keep a list of
sites (Gmail, GitHub, Linear, a `localhost` dev server…), see at a glance which ones have a tab
open in Chrome or Safari, and jump straight to them with one click.

## Features

- **Open/closed status**: a green dot marks every app with at least one matching tab. The menu
  bar icon shows how many of your apps are currently open.
- **One-click switching**: clicking an app focuses its most relevant tab (last-used browser
  first, then the active tab, then the frontmost window). If no tab is open, it opens the app in
  the browser you used last.
- **Close all tabs**: close every tab of an app across all browsers from one hover button.
- **Smart URL matching**: `github.com` matches `github.com/...` and subdomains such as
  `gist.github.com`; `github.com/my-org` matches only paths under `/my-org`. Ports are respected,
  so `localhost:3000` and `localhost:5173` are separate apps.
- **Manage the list**: add by URL, double-click a name to rename, drag the grip to reorder,
  remove with the trash button (`⌘Z` undoes the last removal while the menu is open).
- **Launch at login**: toggle it from the gear menu.
- **Private**: favicons come from each site's own `/favicon.ico`; nothing goes to third parties.

## Install

1. Download `TabDock-<version>.dmg` from the
   [latest release](https://github.com/cuonghx-dev/TabDock/releases/latest).
2. Open it and drag **TabDock** onto **Applications**.
3. TabDock is ad-hoc signed, not notarized, so macOS blocks the first launch. Either
   right-click the app in Applications → **Open** → **Open**, or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/TabDock.app
   ```

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`) to build
- Google Chrome and/or Safari

## Build & run

```bash
./build.sh
open build/TabDock.app
```

`build.sh` compiles `Sources/*.swift` with `swiftc` (no Xcode project needed), writes the
`Info.plist` and ad-hoc signs a universal (Apple silicon + Intel) bundle. `./dmg.sh` builds the
app and packages it as `build/TabDock-<version>.dmg` (set `VERSION=x.y.z` to override).
Move `build/TabDock.app` to `/Applications` if you want to keep it.

TabDock has no Dock icon (`LSUIElement`); look for the grid icon in the menu bar.

## Permissions

TabDock reads tab URLs through AppleScript, so macOS asks once per browser for **Automation**
access ("TabDock wants to control Google Chrome / Safari"). Click **OK**.

If you denied it, the menu shows *Browser access denied*. Use **Open Settings…** to go to
**System Settings → Privacy & Security → Automation** and enable TabDock for each browser.

TabDock only talks to browsers that are already running, so polling never launches one.

## How it works

| File | Role |
| --- | --- |
| `Sources/TabDockApp.swift` | SwiftUI `MenuBarExtra` UI: app rows, add field, drag-to-reorder |
| `Sources/AppStore.swift` | State: app list, tab polling (every 2 s and on browser launch/quit), activation, persistence |
| `Sources/BrowserBridge.swift` | AppleScript bridge to list, focus and close Chrome/Safari tabs |
| `Sources/Models.swift` | `WebApp` URL normalization and matching, `Browser`, `TabRef` |

Your app list is stored at `~/Library/Application Support/TabDock/apps.json`.

## Limitations

- Supports Google Chrome and Safari only.
- Firefox is not supported (it has no AppleScript tab API).
