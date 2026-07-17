#!/usr/bin/env python3
"""Sync Game Center achievements from the canonical achievements.json to
App Store Connect — so text, points, hidden flag, and images are edited in
the repo and pushed with one command, never clicked into the ASC UI.

Dry-run by default: prints exactly what WOULD change and touches nothing.
Pass --apply to write. Images are only (re)uploaded with --images, since the
upload dance is slow and images change rarely; --images alone still needs
--apply to write.

  Scripts/asc/sync.py                 # dry run: show the diff
  Scripts/asc/sync.py --apply         # push text/points/hidden changes
  Scripts/asc/sync.py --apply --images  # also (re)upload images

Image files are read from Scripts/asc/medals (the committed set rendered by
`make asc-medals`), overridable with --image-dir.
Needs: PyJWT + cryptography.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _client import ASC  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def load_canonical():
    doc = json.load(open(os.path.join(HERE, "achievements.json")))
    return doc


def resolve_gc(asc, bundle_id):
    apps = asc.get(f"/apps?filter[bundleId]={bundle_id}&limit=1")["data"]
    if not apps:
        sys.exit(f"No app with bundle id {bundle_id} under this key.")
    detail = asc.get(f"/apps/{apps[0]['id']}/gameCenterDetail")["data"]
    if not detail:
        sys.exit("App has no Game Center detail — enable Game Center first.")
    return detail["id"]


def live_achievements(asc, gc_id):
    """Map wire id → {id, attributes, localizations:{locale:{id,attributes,imageId}}}."""
    out = {}
    achs = asc.get_all(
        f"/gameCenterDetails/{gc_id}/gameCenterAchievements?limit=200")
    for a in achs:
        ref = a["attributes"].get("vendorIdentifier") or a["attributes"].get("referenceName")
        locs = {}
        page = asc.get(
            f"/gameCenterAchievements/{a['id']}/localizations"
            "?limit=50&include=gameCenterAchievementImage")
        for loc in page.get("data", []):
            rel = loc.get("relationships", {}).get("gameCenterAchievementImage", {})
            img = (rel.get("data") or {})
            locs[loc["attributes"]["locale"]] = {
                "id": loc["id"], "attributes": loc["attributes"],
                "imageId": img.get("id"),
            }
        out[ref] = {"id": a["id"], "attributes": a["attributes"], "localizations": locs}
    return out


def diff_attrs(want, live_attrs):
    """Return the achievement-level attributes that differ (points/hidden/progress)."""
    changes = {}
    if want["points"] != live_attrs.get("points"):
        changes["points"] = want["points"]
    # ASC calls it `showBeforeEarned` (hidden = NOT shown before earned).
    want_shown = not want["hidden"]
    if want_shown != live_attrs.get("showBeforeEarned"):
        changes["showBeforeEarned"] = want_shown
    if want["showProgress"] != live_attrs.get("achievableMoreThanOnce", False):
        # showProgress isn't a direct attribute; progress display is driven by
        # the reporter's percentComplete. Nothing to PATCH here — noted only.
        pass
    return changes


def diff_localization(want_loc, live_loc):
    changes = {}
    la = live_loc["attributes"]
    if want_loc["title"] != la.get("name"):
        changes["name"] = want_loc["title"]
    if want_loc["beforeEarned"] != la.get("beforeEarnedDescription"):
        changes["beforeEarnedDescription"] = want_loc["beforeEarned"]
    if want_loc["afterEarned"] != la.get("afterEarnedDescription"):
        changes["afterEarnedDescription"] = want_loc["afterEarned"]
    return changes


def upload_image(asc, loc_id, path, existing_image_id, apply):
    """The 3-step ASC image dance: reserve → upload chunk(s) → commit.
    Replaces any existing image on the localization first."""
    data = open(path, "rb").read()
    if apply and existing_image_id:
        asc.delete(f"/gameCenterAchievementImages/{existing_image_id}")
    if not apply:
        return "would upload"
    # 1. Reserve.
    reserve = asc.post("/gameCenterAchievementImages", {
        "data": {
            "type": "gameCenterAchievementImages",
            "attributes": {
                "fileName": os.path.basename(path), "fileSize": len(data)},
            "relationships": {
                "gameCenterAchievementLocalization": {
                    "data": {"type": "gameCenterAchievementLocalizations", "id": loc_id}}},
        }})
    image_id = reserve["data"]["id"]
    op = reserve["data"]["attributes"]["uploadOperations"][0]
    # 2. Upload the bytes to the returned URL.
    headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
    _put_bytes(op, data, headers)
    # 3. Commit. Only `uploaded` is accepted here — sourceFileChecksum is a
    # reserve-time attribute and 409s ("unknown attribute") at commit.
    asc.patch(f"/gameCenterAchievementImages/{image_id}", {
        "data": {"type": "gameCenterAchievementImages", "id": image_id,
                 "attributes": {"uploaded": True}}})
    return "uploaded"


def _put_bytes(op, data, headers):
    import urllib.request
    req = urllib.request.Request(op["url"], data=data, method=op["method"])
    for k, v in headers.items():
        req.add_header(k, v)
    with urllib.request.urlopen(req):
        pass


def release_achievements(asc, gc_id, live, apply):
    """Add every achievement to review by creating its release record against
    the Game Center detail (the "add to review from the Game Center section"
    flow — one call per achievement, not the per-item UI click). Skips any that
    already have a release. Idempotent: a duplicate create 409s and is skipped."""
    # `include=` is required — without it the list omits relationship data,
    # the set collapses to {None}, and every re-run re-plans all 29.
    existing = {
        (r.get("relationships", {}).get("gameCenterAchievement", {}).get("data") or {}).get("id")
        for r in asc.get_all(
            f"/gameCenterDetails/{gc_id}/achievementReleases"
            "?limit=200&include=gameCenterAchievement")
    }
    made = skipped = 0
    for wid, cur in sorted(live.items()):
        if cur["id"] in existing:
            skipped += 1
            continue
        print(f"release: {wid}")
        if apply:
            _post_release(asc, gc_id, cur["id"])
        made += 1
    print(f"\n{made} release(s) {'created' if apply else 'to create'}, "
          f"{skipped} already released.")


def _post_release(asc, gc_id, achievement_id):
    """One release record; a duplicate 409 means it's already in review — skip."""
    try:
        asc.post("/gameCenterAchievementReleases", {
                "data": {
                    "type": "gameCenterAchievementReleases",
                    "relationships": {
                        "gameCenterDetail": {
                            "data": {"type": "gameCenterDetails", "id": gc_id}},
                        "gameCenterAchievement": {
                            "data": {"type": "gameCenterAchievements", "id": achievement_id}},
                    }}})
    except RuntimeError as e:
        if "409" not in str(e):
            raise


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--images", action="store_true", help="also (re)upload images")
    ap.add_argument(
        "--image-dir", default=os.path.join(HERE, "medals"), help="dir of <id>.png files")
    ap.add_argument("--release", action="store_true",
                    help="add achievements to review (create release records)")
    args = ap.parse_args()

    doc = load_canonical()
    asc = ASC()
    gc_id = resolve_gc(asc, doc["bundleId"])
    live = live_achievements(asc, gc_id)

    if args.release:
        print(f"== {'APPLYING' if args.apply else 'DRY RUN (--apply to write)'} ==\n")
        release_achievements(asc, gc_id, live, args.apply)
        return

    verb = "APPLYING" if args.apply else "DRY RUN (no changes; --apply to write)"
    print(f"== {verb} ==\n")
    text_changes = img_changes = missing = 0

    for want in doc["achievements"]:
        wid = want["id"]
        cur = live.get(wid)
        if not cur:
            print(f"⚠ {wid}: not found in ASC (create it in the UI first)")
            missing += 1
            continue

        attr_changes = diff_attrs(want, cur["attributes"])
        if attr_changes:
            text_changes += 1
            print(f"{wid}: attrs {attr_changes}")
            if args.apply:
                asc.patch(f"/gameCenterAchievements/{cur['id']}", {
                    "data": {"type": "gameCenterAchievements", "id": cur["id"],
                             "attributes": attr_changes}})

        for locale, wl in want["localizations"].items():
            ll = cur["localizations"].get(locale)
            if not ll:
                print(f"{wid} [{locale}]: missing localization")
                missing += 1
                continue
            loc_changes = diff_localization(wl, ll)
            if loc_changes:
                text_changes += 1
                print(f"{wid} [{locale}]: {list(loc_changes)}")
                if args.apply:
                    asc.patch(f"/gameCenterAchievementLocalizations/{ll['id']}", {
                        "data": {"type": "gameCenterAchievementLocalizations",
                                 "id": ll["id"], "attributes": loc_changes}})
            if args.images:
                path = os.path.join(args.image_dir, want["image"])
                if not os.path.exists(path):
                    print(f"⚠ {wid} [{locale}]: image {path} not found")
                    missing += 1
                    continue
                result = upload_image(asc, ll["id"], path, ll["imageId"], args.apply)
                img_changes += 1
                print(f"{wid} [{locale}]: image {result}")

    print(f"\n{text_changes} text/attr change(s), {img_changes} image op(s), "
          f"{missing} problem(s).")
    if not args.apply and (text_changes or img_changes):
        print("Re-run with --apply to write.")


if __name__ == "__main__":
    main()
