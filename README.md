# Hub

One macOS menu-bar app that combines three small tools: Claude Code usage widgets, a Dynamic Island style overlay at the top of the screen, and a menu-bar item manager. One app, one process, one menu-bar icon, one Settings window. Free: no accounts, no telemetry, no paid services.

Works on macOS 13 Ventura or later, on Intel and Apple Silicon. It builds with Apple's Command Line Tools only (no Xcode, no Homebrew).

## Quick setup

```sh
git clone https://github.com/WILL4STRK/Hub.git
cd Hub
./setup.sh
```

`setup.sh` checks your macOS version and the Command Line Tools, builds Hub, installs it to `~/Applications/Hub.app`, starts it and opens the Accessibility settings pane. If the Command Line Tools are missing it opens Apple's installer and asks you to run `./setup.sh` again afterwards.

| Command | What it does |
| :- | :- |
| `./setup.sh` | Check, build, install and launch |
| `./setup.sh --no-launch` | Build `dist/Hub.app` only; installs nothing |
| `./setup.sh --checks` | Run the logic checks only |
| `./run.sh` | Rebuild, reinstall and relaunch (use after changing code) |
| `./clean.sh` | Quit Hub, remove its login item, delete the build and `~/Applications/Hub.app`. Keeps your settings |
| `./clean.sh --prefs` | The same, and also deletes Hub's settings |

## The first minute

1. Open Hub's Settings from its menu-bar icon. The sidebar has five pages: Overview, Widgets, Island, Menu Bar and General.
2. Overview shows each module with its own on/off switch. Turn off what you do not want.
3. To move menu-bar items between Hidden and Visible, give Hub Accessibility access: System Settings > Privacy & Security > Accessibility > Hub on. If moving items does nothing after a rebuild, select Hub in that list, click `-`, then click `+` and add `~/Applications/Hub.app` again. A rebuild changes the app's signature, so macOS can forget the grant.
4. Nothing else is required. macOS asks for Location (weather), Bluetooth (device notices) and Automation (controlling Spotify or Music) only when a feature first needs them.

## What is in it

**Widgets.** Desktop widgets for Claude Code: total tokens, 5-hour and weekly limit rings, what is running now across your chats, and a new-chat box. They have a soft gradient halo border and follow the system light or dark appearance and accent colour. They read the files that the usage-grid mod for Claude Code writes under `~/.claude/usage-grid/`. Without that mod the widgets show "no data".

**Island.** A pill at the top of the screen (a real notch, or a simulated one on Macs without a notch). Hover to peek, click to open, Esc or click elsewhere to close. It hides in full-screen apps.
- Now playing from Spotify, Music and browsers: art, title, artist, scrubbable progress, controls, audio bars, synced lyrics
- Live activities: battery, Low Power Mode, Bluetooth and AirPods, volume and brightness notices, audio output picker, weather
- Lock-screen card (experimental, off unless you turn it on)

**Menu Bar.** Hide the menu-bar icons you do not need behind a chevron.
- Visible, Hidden and Always-hidden sections, with a settings list to move items between them and search
- Reveal by clicking the chevron, clicking or hovering an empty area, scrolling, a global shortcut, or pointing near the chevron
- Rehide after a delay or when the pointer leaves the menu bar; it waits while a menu is open
- Optional menu-bar tint, and a bar below the menu bar for items that would go behind the notch

**General.** Launch at login, appearance notes, and the report of the settings copied from the old apps. The welcome tour can be replayed from the Island page.

## Network and private APIs

Hub contacts only two services, both free and keyless, and each can be turned off on the Island page: `api.open-meteo.com` (weather, location rounded to about 1 km) and `lrclib.net` (lyrics).

Two macOS private frameworks are used, each behind its own switch:
- **MediaRemote** gives now playing for every app, browsers included. Switch it off, or if it fails to load, Hub falls back to AppleScript for Spotify and Music only.
- **SkyLight** draws the lock-screen card. It is only loaded when that card is on. Apple can change private frameworks in any macOS update, so treat both as best effort.

## Coming from the old apps

Hub replaces Claude Widgets, Awning and Shelf. On the first launch it copies their settings once into its own settings domain (`local.hub.Hub`) and shows a report in General. It never changes or deletes the old apps' settings. If one of the old apps is running, Hub pauses the matching module until that app quits, so two copies never fight over the same menu bar.

## Troubleshooting

| Problem | Fix |
| :- | :- |
| Items will not move between Hidden and Visible | Re-grant Accessibility (step 3 above). Do not touch the mouse while a move runs |
| The chevron reopens right after you close it | Turn off "Point near the chevron" on the Menu Bar page |
| Widgets say "no data" | Install the usage-grid mod for Claude Code, or turn the Widgets module off |
| No now-playing information | Open Spotify or Music once and allow Automation when macOS asks, or check the MediaRemote switch on the Island page |
| `./setup.sh` stops at the Command Line Tools | Finish Apple's installer, then run `./setup.sh` again |
| Something else | Read the log: `/usr/bin/log show --last 10m --info --style compact --predicate 'subsystem == "local.hub.Hub"'` |

## For developers

```sh
./run.sh --checks      # ShelfChecks, AwningChecks and HubChecks; touches no app
```

SwiftPM does not work with Command Line Tools only, so `run.sh` calls `swiftc` directly and builds a universal binary.

```
Sources/Hub           entry point, module manager, menu-bar icon, Settings window, login item
Sources/HubCore       settings migration plan and the rules for pausing modules (pure, tested)
Sources/WidgetsModule the widgets
Sources/IslandModule  the island
Sources/MenuBarModule the menu-bar manager
Sources/WidgetCore    pure logic for the widgets
Sources/ShelfCore     pure logic for the menu-bar manager
Checks/               logic checks, run as plain executables
```

Each module is a static library with `start()`, `stop()`, `statusText` and `settingsPage()`. `PROGRESS.md` records decisions, measurements and what is still unverified.

Signing tip: if a self-signed code-signing identity named "Hub Local Signing" exists in your login keychain, `run.sh` signs with it. The signature then stays the same across rebuilds, so the Accessibility grant survives. Otherwise Hub is ad-hoc signed.
