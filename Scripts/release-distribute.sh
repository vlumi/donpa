#!/usr/bin/env bash
# Release step 4 (pure): regenerate the project from main's tip, then archive,
# export, and (unless --no-upload) upload each selected platform via the existing
# Scripts/distribute.sh. Reads nothing but its platform argument; builds straight
# from the checked-out main, which is the tagged merge commit after the prior step.
#
# Usage: release-distribute.sh <ios|macos|all> [--no-upload]
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

platform="$(require_platform "${1:-}")"
shift || true
upload=1
while [ $# -gt 0 ]; do
    case "$1" in
        --no-upload) upload=0 ;;
        *) die "unknown argument '$1'" ;;
    esac
    shift
done

Scripts/generate.sh >/dev/null

distribute() {
    if [ "$upload" -eq 1 ]; then
        Scripts/distribute.sh "$1"
    else
        Scripts/distribute.sh "$1" --no-upload
    fi
}

say "Distributing…"
case "$platform" in ios|all) distribute ios ;; esac
case "$platform" in macos|all) distribute macos ;; esac

echo
if [ "$upload" -eq 1 ]; then
    echo "✓ distributed (${platform}) — uploaded to App Store Connect."
else
    echo "✓ built (${platform}) — packages in dist/ (upload skipped)."
fi
