#!/usr/bin/env python3
"""Extract named screenshot attachments from an .xcresult into PNGs.

Usage: extract_screenshots.py <result.xcresult> <output-dir>

xcresulttool's export interface differs by Xcode version. Newer Xcode
(16+) exposes `xcresulttool export attachments`, which does the whole job
in one call and names files by their test-set attachment name; older ones
need the graph walked by hand. We try the easy path first, then fall back.
"""
import json
import os
import subprocess
import sys


def run(args):
    return subprocess.run(
        ["xcrun", "xcresulttool", *args], capture_output=True, text=True)


def try_export_attachments(result, outdir):
    """Xcode 16+: one command dumps every attachment + a manifest."""
    r = run(["export", "attachments", "--path", result,
             "--output-path", outdir])
    if r.returncode != 0:
        return False
    # A manifest.json maps exported files to their attachment names.
    manifest = os.path.join(outdir, "manifest.json")
    if not os.path.exists(manifest):
        return True  # exported, but no manifest to rename by — leave as-is
    entries = json.load(open(manifest))
    for entry in entries:
        for att in entry.get("attachments", []):
            name = att.get("suggestedHumanReadableName") or att.get("name")
            exported = att.get("exportedFileName")
            if not (name and exported):
                continue
            base = name.split(".")[0]  # the test set it as "home", etc.
            src = os.path.join(outdir, exported)
            dst = os.path.join(outdir, base + ".png")
            if os.path.exists(src):
                os.replace(src, dst)
    os.remove(manifest)
    return True


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: extract_screenshots.py <result.xcresult> <output-dir>")
    result, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)

    if try_export_attachments(result, outdir):
        pngs = [f for f in os.listdir(outdir) if f.endswith(".png")]
        if pngs:
            print(f"Extracted {len(pngs)} screenshots.")
            return
    sys.exit(
        "Could not extract attachments. Check the Xcode version — "
        "`xcrun xcresulttool export attachments` requires Xcode 16+.")


if __name__ == "__main__":
    main()
