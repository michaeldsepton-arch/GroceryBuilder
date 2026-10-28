#!/usr/bin/env python3
"""Download a freely licensed photo for each seed item from Wikimedia Commons.

Runs in CI before the APK build (the build sandbox has open internet). Images
land in assets/seed/images/<id>.jpg and credits in assets/seed/ATTRIBUTION.md.
Items without a result simply keep the in-app placeholder.
"""
import json
import pathlib
import re
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEED = ROOT / "assets" / "seed"
UA = "BudgetBasketBuild/1.0 (https://github.com/michaeldsepton-arch/GroceryBuilder)"
OK_LICENSES = re.compile(r"^(cc0|cc[- ]by(-sa)?[- ]?[\d.]*|public domain|pd)", re.I)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def find(term):
    q = urllib.parse.urlencode({
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": f"{term} filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 12,
        "prop": "imageinfo", "iiprop": "url|extmetadata|mime", "iiurlwidth": 600,
    })
    data = json.loads(get(f"https://commons.wikimedia.org/w/api.php?{q}"))
    pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0))
    for p in pages:
        info = (p.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        lic = meta.get("LicenseShortName", {}).get("value", "")
        if info.get("mime") != "image/jpeg" or not OK_LICENSES.match(lic.strip()):
            continue
        artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "unknown"))
        return info.get("thumburl") or info["url"], p["title"], lic, artist, info.get("descriptionurl", "")
    return None


def main():
    seed = json.loads((SEED / "halal.json").read_text())
    credits = ["# Seed image credits (Wikimedia Commons)\n"]
    for it in seed["items"]:
        out = SEED / "images" / f"{it['id']}.jpg"
        if out.exists():
            continue
        try:
            hit = find(it["search"])
            if not hit:
                print("no image for", it["id"])
                continue
            url, title, lic, artist, page = hit
            out.write_bytes(get(url))
            credits.append(f"- {it['name']}: {title} by {artist} ({lic}) {page}")
            print("ok", it["id"], title)
        except Exception as e:  # keep the build going; placeholder is used
            print("failed", it["id"], e, file=sys.stderr)
    (SEED / "ATTRIBUTION.md").write_text("\n".join(credits) + "\n")


if __name__ == "__main__":
    main()
