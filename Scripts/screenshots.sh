#!/usr/bin/env bash
# Capture App Store / website screenshots by running the ScreenshotCapture
# UI test (which drives the app to each showcase screen with seeded demo data)
# and extracting the named attachments from the .xcresult to PNGs.
#
# Local-only, like uitest.sh — never part of CI. Usage:
#   Scripts/screenshots.sh [output-dir]     (default: ./screenshots)
# Requires the Xcode project (the Makefile target regenerates it).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-screenshots}"
RESULT=".build-xcode/screenshots.xcresult"
mkdir -p "$OUT"
rm -rf "$RESULT"

# Device: an iPhone for the 6.7"/6.9" App Store set. Override with DEVICE=...
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
if ! xcrun simctl list devices available | grep -q "$DEVICE"; then
    DEVICE=$(xcrun simctl list devices available \
        | grep -oE "iPhone [0-9][^(]*" | tail -1 | xargs)
fi
echo "Capturing on: ${DEVICE}"

xcodebuild -project Donpa.xcodeproj -scheme Donpa-iOS \
    -destination "platform=iOS Simulator,name=${DEVICE}" \
    -resultBundlePath "$RESULT" \
    -only-testing:Donpa-iOSUITests/ScreenshotCapture \
    test

# Pull every screenshot attachment out of the result bundle, named by the
# attachment name the test set (home, game, scoreboard, …).
echo "Extracting attachments → ${OUT}/"
python3 Scripts/extract_screenshots.py "$RESULT" "$OUT"

echo "Done. Screenshots in ${OUT}/:"
ls -1 "$OUT"
