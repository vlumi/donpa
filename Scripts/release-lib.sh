# Shared helpers for the release scripts (sourced, not executed).
#
# The release flow is split by concern: release-preflight.sh, release-publish.sh,
# release-tag.sh, distribute.sh — wired in order by the Makefile. The pure steps
# (preflight, tag, distribute) re-derive their inputs from git + project.yml so
# each runs standalone; only the dirty middle (publish: bump prompts + PR +
# CI-wait) carries in-memory state, all within one script.

# shellcheck shell=bash

PROJECT_FILE="project.yml"

say() { printf '\033[36m▶︎ %s\033[0m\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

# Echo the sole distinct value of a quoted setting in project.yml, or die if it's
# missing or differs between the two targets (they're kept in lock-step).
read_unique() {
    local key="$1" vals
    vals="$(grep -oE "${key}: *\"[^\"]+\"" "$PROJECT_FILE" | grep -oE '"[^"]+"' | tr -d '"' | sort -u)"
    [ -n "$vals" ] || die "no ${key} found in $PROJECT_FILE"
    [ "$(printf '%s\n' "$vals" | wc -l)" -eq 1 ] \
        || die "${key} differs between targets in $PROJECT_FILE: $(echo "$vals" | tr '\n' ' ')"
    printf '%s' "$vals"
}

# Validate a platform argument (ios|macos|all), echoing it back.
require_platform() {
    case "${1:-}" in
        ios|macos|all) printf '%s' "$1" ;;
        *) die "platform must be ios|macos|all (got '${1:-}')" ;;
    esac
}

# git prefix (ios|mac) and display label (iOS|macOS) for a platform.
tag_prefix() { [ "$1" = macos ] && echo mac || echo ios; }
plat_label() { [ "$1" = macos ] && echo macOS || echo iOS; }
