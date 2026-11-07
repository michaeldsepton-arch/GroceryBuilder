#!/usr/bin/env python3
"""Preview which items the app charges 5% GST on. Same rules as lib/data/tax.dart (assets/seed/tax_terms.json).
Usage: python tools/tax_check.py catalog.json.gz [name-fragment ...]   (prints counts and samples)
"""
import collections
import gzip
import json
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import scope_check as sc  # noqa: E402

RULES = json.loads((pathlib.Path(__file__).resolve().parent.parent / "assets/seed/tax_terms.json").read_text(encoding="utf-8"))


def _any(text, terms):
    s, t = sc.tokens(text)
    return any(sc.has(s, t, x) for x in terms)


def is_taxable(name, brand="", cat=""):
    text = f"{name} {brand}"
    if _any(text, RULES["nonfood"]):
        return True
    shop = sc.category(name, cat)
    if shop in RULES["taxable_categories"]:
        return True
    if _any(text, RULES["zero"]):
        return False
    if _any(text, RULES["taxable"]):
        return True
    return shop == "Baby" and _any(text, RULES["baby_taxable"])


def main():
    raw = pathlib.Path(sys.argv[1]).read_bytes()
    items = json.loads(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)["items"]
    frags = [a.lower() for a in sys.argv[2:]]
    by = collections.defaultdict(lambda: [0, 0])
    sample = collections.defaultdict(list)
    for i in items:
        c = sc.category(i["name"], i.get("cat") or "")
        t = is_taxable(i["name"], i.get("brand") or "", i.get("cat") or "")
        by[c][t] += 1
        sample[(c, t)].append(i["name"])
        if frags and any(f in i["name"].lower() for f in frags):
            print(("TAX  " if t else "free ") + c + " | " + i["name"])
    if frags:
        return
    random.seed(2)
    for c, (free, tax) in sorted(by.items()):
        print(f"{c}: {tax} taxable, {free} free")
        for t in (True, False):
            for n in random.sample(sample[(c, t)], min(6, len(sample[(c, t)]))):
                print(("   TAX  " if t else "   free ") + n)


if __name__ == "__main__":
    main()
