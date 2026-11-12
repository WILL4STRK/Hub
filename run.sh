#!/bin/bash
# Hub: build, bundle, ad-hoc sign, install to ~/Applications and launch.
#   ./run.sh              build (universal x86_64 + arm64), install ~/Applications/Hub.app, launch
#   ./run.sh --no-launch  build dist/Hub.app only
#   ./run.sh --checks     build and run every logic check (ShelfChecks, AwningChecks, HubChecks); touches no app
#
# SwiftPM fails with Command Line Tools only ("unable to lookup item 'PlatformPath'"),
# so everything is compiled with swiftc, the same way the three original apps were.
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework ServiceManagement -framework IOKit
  -framework IOBluetooth -framework CoreAudio -framework CoreLocation -framework Carbon -framework ApplicationServices)

# lib <arch> <module> <deps...> -- <sources...>: static library + module so other code can import it.
lib() {
  local arch="$1" name="$2"; shift 2
  local deps=()
  while [ "$1" != "--" ]; do deps+=("-l$1"); shift; done
  shift
  local obj="build/$arch"
  swiftc -O -whole-module-optimization -parse-as-library -target "$arch-apple-macos13.0" -sdk "$SDK" \
    -module-name "$name" -I "$obj" -L "$obj" ${deps[@]+"${deps[@]}"} \
    -emit-library -static -o "$obj/lib$name.a" -emit-module -emit-module-path "$obj/$name.swiftmodule" "$@"
}

core_libs() {
  local arch="$1"
  mkdir -p "build/$arch"
  lib "$arch" WidgetCore -- Sources/WidgetCore/*.swift
  lib "$arch" ShelfCore -- Sources/ShelfCore/*.swift
  lib "$arch" HubCore -- Sources/HubCore/*.swift
}

if [ "${1:-}" = "--checks" ]; then
  ARCH="$(uname -m)"
  core_libs "$ARCH"
  O="build/$ARCH"
  swiftc -target "$ARCH-apple-macos13.0" -sdk "$SDK" -I "$O" -L "$O" -lShelfCore Checks/ShelfChecks/*.swift -o "$O/ShelfChecks"
  swiftc -target "$ARCH-apple-macos13.0" -sdk "$SDK" -module-name AwningChecks \
    Sources/IslandModule/Policy.swift Checks/AwningChecks/main.swift -o "$O/AwningChecks"
  swiftc -target "$ARCH-apple-macos13.0" -sdk "$SDK" -I "$O" -L "$O" -lHubCore Checks/HubChecks/*.swift -o "$O/HubChecks"
  status=0
  for c in ShelfChecks AwningChecks HubChecks; do
    echo "=== $c"
    "$O/$c" || status=1
  done
  exit $status
fi

for ARCH in x86_64 arm64; do
  echo "Building ${ARCH}..."
  core_libs "$ARCH"
  lib "$ARCH" Widgets WidgetCore -- Sources/WidgetsModule/*.swift
  lib "$ARCH" Island -- Sources/IslandModule/*.swift
  lib "$ARCH" MenuBar ShelfCore -- Sources/MenuBarModule/*.swift
  O="build/$ARCH"
  swiftc -O -whole-module-optimization -target "$ARCH-apple-macos13.0" -sdk "$SDK" -module-name Hub \
    -I "$O" -L "$O" -lWidgetCore -lShelfCore -lHubCore -lWidgets -lIsland -lMenuBar "${FRAMEWORKS[@]}" \
    Sources/Hub/*.swift -o "$O/Hub"
done
lipo -create build/x86_64/Hub build/arm64/Hub -output build/Hub
strip -x build/Hub

APP=dist/Hub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Hub "$APP/Contents/MacOS/Hub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Hub"))"

if [ "${1:-}" != "--no-launch" ]; then
  pkill -x Hub 2>/dev/null && sleep 0.5 || true
  INSTALLED="$HOME/Applications/Hub.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  open "$INSTALLED"
  echo "Launched $INSTALLED"
fi
