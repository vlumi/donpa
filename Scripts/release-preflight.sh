#!/usr/bin/env bash
# Release step 1 (pure): refuse to start unless we're on a clean release base
# (main, or a release/X.Y.x maintenance branch — see release_base) that matches
# origin, with gh available — so the commit we eventually tag and build is
# exactly what reviewers see and what lands on the base. Mutates nothing; safe
# to run anytime.
set -euo pipefail
cd "$(dirname "$0")/.."
. Scripts/release-lib.sh

command -v gh >/dev/null || die "gh CLI not found (needed to open + auto-merge the PR)."
[ -z "$(git status --porcelain)" ] || die "working tree not clean — commit or stash first."
base="$(release_base)"
say "Fetching origin…"
git fetch --quiet origin "$base"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$base")" ] \
    || die "local ${base} differs from origin/${base} — pull/push to sync first."
echo "✓ preflight: on a clean ${base} matching origin."
