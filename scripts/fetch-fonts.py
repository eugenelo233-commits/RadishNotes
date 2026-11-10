#!/usr/bin/env python3
"""Download pinned bundled fonts; verify existing files and OFL notices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="Verify without network or writes")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / "Resources" / "Fonts"
manifest = json.loads((root / "manifest.json").read_text())
for family in manifest:
    for item in family["files"]:
        dest = root / item["file"]
        def valid(data):
            return len(data) == item["bytes"] and hashlib.sha256(data).hexdigest() == item["sha256"]
        if dest.exists() and valid(dest.read_bytes()):
            print("OK", dest.name)
            continue
        if args.check:
            raise SystemExit("Missing or invalid font/resource: " + dest.name + "; run python3 scripts/fetch-fonts.py")
        print("Downloading", dest.name, flush=True)
        request = urllib.request.Request(item["url"], headers={"User-Agent": "RadishNotes-font-fetcher"})
        with urllib.request.urlopen(request, timeout=90) as response:
            data = response.read()
        if not valid(data):
            raise SystemExit("Checksum mismatch: " + dest.name)
        temp = dest.with_name(dest.name + ".download")
        temp.write_bytes(data)
        os.replace(temp, dest)
print("All bundled fonts and licenses verified.")
