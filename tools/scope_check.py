#!/usr/bin/env python3
"""Preview what the app's "grocery and home items only" filter does to a catalog.

Same rules as lib/data/scope.dart (assets/seed/scope_terms.json). Usage:
  python tools/scope_check.py path/to/catalog.json.gz [more samples: N]
Prints how many items stay, samples of removed items, and the category split.
"""
import collections
import gzip
import json
import pathlib
import random
import re
import sys

RULES = json.loads((pathlib.Path(__file__).resolve().parent.parent / "assets/seed/scope_terms.json").read_text(encoding="utf-8"))


def tokens(text):
    s = text.lower()
    t = set(re.findall(r"[a-z0-9']+", s))
    t |= {w[:-1] for w in t if len(w) > 3 and w.endswith("s")}
    return s, t


def has(s, t, term):
    return term in s if (" " in term or "-" in term) else term in t


def in_scope(name, brand="", cat=""):
    s, t = tokens(f"{name} {brand}")
    if any(has(s, t, x) for x in RULES.get("keep", [])):
        return True
    if any(has(s, t, x) for x in RULES["block"]):
        return False
    if cat:
        cs, ct = tokens(cat)
        if any(has(cs, ct, x) for x in RULES["block_category"]):
            return False
    return True


def category(name, cat=""):
    for text in (cat, name):
        if not text:
            continue
        s, t = tokens(text)
        for c in RULES["categories"]:
            if any(has(s, t, x) for x in c["terms"]):
                return c["name"]
    return "Other"


def main():
    path = sys.argv[1]
    raw = pathlib.Path(path).read_bytes()
    data = json.loads(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)
    items = data["items"]
    flags = [in_scope(i["name"], i.get("brand") or "", i.get("cat") or "") for i in items]
    keep = [i for i, ok in zip(items, flags) if ok]
    gone = [i for i, ok in zip(items, flags) if not ok]
    print(f"{len(items)} items -> {len(keep)} kept, {len(gone)} removed")
    random.seed(1)
    for i in random.sample(gone, min(60, len(gone))):
        print("  removed:", i["store"], "|", i["name"][:70])
    print(collections.Counter(category(i["name"], i.get("cat") or "") for i in keep).most_common())


if __name__ == "__main__":
    main()
