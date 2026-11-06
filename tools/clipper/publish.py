#!/usr/bin/env python3
"""Publish the clipper export so the app can download it, WITHOUT losing what is already there.

The app replaces its whole price list with the published file, so each publish must contain
everything still current. This merges the new export into the catalog already on GitHub:
- items are matched by id; the newer export wins;
- items not in this export stay unless they were last seen more than 45 days ago;
- stores are unioned;
- Walmart prices left in cents are repaired, and same name/brand/size/price duplicates collapse.
Usage: python publish.py [export.json.gz] [--existing current.json.gz] [--no-upload]
"""
import datetime
import gzip
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

REPO = "michaeldsepton-arch/GroceryBuilder"
URL = f"https://github.com/{REPO}/releases/download/catalog/catalog.json.gz"
STALE_DAYS = 45


def load(path_or_bytes):
    raw = path_or_bytes if isinstance(path_or_bytes, bytes) else open(path_or_bytes, "rb").read()
    return json.loads(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)


def fix_walmart(i):
    if i.get("store") != "walmart":
        return
    p = i["price"]
    if float(p).is_integer() and p >= 100 and int(p) % 100 != 0:
        i["price"] = round(p / 100, 2)
        w = i.get("was")
        if w and float(w).is_integer() and w >= 100 and int(w) % 100 != 0:
            i["was"] = round(w / 100, 2)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = sys.argv[1:]
    dl = os.path.join(os.path.expanduser("~"), "Downloads")
    import glob
    found = sorted(glob.glob(os.path.join(dl, "budget-basket-catalog*.json.gz")) + glob.glob(os.path.join(dl, "budget-basket-catalog*.txt")),
                   key=os.path.getmtime)
    src = args[0] if args else (found[-1] if found else None)
    if not src:
        sys.exit("No export found in Downloads. In the extension click Export prices for the app first.")
    new = load(src)
    old = {"stores": [], "items": [], "generated": None}
    if "--existing" in flags:
        old = load(flags[flags.index("--existing") + 1])
    else:
        try:
            old = load(urllib.request.urlopen(URL, timeout=60).read())
        except Exception as e:
            print("Could not read the catalog already published (", e, "), publishing the export alone.")
    now = datetime.datetime.utcnow()
    stamp_new = new.get("generated") or now.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    cutoff = now - datetime.timedelta(days=STALE_DAYS)

    def seen_of(i, fallback):
        try:
            return datetime.datetime.strptime((i.get("seen") or fallback or "")[:19], "%Y-%m-%dT%H:%M:%S")
        except ValueError:
            return now

    items = {}
    kept_old = 0
    for i in old.get("items", []):
        if seen_of(i, old.get("generated")) >= cutoff:
            items[i["id"]] = i
            kept_old += 1
    for i in new.get("items", []):
        i.setdefault("seen", stamp_new)
        items[i["id"]] = i
    stores = {s["id"]: s for s in old.get("stores", [])}
    stores.update({s["id"]: s for s in new.get("stores", [])})
    best = {}
    score = lambda x: (2 if x.get("img") else 0) + (1 if x.get("was") else 0) + (1 if x.get("pv") else 0)
    for i in items.values():
        fix_walmart(i)
        k = (i["store"], i["name"].lower().strip(), (i.get("brand") or "").lower().strip(), i.get("size"), i.get("unit"), i["price"])
        if k not in best or score(i) > score(best[k]):
            best[k] = i
    out = {"generated": now.strftime("%Y-%m-%dT%H:%M:%S.000Z"), "stores": list(stores.values()), "items": list(best.values())}
    counts = {}
    for i in out["items"]:
        counts[i["store"]] = counts.get(i["store"], 0) + 1
    print(f"export {len(new.get('items', []))} items + {kept_old} already published -> {len(out['items'])}: {counts}")
    # Safety copies: every export and every published catalog is kept on this PC with the date.
    bdir = os.path.join(os.path.expanduser("~"), "Documents", "BudgetBasket-catalog-backups")
    os.makedirs(bdir, exist_ok=True)
    stampname = now.strftime("%Y%m%d-%H%M%S")
    open(os.path.join(bdir, f"export-{stampname}.json.gz"), "wb").write(open(src, "rb").read())
    tmp = os.path.join(tempfile.gettempdir(), "catalog.json.gz")
    open(tmp, "wb").write(gzip.compress(json.dumps(out, separators=(",", ":")).encode()))
    open(os.path.join(bdir, f"published-{stampname}.json.gz"), "wb").write(open(tmp, "rb").read())
    if "--no-upload" in flags:
        print("wrote", tmp)
        return
    r = subprocess.run(["gh", "release", "upload", "catalog", tmp, "-R", REPO, "--clobber"])
    print("Done. In the app: More > Refresh prices." if r.returncode == 0 else "Upload failed. Is gh signed in? Run: gh auth login")


if __name__ == "__main__":
    main()
