#!/usr/bin/env bash
# Build, install, and launch the iOS app in a simulator.
#   Usage: run-ios.sh [iphone|ipad] [device-name-substring]
# Builds for the generic simulator destination, then installs to a sim of the
# chosen family: an already-booted matching one, else the newest available that
# matches the optional name substring (e.g. "SE", "17 Pro", "Air").
set -euo pipefail
cd "$(dirname "$0")/.."

bundle_id="fi.misaki.donpa"
derived=".build-xcode"
family="${1:-iphone}"   # iphone | ipad
device="${2:-}"         # optional name substring, e.g. "SE" or "17 Pro"
case "$family" in
    iphone) family_match="iPhone" ;;
    ipad)   family_match="iPad" ;;
    *) echo "error: family must be iphone or ipad (got '$family')" >&2; exit 2 ;;
esac

# Pick a simulator (iOS >= 16, the app's minimum). Rules:
#  - No DEVICE filter: reuse an already-booted one of the family if any, else
#    the newest by runtime version — the quick "just run it" path.
#  - DEVICE filter given: it is AUTHORITATIVE — pick the best NAME match and
#    boot it even if another sim is already booted (so `DEVICE=SE` really gives
#    you the SE), and FAIL if nothing matches rather than silently substituting.
#    Names are additive substrings ("17" ⊂ "17 Pro" ⊂ "17 Pro Max"), so among
#    matches prefer an exact name, then the shortest name, then newest runtime —
#    `DEVICE=17` favours plain "iPhone 17" over the Pro Max.
udid="$(xcrun simctl list devices --json 2>/dev/null | DEVICE="$device" FAMILY="$family_match" python3 -c '
import json, os, re, sys
d = json.load(sys.stdin)["devices"]
want = os.environ.get("DEVICE", "").strip()
fam = os.environ.get("FAMILY", "iPhone")
booted = None
matches = []  # (exact_name, name_len, ver, udid)
for runtime, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    ver = (int(m.group(1)), int(m.group(2))) if m else None
    if not ver or ver < (16, 0):
        continue
    for dev in devs:
        name = dev["name"]
        if not dev.get("isAvailable") or fam not in name:
            continue
        if want and want.lower() not in name.lower():
            continue
        if dev["state"] == "Booted":
            booted = dev["udid"]
        exact = (name.lower() == want.lower())
        matches.append((not exact, len(name), tuple(-x for x in ver), dev["udid"]))
if not matches:
    print("")
elif want:
    # Filter is authoritative: best name match wins, ignore whatever is booted.
    print(sorted(matches)[0][3])
else:
    print(booted or sorted(matches)[0][3])
')"
[ -n "$udid" ] || {
    echo "error: no available iOS>=16 $family_match simulator${device:+ matching '$device'} found" >&2
    exit 1
}

echo "Simulator: $udid"
open -a Simulator
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

# Build for the generic simulator destination (robust — no per-device matching),
# then install the product to the chosen sim.
echo "Building Donpa-iOS..."
xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$derived" -configuration Debug build \
    >/dev/null 2>&1 || {
    echo "build failed; re-running with full output:" >&2
    xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$derived" -configuration Debug build
    exit 1
}

app="$derived/Build/Products/Debug-iphonesimulator/Donpa Squad.app"
[ -d "$app" ] || { echo "error: built app not found at $app" >&2; exit 1; }

echo "Installing and launching $bundle_id"
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" "$bundle_id"
