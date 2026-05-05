#!/usr/bin/env bash
# Wipes Launch Services registrations for run.rosie.dacx and forces macOS to
# re-register the currently installed Dacx.app from scratch. Use this on test
# machines after upgrading between Dacx releases if "Open With" launches the
# wrong build, or if the custom document icon doesn't refresh.
#
# WARNING: On macOS versions that still support `lsregister -kill`, this script
# uses a SYSTEM-WIDE Launch Services reset. All other apps then silently
# re-register themselves within a few seconds. On newer macOS versions where
# `-kill` is removed, the script uses a targeted Dacx unregister + LS rebuild
# path instead.
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

COPY_COUNT=0
COPIES=()

add_unique_copy() {
  local candidate="$1"
  [[ -z "$candidate" ]] && return
  if [[ "$COPY_COUNT" -gt 0 ]]; then
    for existing in "${COPIES[@]}"; do
      if [[ "$existing" == "$candidate" ]]; then
        return
      fi
    done
  fi
  COPIES+=("$candidate")
  COPY_COUNT=$((COPY_COUNT + 1))
}

echo "==> Quitting Dacx (if running)..."
if pgrep -x Dacx >/dev/null 2>&1; then
  osascript -e 'tell application "Dacx" to quit' 2>/dev/null || true
  sleep 1
  pkill -x Dacx 2>/dev/null || true
fi

echo "==> Locating every copy of $BUNDLE_ID on this machine..."
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  add_unique_copy "$line"
done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null)

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  add_unique_copy "$line"
done < <(
  "$LSREGISTER" -dump 2>/dev/null | awk -v id="$BUNDLE_ID" '
    /^path:[[:space:]]*/ {
      path = $0
      sub(/^path:[[:space:]]*/, "", path)
      sub(/[[:space:]]*\(0x[0-9a-fA-F]+\)$/, "", path)
      next
    }
    /^identifier:[[:space:]]*/ {
      ident = $0
      sub(/^identifier:[[:space:]]*/, "", ident)
      if (ident == id && path != "") print path
      path = ""
    }
  '
)

for copy in ${COPIES[@]+"${COPIES[@]}"}; do
  echo "    $copy"
done
if [[ "$COPY_COUNT" -eq 0 ]]; then
  echo "    (Spotlight found no copies. Check /Applications, ~/Downloads,"
  echo "    ~/Desktop, and any mounted DMGs manually.)"
fi

VOLUMES_TO_EJECT=()
for copy in ${COPIES[@]+"${COPIES[@]}"}; do
  if [[ "$copy" == /Volumes/* ]]; then
    volume="$(echo "$copy" | awk -F/ '{print "/"$2"/"$3}')"
    already_listed=0
    for v in ${VOLUMES_TO_EJECT[@]+"${VOLUMES_TO_EJECT[@]}"}; do
      if [[ "$v" == "$volume" ]]; then
        already_listed=1
        break
      fi
    done
    if [[ "$already_listed" -eq 0 ]]; then
      VOLUMES_TO_EJECT+=("$volume")
    fi
  fi
done

if [[ "${#VOLUMES_TO_EJECT[@]}" -gt 0 ]]; then
  echo
  echo "==> Ejecting mounted Dacx DMG volumes (otherwise LS keeps re-registering them)..."
  for volume in "${VOLUMES_TO_EJECT[@]}"; do
    echo "    Ejecting $volume"
    diskutil eject "$volume" >/dev/null 2>&1 \
      || hdiutil detach "$volume" -force >/dev/null 2>&1 \
      || echo "    (failed to eject $volume; eject it manually in Finder)"
  done
fi

echo
if [[ "$COPY_COUNT" -gt 0 ]]; then
  echo "==> Unregistering discovered Dacx copies from Launch Services..."
  for copy in "${COPIES[@]}"; do
    "$LSREGISTER" -u "$copy" >/dev/null 2>&1 || true
  done
  echo
fi

echo "==> Refreshing Launch Services registrations..."
if "$LSREGISTER" -h 2>&1 | grep -q -- " -kill"; then
  echo "    Using legacy full reset mode (-kill supported)."
  "$LSREGISTER" -kill -r -domain local -domain system -domain user
else
  echo "    -kill not supported on this macOS; using targeted rebuild mode."
  "$LSREGISTER" -gc
  "$LSREGISTER" -r -apps local,system,user
fi

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
REGISTRATIONS="$(
  "$LSREGISTER" -dump 2>/dev/null | awk -v id="$BUNDLE_ID" '
    /^identifier:[[:space:]]*/ {
      ident = $0
      sub(/^identifier:[[:space:]]*/, "", ident)
      if (ident == id) count++
    }
    END {
      print count + 0
    }
  '
)"
echo "==> Done. Launch Services now has $REGISTRATIONS registration(s) for $BUNDLE_ID."
if [[ "$REGISTRATIONS" -gt 1 ]]; then
  echo "    WARNING: more than one registration is still present. Remove any"
  echo "    extra Dacx.app copies shown above (including local build outputs),"
  echo "    then re-run this script."
  exit 2
fi

