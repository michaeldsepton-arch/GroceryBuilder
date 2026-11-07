#!/usr/bin/env python3
"""Turn the items the family flagged in the app ("Flagged items" > Send) into removal rules, safely.

Nothing is deleted from the clipper data or the backups. Removal happens in publish.py through
tools/clipper/exclude.json, and every removed item is archived in
~/Documents/BudgetBasket-catalog-backups/removed-<time>.json.gz. To bring something back, delete its rule from
exclude.json and publish again (the raw exports in the same folder still hold every item).

  python tools/apply_flags.py flagged.json            show each flagged item and the similar items it would remove
  python tools/apply_flags.py flagged.json --ids      add the flagged items themselves (by id) to exclude.json
  python tools/apply_flags.py --phrase "word or phrase" [--phrase ...]   add name phrases to exclude.json (after reviewing)
  python tools/apply_flags.py --preview "phrase"      list what a phrase would remove, change nothing
"""
import gzip
import json
import pathlib
import re
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
EXCLUDE = HERE / "clipper" / "exclude.json"
URL = "https://github.com/michaeldsepton-arch/GroceryBuilder/releases/download/catalog/catalog.json.gz"


def load_catalog():
    raw = urllib.request.urlopen(URL, timeout=60).read()
    return json.loads(gzip.decompress(raw))["items"]


def rules():
    try:
        return json.loads(EXCLUDE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"ids": [], "phrases": []}


def save(r):
    r["ids"] = sorted(set(r["ids"]))
    r["phrases"] = sorted(set(r["phrases"]))
    EXCLUDE.write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")


def phrase_rx(p):
    return re.compile(r"(?<![a-z0-9])" + re.escape(p.lower()) + r"s?(?![a-z0-9])")


def core(name):
    """The product's own words: no sizes, counts or punctuation."""
    n = re.sub(r"\b\d[\d.,/x×]*\s*(kg|g|lbs?|oz|ml|l|ct|pk|pack|count)?\b", " ", name.lower())
    return [w for w in re.findall(r"[a-z]+", n) if len(w) > 2]


def main():
    a = sys.argv[1:]
    r = rules()
    if "--phrase" in a:
        for k, v in enumerate(a):
            if v == "--phrase":
                r["phrases"].append(a[k + 1])
        save(r)
        print("rules now:", len(r["ids"]), "ids,", len(r["phrases"]), "phrases")
        return
    items = load_catalog()
    if "--preview" in a:
        rx = phrase_rx(a[a.index("--preview") + 1])
        hits = [i for i in items if rx.search(i["name"].lower())]
        print(len(hits), "items would be removed")
        for i in hits[:60]:
            print("  ", i["store"], "|", i["name"])
        return
    flagged = json.loads(pathlib.Path(a[0]).read_text(encoding="utf-8"))["flagged"]
    byid = {i["id"]: i for i in items}
    for f in flagged:
        it = byid.get(f["item_id"]) or {"name": f["name"], "store": f["store_id"]}
        words = core(it["name"])
        print(f"\nFLAGGED: {it['name']}  [{it['store']}]")
        if "--ids" in a:
            r["ids"].append(f["item_id"])
            continue
        # similar = same product words, in any store (a suggestion only; review before adding a phrase)
        similar = [i for i in items if i["id"] != f["item_id"] and core(i["name"]) == words][:15]
        print(f"  {len(similar)} with exactly the same words" if similar else "  no exact twins; consider a --phrase from its key word(s)")
        for i in similar:
            print("    ", i["store"], "|", i["name"])
    if "--ids" in a:
        save(r)
        print("\nadded", len(flagged), "ids to exclude.json")


if __name__ == "__main__":
    main()
