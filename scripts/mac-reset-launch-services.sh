#!/usr/bin/env bash
# Wipes Launch Services registrations for run.rosie.dacx and forces macOS to
# re-register the currently installed Dacx.app from scratch. Use this on test
# machines after upgrading between Dacx releases if "Open With" launches the
# wrong build, or if the custom document icon doesn't refresh.
#
# WARNING: `lsregister -kill -r` wipes the SYSTEM-WIDE Launch Services
# database, not just Dacx's entries. All other apps will silently re-register
# themselves within a few seconds. This is normal LS maintenance and is the
# documented way to clear stale records, but you may briefly see "Open With"
# menus look sparse for other apps until macOS rebuilds the index.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only runs on macOS." >&2
  exit 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
BUNDLE_ID="run.rosie.dacx"

if [[ ! -x "$LSREGISTER" ]]; then
  echo "ERROR: lsregister not found at $LSREGISTER" >&2
  echo "This macOS version may have moved it. Aborting." >&2
  exit 1
fi

echo "==> Quitting Dacx (if running)..."
if pgrep -x Dacx >/dev/null 2>&1; then
  osascript -e 'tell application "Dacx" to quit' 2>/dev/null || true
  sleep 1
  pkill -x Dacx 2>/dev/null || true
fi

echo "==> Locating every copy of $BUNDLE_ID on this machine..."
COPY_COUNT=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "    $line"
  COPY_COUNT=$((COPY_COUNT + 1))
done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null)
if [[ "$COPY_COUNT" -eq 0 ]]; then
  echo "    (Spotlight found no copies. Check /Applications, ~/Downloads,"
  echo "    ~/Desktop, and any mounted DMGs manually.)"
fi

echo
echo "==> Wiping Launch Services database (all apps will silently re-register)..."
"$LSREGISTER" -kill -r -domain local -domain system -domain user

echo "==> Restarting Finder, Dock, and cfprefsd to refresh icon caches..."
killall Finder Dock cfprefsd 2>/dev/null || true

if [[ -d /Applications/Dacx.app ]]; then
  echo
  echo "==> Re-registering /Applications/Dacx.app..."
  "$LSREGISTER" -f /Applications/Dacx.app
  echo
  if [[ -f /Applications/Dacx.app/Contents/Info.plist ]]; then
    SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
      /Applications/Dacx.app/Contents/Info.plist 2>/dev/null || echo '?')"
    BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' \
      /Applications/Dacx.app/Contents/Info.plist 2>/dev/null || echo '?')"
    echo "    Installed version: $SHORT_VERSION"
    echo "    Build number:      $BUILD_VERSION"
  fi
fi

echo
REGISTRATIONS="$("$LSREGISTER" -dump 2>/dev/null | grep -c "identifier:.*$BUNDLE_ID" || true)"
echo "==> Done. Launch Services now has $REGISTRATIONS registration(s) for $BUNDLE_ID."
if [[ "$REGISTRATIONS" -gt 1 ]]; then
  echo "    WARNING: more than one registration is still present. Make sure"
  echo "    you've deleted every Dacx.app copy mdfind reported above, then"
  echo "    re-run this script."
  exit 2
fi

