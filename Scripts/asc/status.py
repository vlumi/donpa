#!/usr/bin/env python3
"""List every Game Center achievement in App Store Connect with its
completeness — points, per-locale coverage, image count, live flag — so the
whole set is checkable at a glance instead of clicking through each one.

  Scripts/asc/status.py

Reads the same canonical bundle id + expected locales as sync.py.
Needs: PyJWT + cryptography (see README.md — install into a venv).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _client import ASC  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    doc = json.load(open(os.path.join(HERE, "achievements.json")))
    expected = set(doc["expectedLocales"])
    asc = ASC()

    apps = asc.get(f"/apps?filter[bundleId]={doc['bundleId']}&limit=1")["data"]
    if not apps:
        sys.exit(f"No app with bundle id {doc['bundleId']} under this key.")
    detail = asc.get(f"/apps/{apps[0]['id']}/gameCenterDetail")["data"]
    if not detail:
        sys.exit("App has no Game Center detail.")
    achs = asc.get_all(
        f"/gameCenterDetails/{detail['id']}/gameCenterAchievements?limit=200")

    print(f"{len(achs)} achievements\n")
    header = f"{'reference name':<26} {'points':>6} {'locales':<14} {'image':<6} live"
    print(header)
    print("-" * len(header))
    incomplete = 0
    for ach in sorted(achs, key=lambda a: a["attributes"].get("referenceName", "")):
        attr = ach["attributes"]
        name = attr.get("referenceName", "?")[:25]
        points = attr.get("points", 0)
        live = "yes" if attr.get("live") else "no"

        page = asc.get(
            f"/gameCenterAchievements/{ach['id']}/localizations"
            "?limit=50&include=gameCenterAchievementImage")
        locs = page.get("data", [])
        included = {r["id"] for r in page.get("included", [])
                    if r["type"] == "gameCenterAchievementImages"}
        have = {loc["attributes"]["locale"] for loc in locs}
        with_image = sum(
            1 for loc in locs
            if (rel := loc.get("relationships", {}).get("gameCenterAchievementImage", {}))
            and (d := rel.get("data")) and d.get("id") in included)

        gap = (expected - have) or with_image < len(locs) or not locs
        if gap:
            incomplete += 1
        loc_str = ",".join(sorted(have)) if have else "(none)"
        print(f"{name:<26} {points:>6} {loc_str:<14} "
              f"{f'{with_image}/{len(locs)}':<6} {live}{'  ⚠' if gap else ''}")

    print()
    if incomplete:
        print(f"⚠  {incomplete} achievement(s) missing a locale or image.")
    else:
        print("✓ All achievements have every expected locale and an image each.")


if __name__ == "__main__":
    main()
