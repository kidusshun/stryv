# Stryv for macOS

The native Swift/SwiftUI version of Stryv. Today it's a menu bar website blocker. Reports and
the rest of the original Electron app (in the repo root) will move here over time.

## What it does

- **Blocks distracting websites for a set time.** You choose sites and a duration: type
  anything from `2m`, `45 min` or `1h 30m` to `1:30`, or tap a preset (1 minute to 24 hours).
  Once a block starts there is no stop button. Quitting Stryv, deleting the app, or
  restarting the Mac doesn't end it. You can only add sites to a running block.
- **Shows a Stryv screen over blocked sites.** When the front browser tab is on a blocked
  site, a panel covers the page with the time left and a "Close this tab" button. No
  browser extension: it reads the browser window through macOS Accessibility.
- **Plays focus music in the menu bar.** YouTube's embed player (from `youtube-nocookie.com`,
  which keeps working while `youtube.com` is blocked) runs in an invisible window. Stryv's own
  controls drive it: play/pause, previous/next, seek, and a volume level that's remembered and
  re-applied on every track. An Audio/Video switch moves the player into the popover without
  interrupting playback. Stryv caches each playlist's track list from its YouTube page and
  plays it as an explicit queue, which works even where YouTube's playlist embed refuses a
  list, and while youtube.com is blocked. Playlists must be Public or Unlisted.
- **Quotes on the blocked screen.** A shuffled deck (`QuoteDeck.focus` in `StryvCore`) deals a
  new quote each time the screen appears, then rotates every 20 seconds. Every quote shows
  once before any repeats.

## How it works

```
Stryv.app (menu bar, runs as you)
   │  XPC: only "status" and "start/extend block". There is no "stop".
   ▼
com.stryv.blockd (root LaunchDaemon, installed once with your admin password)
   ├─ saves the block in /Library/Application Support/Stryv/block-state.json
   ├─ writes a managed section into /etc/hosts and flushes the DNS cache
   └─ removes the section only when the end time passes
```

The daemon is **event-driven**: it sleeps until one of these happens.

| Event | Source | Reaction |
|---|---|---|
| Daemon launch (boot, crash restart) | launchd (`RunAtLoad`, `KeepAlive`) | reload state, re-apply hosts |
| Start/extend a block | XPC from the app | save, write hosts, set the end timer |
| End time | one wall-clock timer (fires on wake if the Mac slept through it) | remove hosts entries |
| `/etc/hosts` edited | kqueue file watch | put the managed section back |
| System clock changed | `com.apple.system.clock_set` | extend the block by any forward jump |
| Wake from sleep | IOKit power notification | re-check everything |
| Anything missed | 5-minute safety-net timer | re-check everything |

Clock tampering is detected by comparing the wall clock with `CLOCK_MONOTONIC`, which keeps
counting during sleep and can't be set. Both readings are saved, so the check also works
across daemon restarts within the same boot.

After any change the daemon posts the Darwin notification `com.stryv.block.changed`. The app
refreshes then, so neither side polls.

What it doesn't stop: an admin can unload the daemon and edit `/etc/hosts` by hand. See
[../docs/blocker-tamper-hardening.md](../docs/blocker-tamper-hardening.md) for the options.

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen project definition (the `.xcodeproj` is generated, not committed) |
| `StryvCore/` | Shared logic: block engine, hosts rendering, domain rules, XPC protocol, playlists |
| `StryvBlockd/` | Root daemon: XPC listener and event sources |
| `Stryv/` | The app: menu bar popover, daemon client and installer, browser overlay, focus music |
| `StryvCoreTests/` | Swift Testing tests for the engine (temporary files and fake clocks, no root) |
| `Scripts/` | Build, test, development daemon, uninstall |

## Build and run

Requirements: Xcode, XcodeGen (`brew install xcodegen`), and the "Apple Development" signing
identity for team `PUWH8RNHCN`. The daemon only accepts XPC calls from `com.stryv.mac`
signed by that team.

```sh
macos/Scripts/build.sh --install   # build Release, copy to /Applications, launch
macos/Scripts/test.sh              # unit tests
```

The first time, open the menu bar icon and click **Install…** (admin password). For the
blocked-site screen, click **Allow** and turn on Stryv under System Settings → Privacy &
Security → Accessibility. Turn on **Open at login** so the overlay and menu bar come back
after a restart (the block itself doesn't need the app).

To work in Xcode: `cd macos && xcodegen generate && open Stryv.xcodeproj`.

### Developing without touching /etc/hosts

```sh
macos/Scripts/dev-daemon.sh start   # daemon as your user, using a fake hosts file
macos/Scripts/dev-daemon.sh app     # launch the Debug app connected to it
macos/Scripts/dev-daemon.sh hosts   # inspect the fake hosts file
macos/Scripts/dev-daemon.sh stop
```

Debug-only environment variables: `STRYV_SHOW_POPOVER=1` opens the popover on launch, and
`STRYV_SNAPSHOT_PATH=/path.png` also saves a PNG of it.

### Logs and uninstall

```sh
log stream --predicate 'subsystem == "com.stryv.blockd"'
sudo macos/Scripts/uninstall-daemon.sh   # refuses while a block is running
```

Bump `StryvConstants.daemonVersion` whenever the daemon changes. The app then offers to
reinstall it, which keeps any running block.
