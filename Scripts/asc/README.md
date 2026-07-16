# App Store Connect achievement tooling

Manage the 29 Game Center achievements from the repo instead of the ASC UI.
`achievements.json` is the single source of truth (text, points, hidden flag,
image filename); edit it here, never in ASC.

## Setup (once)

Homebrew's Python is externally-managed, so install into a virtualenv:

```sh
python3 -m venv ~/.venvs/donpa-asc
~/.venvs/donpa-asc/bin/pip install -r Scripts/asc/requirements.txt
```

Credentials reuse the release lane's: `Scripts/.asc-config` (Key ID + Issuer
ID) with the `.p8` in `~/.appstoreconnect/private_keys/` — nothing new to set up.

## Use

```sh
PY=~/.venvs/donpa-asc/bin/python

$PY Scripts/asc/status.py            # list all achievements + completeness
$PY Scripts/asc/sync.py              # dry run: show what differs from ASC
$PY Scripts/asc/sync.py --apply      # push text/points/hidden changes
$PY Scripts/asc/sync.py --apply --images --image-dir <dir>   # also (re)upload images
```

Images come from the app's render harness:
`DONPA_MEDAL_ASC=<dir> swift test --filter MedalGalleryRender/testRenderASCImages`.
