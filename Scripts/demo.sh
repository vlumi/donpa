#!/usr/bin/env bash
# Launch the app in DEMO mode — seeded data + a fixed blue accent (-uitest-demo)
# and an isolated store (-uitest-clean), for taking App Store screenshots by
# hand. Build first (make build-iphone/ipad is implied via the simulator run;
# Mac uses the built .app). Usage:
#   PLATFORM=iphone Scripts/demo.sh   # boot a sim + launch (default)
#   PLATFORM=ipad   Scripts/demo.sh
#   PLATFORM=mac    Scripts/demo.sh   # launch the built Mac app
# Then capture: simulator ⌘S (iOS/iPad), or Scripts/grab-mac-shot.sh <name> (Mac).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
# The app reads committed demo saves from $DONPA_REPO_ROOT/Scripts/asc/demo-saves
# (dev-only; not in the shipped bundle). Passed to the Mac app via the inherited
# env, and to the simulator via SIMCTL_CHILD_ (simctl forwards those, stripped).
export DONPA_REPO_ROOT="$REPO_ROOT"
export SIMCTL_CHILD_DONPA_REPO_ROOT="$REPO_ROOT"

PLATFORM="${PLATFORM:-iphone}"
# DEMO_LANG picks the UI language for this run (en|fi|ja) — a distinct name so
# it never collides with the shell's own LANG. Each language is its own clean
# launch; the seed is identical, so only the language differs.
DEMO_LANG="${DEMO_LANG:-en}"
case "$DEMO_LANG" in
    en | fi | ja) ;;
    *) echo "DEMO_LANG must be en | fi | ja (got '$DEMO_LANG')" >&2; exit 2 ;;
esac
ARGS=(-uitest-clean -uitest-demo -AppleLanguages "($DEMO_LANG)")
# DUMP=1 freezes each board you resume+edit (flags and all) to
# ~/Desktop/donpa-demo-saves/<config>.json on autosave/quit — hand those back
# to ship as the seeded saves.
[ "${DUMP:-0}" = "1" ] && ARGS+=(-uitest-dump-saves)
BUNDLE="fi.misaki.donpa"

pick_udid() {  # $1 = name pattern
    xcrun simctl list devices available | grep -E "$1" \
        | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | tail -1
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
        app=$(find ~/Library/Developer/Xcode/DerivedData/Donpa-*/Build/Products/Debug \
            -maxdepth 1 -name "Donpa Squad.app" 2>/dev/null | head -1)
        [ -n "$app" ] || { echo "Build the Mac app first (make build-mac)." >&2; exit 1; }
        echo "Launching demo Mac app (fixed 1440×900 window)…"
        open "$app" --args "${ARGS[@]}"
        print_shots
        echo
        echo "Capture each window with ⌘⇧4-space (or screencapture -w)."
        exit 0 ;;
    *) echo "PLATFORM must be iphone | ipad | mac" >&2; exit 2 ;;
esac

udid=$(pick_udid "$pat")
[ -n "$udid" ] || { echo "No simulator matching /$pat/ installed." >&2; exit 1; }
name=$(xcrun simctl list devices available | grep "$udid" | sed -E 's/ *\(.*//' | xargs)
echo "Booting ${name}…"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
open -a Simulator
app="$(find ~/Library/Developer/Xcode/DerivedData/Donpa-*/Build/Products/Debug-iphonesimulator \
    -maxdepth 1 -name "Donpa Squad.app" 2>/dev/null | head -1)"
[ -d "$app" ] || { echo "Build the app first (make build-ios)." >&2; exit 1; }
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" "$BUNDLE" "${ARGS[@]}"
print_shots
echo
echo "Capture each with the simulator's ⌘S (Save Screen)."
