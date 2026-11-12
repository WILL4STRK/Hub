#!/bin/bash
# Remove Hub: quit it, remove its login item, delete build output and ~/Applications/Hub.app.
#   ./clean.sh          keeps Hub's settings (domain local.hub.Hub)
#   ./clean.sh --prefs  also deletes Hub's settings, so the next launch copies the old apps' settings again
# Never touches Awning, Shelf or Claude Widgets, or their settings.
set -euo pipefail
cd "$(dirname "$0")"
INSTALLED="$HOME/Applications/Hub.app"
pkill -x Hub 2>/dev/null && sleep 0.5 || true
for app in "$INSTALLED" dist/Hub.app; do
  if [ -x "$app/Contents/MacOS/Hub" ]; then "$app/Contents/MacOS/Hub" --unregister-login || true; break; fi
done
rm -rf build dist "$INSTALLED"
if [ "${1:-}" = "--prefs" ]; then defaults delete local.hub.Hub 2>/dev/null || true; echo "Hub settings deleted."; fi
echo "Hub quit, login item removed, build/, dist/ and ~/Applications/Hub.app deleted."
