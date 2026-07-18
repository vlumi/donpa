#!/usr/bin/env bash
# Launch the app in DEMO mode — seeded data + a fixed blue accent, isolated
# storage (-uitest-clean routes EVERY store to an ephemeral suite, never the
# real player's data), starting in Light. For App Store screenshots: prefer
# `make shots` (guided, captures for you); this script is the bare launcher.
#   PLATFORM=iphone|ipad|mac  which target                (default iphone)
#   DEMO_LANG=en|fi|ja        UI language for this launch (default en)
# When boards hand-staged via `make demo-freeze` are committed under
# Scripts/asc/demo-saves, they're copied into the app's demo save dir before
# launch (the sandboxed app can't read the repo itself).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${PLATFORM:-iphone}"
DEMO_LANG="${DEMO_LANG:-en}"
case "$DEMO_LANG" in
    en | fi | ja) ;;
    *) echo "DEMO_LANG must be en | fi | ja (got '$DEMO_LANG')" >&2; exit 2 ;;
esac
ARGS=(-uitest-clean -uitest-demo -AppleLanguages "($DEMO_LANG)")
BUNDLE="fi.misaki.donpa"
COMMITTED_SAVES="Scripts/asc/demo-saves"

pick_udid() {  # $1 = name pattern
    xcrun simctl list devices available | grep -E "$1" \
        | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | tail -1
}

# Wipe the app's fixed demo save dir ($1) and, if hand-staged boards are
# committed, copy them in and mark the dir authoritative (-uitest-staged-saves).
stage_saves() {
    local dir="$1"
    rm -rf "$dir"
    mkdir -p "$dir"
    if compgen -G "$COMMITTED_SAVES/save-*.json" >/dev/null; then
        cp "$COMMITTED_SAVES"/*.json "$dir/"
        ARGS+=(-uitest-staged-saves)
        echo "Staged $(ls "$COMMITTED_SAVES"/save-*.json | wc -l | tr -d ' ') committed demo board(s)."
    fi
}

# Print the ordered shot list for this platform so the capture checklist is
# right there after launch (organize-shots.py is pure stdlib, no venv).
print_shots() {
    echo
    python3 Scripts/asc/organize-shots.py "$PLATFORM" --list
}

case "$PLATFORM" in
    iphone) pat="${DEVICE:-iPhone 1[6-9] Pro Max}" ;;
    ipad) pat="${DEVICE:-iPad Pro 13-inch}" ;;
    mac)
        # AppKit resolves Color.accentColor from the SYSTEM accent, out of
        # SwiftUI's reach — pin it per-launch via the argument domain so Mac
        # captures are blue on any machine (iOS is pinned in-app).
        ARGS+=(-AppleAccentColor 4)
        app=$(find ~/Library/Developer/Xcode/DerivedData/Donpa-*/Build/Products/Debug \
            -maxdepth 1 -name "Donpa Squad.app" 2>/dev/null | head -1)
        [ -n "$app" ] || { echo "Build the Mac app first (make build-mac)." >&2; exit 1; }
        stage_saves "$HOME/Library/Containers/$BUNDLE/Data/tmp/donpa-demo/saves"
        echo "Launching demo Mac app (fixed 1440×900 window)…"
        open "$app" --args "${ARGS[@]}"
        print_shots
        exit 0 ;;
    *) echo "PLATFORM must be iphone | ipad | mac" >&2; exit 2 ;;
esac

udid=$(pick_udid "$pat")
[ -n "$udid" ] || { echo "No simulator matching /$pat/ installed." >&2; exit 1; }
# Tell the caller (shoot.sh) WHICH device we picked — `booted` is ambiguous
# with several simulators open, and screenshots must hit this one.
[ -n "${DONPA_UDID_FILE:-}" ] && echo "$udid" > "$DONPA_UDID_FILE"
name=$(xcrun simctl list devices available | grep "$udid" | sed -E 's/ *\(.*//' | xargs)
echo "Booting ${name}…"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
open -a Simulator
app="$(find ~/Library/Developer/Xcode/DerivedData/Donpa-*/Build/Products/Debug-iphonesimulator \
    -maxdepth 1 -name "Donpa Squad.app" 2>/dev/null | head -1)"
[ -d "$app" ] || { echo "Build the app first (make build-ios)." >&2; exit 1; }
xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$udid" "$app"
container=$(xcrun simctl get_app_container "$udid" "$BUNDLE" data 2>/dev/null || true)
[ -n "$container" ] && stage_saves "$container/tmp/donpa-demo/saves"
xcrun simctl launch "$udid" "$BUNDLE" "${ARGS[@]}" >/dev/null
print_shots
