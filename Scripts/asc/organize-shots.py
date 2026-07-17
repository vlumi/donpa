#!/usr/bin/env python3
"""Rename a folder of raw screenshots to the canonical set, by CAPTURE ORDER —
so you shoot in the listed order, dump the files in one folder, and this names
them without you having to look at each image.

The order is the SCREENSHOTS.md shot list (best-first). Per platform the count
differs (rivalry is iPhone-only), so pass the platform.

  # print the order to shoot in (do this first):
  Scripts/asc/organize-shots.py iphone --list

  # after dumping raw shots into <dir> (sorted by filename = capture order):
  Scripts/asc/organize-shots.py iphone <dir>
  Scripts/asc/organize-shots.py ipad   <dir>
  Scripts/asc/organize-shots.py mac    <dir>

Sorted by filename ascending — macOS names shots "Screenshot … at H.MM.SS",
Simulator names them by timestamp too, so lexical sort == capture order. Pass
--by-mtime if your names don't sort chronologically.

Multiple languages in ONE folder: shoot each language's full set back-to-back
(en set, then fi set, then ja set), dump all into <dir>, and pass the order
with --langs. The files split into per-language subfolders, canonically named:

  Scripts/asc/organize-shots.py iphone <dir> --langs en,fi,ja
  # → <dir>/en/big-map-iphone.png, <dir>/fi/big-map-iphone.png, …

Expects exactly (shots × languages) files; the first chunk is the first
language, and so on.
"""
import os
import sys

# Canonical shots in capture order (see SCREENSHOTS.md — the recommended STORE
# order differs; arrange at upload). Each: (name, iphone_only, what-to-capture);
# `iphone_only` skips a shot on iPad/Mac. Every language gets this SAME full
# set, in that language — a JP listing must show JP screenshots, not English.
SHOTS = [
    ("big-map", False,
     "Resume the XXL save and zoom out so the minimap and sheer scale fill the "
     "screen — the scale hook."),
    ("big-map-dark", False,
     "The SAME big-map shot in Dark: flip Settings ▸ Appearance to Dark, "
     "re-frame, capture, flip back to Light. The dark-mode taster."),
    ("variant-board", False,
     "Resume the Hive save — a hex board mid-solve, so the non-square shape "
     "reads at a glance."),
    ("new-game", False,
     "FROM WITHIN A GAME (board behind, never the title art), open New Game; "
     "show the family / size / edge picker with a family selected."),
    ("mid-game", False,
     "Resume the Beginner save — a clean, part-cleared square board mid-solve."),
    ("service-record", False,
     "From within a game, open the Service Record (medal button) and EXPAND a "
     "cleared board's row — top-5 times, pace, the rival ladder."),
    ("daily", False,
     "The daily REVIEW screen: start the daily from Home — board + Start "
     "overlay, no title art. (The calendar only opens over Home's art.)"),
    ("rivalry", False,
     "From within a game: Service Record ▸ 'Manage rivals' swaps to the Mess "
     "hall over the board — share card + rivals list, no title art."),
]


def shots_for(platform):
    return [(name, desc) for name, iphone_only, desc in SHOTS
            if not (iphone_only and platform != "iphone")]


def rename_set(d, raw_files, names, platform, subdir=None):
    """Rename `raw_files` (already in capture order) to canonical names, into
    `d`/`subdir` when a subdir (a language) is given."""
    out = os.path.join(d, subdir) if subdir else d
    os.makedirs(out, exist_ok=True)
    for src, name in zip(raw_files, names):
        dst = f"{name}-{platform}.png"
        os.rename(os.path.join(d, src), os.path.join(out, dst))
        print(f"  {src}  →  {os.path.join(subdir, dst) if subdir else dst}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    flagset = {f.split("=", 1)[0] for f in flags}
    langs = next(
        (f.split("=", 1)[1].split(",") for f in flags if f.startswith("--langs=")), None)
    if not args or args[0] not in ("iphone", "ipad", "mac"):
        sys.exit(
            "usage: organize-shots.py <iphone|ipad|mac> "
            "[<dir> | --list] [--by-mtime] [--langs=en,fi,ja]")
    platform = args[0]
    shots = shots_for(platform)
    names = [name for name, _ in shots]

    if "--plain" in flagset:  # machine-readable, for Scripts/shoot.sh
        for name, desc in shots:
            print(f"{name}\t{desc}")
        return

    if "--list" in flagset or len(args) < 2:
        print(f"Capture these {len(shots)} shots for {platform}, in this order:\n")
        for i, (name, desc) in enumerate(shots, 1):
            print(f"  {i}. {name}-{platform}.png")
            print(f"     {desc}")
        print("\nShots 1 (big-map, Light) and 2 (big-map-dark) are the same "
              "board:\nshoot 1, flip Settings ▸ Appearance to Dark, shoot 2, "
              "flip back to Light,\nthen carry on. Everything else is Light.")
        print("\nOne language: drop that set's raw files in a folder, then:\n"
              f"  Scripts/asc/organize-shots.py {platform} <dir>")
        print(f"Several: shoot the SAME {len(shots)} shots in each language "
              "(each listing needs\nits own localized set), all into one "
              "folder in language order:\n"
              f"  Scripts/asc/organize-shots.py {platform} <dir> --langs=en,fi,ja")
        return

    d = args[1]
    raw = [f for f in os.listdir(d)
           if f.lower().endswith((".png", ".jpg", ".jpeg")) and not f.startswith(".")]
    key = (
        (lambda f: os.path.getmtime(os.path.join(d, f)))
        if "--by-mtime" in flagset else str.lower)
    raw.sort(key=key)

    # One flat set, or several equal-size language sets back-to-back.
    groups = langs or [None]
    expected = len(names) * len(groups)
    if len(raw) != expected:
        print(f"⚠ found {len(raw)} images but expected {expected} for {platform}"
              + (f" ({len(names)} shots × {len(groups)} languages)" if langs else "") + ".")
        print("  Files (sorted):", raw)
        sys.exit("Fix the folder (one image per shot, in capture order) and re-run.")

    for i, lang in enumerate(groups):
        chunk = raw[i * len(names):(i + 1) * len(names)]
        rename_set(d, chunk, names, platform, subdir=lang)
    print(f"\nRenamed {expected} shot(s) for {platform}"
          + (f" across {len(groups)} languages." if langs else "."))


if __name__ == "__main__":
    main()
