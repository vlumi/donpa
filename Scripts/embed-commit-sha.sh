#!/bin/sh
#
# Stamp the current git commit into the built app's Info.plist as a custom
# `GitCommitSHA` key, so every build (TestFlight, App Store, local) self-
# identifies the exact source it came from. Wired as a run-script build phase
# in project.yml for both app targets, so it fires on `xcodebuild` AND on an
# Xcode Organizer "Archive" (Apple sets INFOPLIST_PATH / TARGET_BUILD_DIR for us).
#
# It only writes the built product's plist (the bundled copy), never the source
# Info.plist — that one is XcodeGen-owned. A checkout with no resolvable HEAD (a
# source tarball, or a fresh `git init` with no commits yet) writes "unknown"
# rather than failing the build, and a dirty tree gets a "-dirty" suffix so a
# build off uncommitted changes is never mistaken for a clean commit.

set -eu

PLIST="${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ] || [ ! -f "$PLIST" ]; then
    echo "embed-commit-sha: no built Info.plist (TARGET_BUILD_DIR/INFOPLIST_PATH unset) — skipping"
    exit 0
fi

# A repo with no commits yet (fresh `git init`) has a git dir but no HEAD to
# resolve — check HEAD, not just the git dir, or `rev-parse HEAD` fails the build
# under `set -e`. Both that and a non-git checkout (a source tarball) get
# "unknown".
if git -C "${SRCROOT:-.}" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    SHA=$(git -C "${SRCROOT:-.}" rev-parse --short HEAD)
    if ! git -C "${SRCROOT:-.}" diff --quiet HEAD 2>/dev/null; then
        SHA="${SHA}-dirty"
    fi
else
    SHA="unknown"
fi

/usr/libexec/PlistBuddy -c "Set :GitCommitSHA $SHA" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :GitCommitSHA string $SHA" "$PLIST"

echo "embed-commit-sha: stamped GitCommitSHA = $SHA into $PLIST"
