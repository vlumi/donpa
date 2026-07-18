#!/usr/bin/env python3
"""Upload App Store screenshots from the `make shots` output tree — so ~70
per-locale uploads never happen by hand in Media Manager.

Reads shots/<platform>/<lang>/<shot>-<platform>.png, maps platform → the ASC
screenshot set (display type) and lang → locale, REPLACES each set's contents,
and uploads in the agreed store order (big-map first, the dark twin last).

  Scripts/asc/screenshots.py               # dry run: show the plan
  Scripts/asc/screenshots.py --apply       # replace + upload
  Scripts/asc/screenshots.py --dir <tree>  # a different capture tree

Dry-run by default. Needs: PyJWT + cryptography (the run.sh venv).
"""
import argparse
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _client import ASC  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
# run.sh cd's into Scripts/asc — anchor the default capture tree at repo root.
REPO = os.path.dirname(os.path.dirname(HERE))

# The carousel sells in this order — capture order is staging convenience only.
STORE_ORDER = ["big-map", "mid-game", "variant-board", "new-game",
               "daily", "rivalry", "service-record", "big-map-dark"]

# platform dir → (ASC version platform, screenshot display type)
PLATFORMS = {
    "iphone": ("IOS", "APP_IPHONE_67"),
    "ipad": ("IOS", "APP_IPAD_PRO_3GEN_129"),
    "mac": ("MAC_OS", "APP_DESKTOP"),
}
# Pixel sizes ASC accepts for each platform dir. A capture at any other size
# uploads fine but fails ASC's processing — a broken tile that BLOCKS
# submission — so refuse it here, loudly, before touching the sets.
EXPECTED_SIZES = {
    "iphone": {(1320, 2868)},
    "ipad": {(2064, 2752)},
    "mac": {(1440, 900), (2880, 1800)},
}
LOCALES = {"en": "en-US", "fi": "fi", "ja": "ja"}
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "PENDING_DEVELOPER_RELEASE"}


def ordered_files(lang_dir, platform):
    """The captured files present, in store order."""
    out = []
    for name in STORE_ORDER:
        path = os.path.join(lang_dir, f"{name}-{platform}.png")
        if os.path.exists(path):
            out.append(path)
    return out


def png_size(path):
    """Width × height from the PNG header (IHDR is always first)."""
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        sys.exit(f"Not a PNG: {path}")
    return (int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big"))


def check_sizes(files, platform):
    """Refuse the whole run on a wrong-sized capture (see EXPECTED_SIZES)."""
    bad = [(p, png_size(p)) for p in files if png_size(p) not in EXPECTED_SIZES[platform]]
    if bad:
        lines = "\n".join(f"  {p}: {w}x{h}" for p, (w, h) in bad)
        want = " or ".join(f"{w}x{h}" for w, h in sorted(EXPECTED_SIZES[platform]))
        sys.exit(f"Wrong-sized {platform} capture(s) — expected {want}:\n{lines}\n"
                 "Recapture via `make shots` (the demo pins the window/simulator size).")


def screenshot_set(asc, loc_id, display_type, apply):
    """The localization's set for `display_type`, created when missing."""
    sets = asc.get_all(f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    for s in sets:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    if not apply:
        return None  # dry run: would create
    created = asc.post("/appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
        }})
    return created["data"]["id"]


def clear_set(asc, set_id, apply):
    """Delete every existing screenshot in the set (replace semantics)."""
    existing = asc.get_all(f"/appScreenshotSets/{set_id}/appScreenshots")
    for shot in existing:
        if apply:
            asc.delete(f"/appScreenshots/{shot['id']}")
    return len(existing)


def upload(asc, set_id, path):
    """The 3-step dance: reserve → upload chunk(s) → commit."""
    data = open(path, "rb").read()
    reserve = asc.post("/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileName": os.path.basename(path), "fileSize": len(data)},
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}}},
        }})
    shot_id = reserve["data"]["id"]
    for op in reserve["data"]["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        _put_bytes(op, chunk, headers)
    # Commit — try the documented checksum form; drop it if ASC rejects the
    # attribute (as it now does for achievement images).
    md5 = hashlib.md5(data).hexdigest()
    for attrs in ({"uploaded": True, "sourceFileChecksum": md5}, {"uploaded": True}):
        try:
            asc.patch(f"/appScreenshots/{shot_id}", {
                "data": {"type": "appScreenshots", "id": shot_id, "attributes": attrs}})
            return
        except RuntimeError as e:
            if "ATTRIBUTE.UNKNOWN" not in str(e):
                raise


def _put_bytes(op, data, headers):
    import urllib.request
    req = urllib.request.Request(op["url"], data=data, method=op["method"])
    for k, v in headers.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write (default: dry run)")
    ap.add_argument(
        "--dir", default=os.path.join(REPO, "shots"),
        help="capture tree (default: <repo>/shots)")
    args = ap.parse_args()

    doc = json.load(open(os.path.join(HERE, "listing.json")))
    asc = ASC()
    apps = asc.get(f"/apps?filter[bundleId]={doc['bundleId']}&limit=1")["data"]
    if not apps:
        sys.exit(f"No app with bundle id {doc['bundleId']} under this key.")
    app_id = apps[0]["id"]

    versions = asc.get(f"/apps/{app_id}/appStoreVersions?limit=20")["data"]
    by_platform = {}
    for ver in versions:
        if ver["attributes"]["appStoreState"] in EDITABLE:
            by_platform.setdefault(ver["attributes"]["platform"], ver)

    print(f"== {'APPLYING' if args.apply else 'DRY RUN (--apply to write)'} ==\n")
    uploaded = 0
    for platform, (ver_platform, display_type) in PLATFORMS.items():
        plat_dir = os.path.join(args.dir, platform)
        if not os.path.isdir(plat_dir):
            print(f"({platform}: no {plat_dir}/ — skipped)")
            continue
        ver = by_platform.get(ver_platform)
        if not ver:
            print(f"({platform}: no editable {ver_platform} version — skipped)")
            continue
        locs = asc.get_all(
            f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")
        loc_ids = {l["attributes"]["locale"]: l["id"] for l in locs}
        for lang, locale in LOCALES.items():
            lang_dir = os.path.join(plat_dir, lang)
            files = ordered_files(lang_dir, platform) if os.path.isdir(lang_dir) else []
            if not files:
                print(f"({platform} [{locale}]: no captures — skipped)")
                continue
            check_sizes(files, platform)
            loc_id = loc_ids.get(locale)
            if not loc_id:
                print(f"({platform} [{locale}]: locale missing on the version — skipped)")
                continue
            set_id = screenshot_set(asc, loc_id, display_type, args.apply)
            if set_id is None:
                print(f"{platform} [{locale}]: would create {display_type} set "
                      f"and upload {len(files)}")
                uploaded += len(files)
                continue
            dropped = clear_set(asc, set_id, args.apply)
            note = f" (replacing {dropped})" if dropped else ""
            if args.apply:
                for path in files:
                    upload(asc, set_id, path)
                    print(f"  {platform} [{locale}] ← {os.path.basename(path)}")
            else:
                print(f"{platform} [{locale}]: would upload {len(files)}{note}: "
                      + ", ".join(os.path.basename(f) for f in files))
            uploaded += len(files)

    print(f"\n{uploaded} screenshot(s) {'uploaded' if args.apply else 'planned'}.")


if __name__ == "__main__":
    main()
