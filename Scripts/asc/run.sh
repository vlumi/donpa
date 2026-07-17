#!/usr/bin/env bash
# Run the App Store Connect achievement tooling in a self-managed venv, so the
# Makefile targets are one step. Bootstraps the venv on first use and refreshes
# it only when requirements.txt changes (a stamp file guards the reinstall).
#
# Usage: run.sh status
#        run.sh sync [-- <extra args passed to sync.py, e.g. --apply --images>]
set -euo pipefail
cd "$(dirname "$0")"

VENV="${DONPA_ASC_VENV:-$HOME/.venvs/donpa-asc}"
PY="$VENV/bin/python"
STAMP="$VENV/.requirements-stamp"

# Homebrew's Python is externally-managed; a venv is the correct install target.
if [ ! -x "$PY" ]; then
    echo "▶︎ Creating venv at $VENV …"
    python3 -m venv "$VENV"
fi
# (Re)install deps when requirements.txt is newer than the last install.
if [ ! -f "$STAMP" ] || [ requirements.txt -nt "$STAMP" ]; then
    echo "▶︎ Installing dependencies …"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet -r requirements.txt
    touch "$STAMP"
fi

cmd="${1:-status}"
shift || true
case "$cmd" in
    status) exec "$PY" status.py "$@" ;;
    sync) exec "$PY" sync.py "$@" ;;
    listing) exec "$PY" listing.py "$@" ;;
    organize) exec "$PY" organize-shots.py "$@" ;;
    screens) exec "$PY" screenshots.py "$@" ;;
    *) echo "usage: run.sh {status|sync|listing|organize|screens} [args]" >&2; exit 2 ;;
esac
