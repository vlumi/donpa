#!/usr/bin/env python3
"""Sync the App Store listing text from listing.json to App Store Connect —
app name/subtitle/privacy URL (app-level) and description/keywords/promo/
what's-new/URLs (per platform version). Edit listing.json, push with one
command, never the ASC UI.

Dry-run by default; --apply to write. Text only (screenshots: screenshots.py).

  Scripts/asc/listing.py            # dry run: show the diff
  Scripts/asc/listing.py --apply    # write

Needs: PyJWT + cryptography (see README.md).
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _client import ASC  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))

# ASC attribute keys, in the two localization scopes.
APPINFO_FIELDS = ["name", "subtitle", "privacyPolicyUrl"]
VERSION_FIELDS = [
    "description", "keywords", "promotionalText", "supportUrl",
    "marketingUrl", "whatsNew",
]


def patch_localization(asc, kind, loc_id, want, live_attrs, fields, apply, label):
    changes = {k: want[k] for k in fields
               if k in want and want[k] != live_attrs.get(k)}
    if not changes:
        return 0
    print(f"{label}: {list(changes)}")
    if not apply:
        return 1
    # Some fields lock once a build is in review/processing (notably whatsNew).
    # A PATCH is atomic, so one locked field would reject the whole set — so on
    # a STATE_ERROR we drop the field(s) it names and retry the editable rest,
    # reporting what was skipped rather than failing the run.
    attrs = dict(changes)
    while attrs:
        try:
            asc.patch(f"/{kind}/{loc_id}", {
                "data": {"type": kind, "id": loc_id, "attributes": attrs}})
            return 1
        except RuntimeError as err:
            locked = [f for f in list(attrs) if f"'{f}'" in str(err)]
            if not locked or "409" not in str(err):
                raise
            for f in locked:
                attrs.pop(f)
            print(f"  ↳ locked, skipped: {locked} (editable fields still written)")
    return 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write (default: dry run)")
    args = ap.parse_args()

    doc = json.load(open(os.path.join(HERE, "listing.json")))
    asc = ASC()
    apps = asc.get(f"/apps?filter[bundleId]={doc['bundleId']}&limit=1")["data"]
    if not apps:
        sys.exit(f"No app with bundle id {doc['bundleId']} under this key.")
    app_id = apps[0]["id"]

    print(f"== {'APPLYING' if args.apply else 'DRY RUN (--apply to write)'} ==\n")
    changed = 0

    # App-level: name / subtitle / privacy URL, shared across platforms.
    info = asc.get(f"/apps/{app_id}/appInfos")["data"][0]
    for loc in asc.get(f"/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"]:
        locale = loc["attributes"]["locale"]
        want = doc["appInfo"].get(locale)
        if not want:
            continue
        changed += patch_localization(
            asc, "appInfoLocalizations", loc["id"], want, loc["attributes"],
            APPINFO_FIELDS, args.apply, f"appInfo [{locale}]")

    # Version-level: written to EVERY editable version (iOS + macOS).
    versions = asc.get(f"/apps/{app_id}/appStoreVersions?limit=20")["data"]
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                "METADATA_REJECTED", "PENDING_DEVELOPER_RELEASE"}
    released = {"READY_FOR_SALE", "PENDING_DEVELOPER_RELEASE", "REPLACED_WITH_NEW_VERSION",
                "REMOVED_FROM_SALE"}
    # `whatsNew` is release notes — it doesn't exist for a first release (no
    # prior public version to describe changes from) and Apple locks it there.
    # Include it only once the app has ever been released.
    has_release = any(v["attributes"]["appStoreState"] in released for v in versions)
    fields = VERSION_FIELDS if has_release else [f for f in VERSION_FIELDS if f != "whatsNew"]
    if not has_release:
        print("(first release — 'whatsNew' omitted; it applies to updates only)\n")
    for ver in versions:
        state = ver["attributes"]["appStoreState"]
        platform = ver["attributes"]["platform"]
        if state not in editable:
            print(f"(skipping {platform} {ver['attributes']['versionString']} — {state})")
            continue
        locs = asc.get(
            f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")["data"]
        for loc in locs:
            locale = loc["attributes"]["locale"]
            want = doc["version"].get(locale)
            if not want:
                continue
            changed += patch_localization(
                asc, "appStoreVersionLocalizations", loc["id"], want,
                loc["attributes"], fields, args.apply,
                f"{platform} [{locale}]")

    print(f"\n{changed} change(s).")
    if not args.apply and changed:
        print("Re-run with --apply to write.")


if __name__ == "__main__":
    main()
