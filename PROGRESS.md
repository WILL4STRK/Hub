# Hub progress

One macOS app (bundle id `local.hub.Hub`) that combines Claude Widgets, Awning and Shelf: one process, one
menu-bar icon, one Settings window (Overview, Widgets, Island, Menu Bar, General).
Target: Intel MacBook, macOS 13.7.8, Command Line Tools only (Swift 5.8.1, SDK 13.3), no Homebrew.

## Commands
- `./run.sh` build universal (x86_64 + arm64), install `~/Applications/Hub.app`, launch
- `./run.sh --no-launch` build `dist/Hub.app` only
- `./run.sh --checks` ShelfChecks + AwningChecks + HubChecks (touches no app)
- `./clean.sh` quit Hub, remove its login item, delete build/, dist/, ~/Applications/Hub.app (`--prefs` also deletes Hub's settings)

## Rules from the owner
- Originals stay untouched and running until the owner confirms Hub works:
  ~/Projects/claude-widgets, ~/Documents/Dev/awning, ~/Projects/Shelf and their installed apps. Never stop or delete them.
- Ask before committing, pushing, deleting, deploying or replacing any installed app.
- No private APIs beyond the two approved (MediaRemote, SkyLight), each behind its own switch.
- Free only, no telemetry. Open-Meteo and LRCLIB each switchable off (Island page).

## Layout
- `Sources/WidgetCore`, `Sources/ShelfCore`: pure logic copied from the originals.
- `Sources/HubCore`: settings migration plan + which old app pauses which module (pure, tested by HubChecks).
- `Sources/WidgetsModule` (module `Widgets`), `Sources/IslandModule` (module `Island`), `Sources/MenuBarModule`
  (module `MenuBar`): the three apps, each a static library with `start()`, `stop()`, `statusText`, `settingsPage()`.
- `Sources/Hub`: entry point, `ModuleManager`, menu-bar icon, Settings window, login item, migration runner.
- `Checks/`: ShelfChecks and AwningChecks copied unchanged; HubChecks new.

## Decisions
- Menu-bar hider: kept Shelf's (per-item sections with stable AX keys, arranger, search, recorder shortcuts,
  click/hover/scroll triggers, notch bar, rehide that waits for open menus, 88 checks). Awning's hider removed.
  Ported from Awning: menu-bar tint, "point near the chevron" hover (off by default; after a chevron click it is
  ignored until the pointer leaves the 80 pt zone, ShelfCore/HoverGate.swift), "rehide when pointer leaves the menu bar",
  collapse on lock/sleep. Not ported: Awning's fixed ⌃⌥⌘M (Shelf's shortcut recorder covers it; Shelf's settings win).
- Settings: one domain, `local.hub.Hub`, keys unchanged from the originals (no name clashes between the three
  apps; HubChecks covers the copy). Deviation from the plan's per-module suites: simpler, and status-item and
  window autosave positions live in the standard domain anyway.
- Migration: once (`hub.migrated.v1`), before modules start. Awning keys minus NSStatusItem*, launchAtLoginAutoApplied
  and menuBar* (except menuBarShowOnHover -> showOnHoverNearChevron, menuBarTint, menuBarTintColor); all Shelf and
  Claude Widgets keys. Awning's menuBarShowOnHover is NOT copied (owner, 2026-11-12: it reopened the chevron right
  after a click); a one-time repair (`hub.fix.hoverNearChevronOff.v1`) turned it off on this Mac. Shelf wins clashes; Hub's existing values are never overwritten. Report in General.
- Old app running -> matching module paused (Claude Widgets -> Widgets; Awning -> Island and Menu Bar; Shelf -> Menu Bar).
  Resumes by itself when the old app quits.
- Module off: Widgets hides panels and stops its 3 s reader. Island is parked (off screen, no event monitors, no
  notices, no lock card; event-driven services stay loaded). Menu Bar collapses and removes its status items,
  monitors, shortcuts and tint.
- MediaRemote switch (`useMediaRemote`, default on): off or failing to load -> AppleScript for Spotify and Music.
  SkyLight switch = the lock-screen card switch (`showOnLockScreen`); SkyLight is looked up only on first use.
- Launch at login: SMAppService, turned on once at first run (`hub.launchAtLoginApplied`), switch in General.
- Accent: widgets use the system accent colour; halo border kept on widget cards and used on Overview cards.
- Claude Widgets CPU fix: `StatusDot` pulse moved from a SwiftUI repeatForever animation (re-rendered the whole
  widget at 60 fps while a chat worked) to a Core Animation layer animation.

## Baseline (old apps, 2026-11-12, 60 s idle, `ps` cputime delta; footprint from `footprint`)
- Awning 0.69 s/60 s, 37 MB. Shelf 0.46 s/60 s, 9.8 MB. Claude Widgets 3.13 s/60 s, 41 MB. Total 4.28 s/60 s, 88 MB.

## Status
- M1 done: code copied, all modules compile.
- M2 done: Hub shell, Settings window, migration; checks ShelfChecks 88/88, AwningChecks 39/39, HubChecks 32/32.
  Universal build OK.
- 2026-11-12 09:30 owner quit the old apps. Fixed: modules did not start on quit (runningApplications still listed
  the quitting app; now skips its pid; verified only by fresh launch). Fixed: Hub icon landed in the hidden section;
  now placed right of the chevron until moved. All modules running and seen in window screenshots (widgets with halo,
  island pill with art via MediaRemote, chevron + Hub icon).
- After (Hub, all modules on, 60 s idle): 1.49 s CPU/60 s, 29 MB footprint, 6 threads. Before: 4.28 s, 88 MB.
- Fixed: chevron reopened after a click (hover mapping + HoverGate). Checks: Shelf 96/96, Awning 39/39, Hub 34/34.
- First local commit approved by the owner (2026-11-12). Local only: never push.
- Owner is testing: lock-screen card on a real lock, Accessibility grant after rebuild, modules starting when an old app quits.
- M3 in progress: Hub installed at ~/Applications/Hub.app and running (2026-11-12 09:21). Migration ran on the real
  domains: 19 values copied (report in General); old domains unchanged (Awning 15 keys, Shelf 7, Claude Widgets 2).
  All three modules show "Paused" because the old apps run. Settings window verified by window screenshot
  (dark mode, halo cards). Hub icon is offscreen (x=-14095) while the old Shelf/Awning hiders are collapsed.
  Added: reopening Hub shows Settings; Settings opens once on the first launch.
  WAITING on owner: quit Awning, Shelf and Claude Widgets; grant Hub Accessibility. Then measure and verify on screen.

## Not verified yet / needs the owner
- Everything on screen: Settings window look, Overview switches, island, widgets, menu-bar sections.
- Permissions for the new bundle: Accessibility (Shelf moves and search), Automation, Location, Bluetooth.
  Ad-hoc signing changes on every rebuild, so Accessibility may need re-granting (remove Hub with "−", add again).
- Full test needs the owner to quit Awning, Shelf and Claude Widgets (Hub pauses its modules while they run).
- Shelf's self-test (`shelf-selftest`) was not copied; Hub still answers its ShelfCommand notifications.
