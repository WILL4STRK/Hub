#!/bin/bash
# Hub setup: checks your Mac, builds Hub, installs it to ~/Applications and launches it.
#   ./setup.sh              check, build, install, launch
#   ./setup.sh --no-launch  check and build dist/Hub.app only (installs nothing)
#   ./setup.sh --checks     check, then run the logic checks only (installs nothing)
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "Setup stopped: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Hub only runs on macOS."

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 13 ] || die "Hub needs macOS 13 (Ventura) or later. This Mac has $(sw_vers -productVersion)."

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
  echo "Apple's Command Line Tools are missing. A dialog will open: click Install, wait for it to finish, then run ./setup.sh again."
  xcode-select --install 2>/dev/null || true
  exit 1
fi

echo "macOS $(sw_vers -productVersion), $(uname -m), $(swiftc --version 2>&1 | head -1)"
echo "Building Hub (about a minute)..."
./run.sh "$@"

case "${1:-}" in
  --no-launch) echo "Built dist/Hub.app. Nothing was installed." ;;
  --checks) ;;
  *)
    cat <<'EOF'

Hub is running. Look for its icon in the menu bar.

One permission to grant, only if you want to move menu-bar items between Hidden and Visible:
  System Settings > Privacy & Security > Accessibility > turn Hub on
  (if it is already listed but moving items does nothing: select Hub, click -, then click + and add ~/Applications/Hub.app)
macOS asks for Location, Bluetooth and Spotify/Music control the first time a feature needs them. You can say no.

Open Hub's Settings from its menu-bar icon. To remove Hub: ./clean.sh
EOF
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
    ;;
esac
