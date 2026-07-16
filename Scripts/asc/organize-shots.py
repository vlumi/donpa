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
"""
import os
import sys

# Canonical shots in capture order (see SCREENSHOTS.md). `iphone_only` marks
# shots skipped on iPad/Mac (the Mess hall reads poorly as a centred sheet).
SHOTS = [
    ("big-map", False),        # 1. million-cell map — the opener
    ("variant-board", False),  # 2. Round/Hive board mid-clear
    ("new-game", False),       # 3. the picker: families × sizes × edges
    ("mid-game", False),       # 4. a clean part-cleared normal board
    ("service-record", False), # 5. Tour of Duty — pace + daily orders
    ("daily", False),          # 6. daily calendar / review
    ("rivalry", True),         # 7. Mess hall (iPhone only)
]


def shots_for(platform):
    return [name for name, iphone_only in SHOTS
            if not (iphone_only and platform != "iphone")]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if not args or args[0] not in ("iphone", "ipad", "mac"):
        sys.exit("usage: organize-shots.py <iphone|ipad|mac> [<dir> | --list] [--by-mtime]")
    platform = args[0]
    names = shots_for(platform)

    if "--list" in flags or len(args) < 2:
        print(f"Capture these {len(names)} shots for {platform}, in this order:\n")
        for i, name in enumerate(names, 1):
            print(f"  {i}. {name}-{platform}.png")
        print("\nShoot in order, drop the raw files in one folder, then re-run "
              f"with that folder:\n  Scripts/asc/organize-shots.py {platform} <dir>")
        return

    d = args[1]
    raw = [f for f in os.listdir(d)
           if f.lower().endswith((".png", ".jpg", ".jpeg")) and not f.startswith(".")]
    key = (lambda f: os.path.getmtime(os.path.join(d, f))) if "--by-mtime" in flags else str.lower
    raw.sort(key=key)

    if len(raw) != len(names):
        print(f"⚠ found {len(raw)} images but expected {len(names)} for {platform}.")
        print("  Files (sorted):", raw)
        print("  Expected order:", [f"{n}-{platform}.png" for n in names])
        sys.exit("Fix the folder (one image per shot, in order) and re-run.")

    for src, name in zip(raw, names):
        dst = f"{name}-{platform}.png"
        os.rename(os.path.join(d, src), os.path.join(d, dst))
        print(f"  {src}  →  {dst}")
    print(f"\nRenamed {len(names)} shots for {platform}.")


if __name__ == "__main__":
    main()
