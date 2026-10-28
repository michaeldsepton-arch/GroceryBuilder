#!/usr/bin/env python3
"""Builds data/catalog.json.gz from every store adapter that works.

Each adapter is isolated: a blocked or broken store is reported and skipped so
the others still publish. Usage: python scraper/scrape.py [store ...]
"""
import datetime
import gzip
import json
import pathlib
import sys
import traceback

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import loblaw  # noqa: E402

ADAPTERS = {
    "superstore": lambda: loblaw.scrape("superstore"),
    "wholesaleclub": lambda: loblaw.scrape("wholesaleclub"),
}
try:
    import walmart  # noqa: E402
    ADAPTERS["walmart"] = walmart.scrape
except Exception:  # adapter is optional
    traceback.print_exc()


def main():
    wanted = sys.argv[1:] or list(ADAPTERS)
    stores, items, report = [], [], {}
    for name in wanted:
        try:
            s, i = ADAPTERS[name]()
            stores += s
            items += i
            report[name] = len(i)
        except Exception as e:
            traceback.print_exc()
            report[name] = f"FAILED: {e}"
    out = {"generated": datetime.datetime.now(datetime.timezone.utc).isoformat(), "stores": stores, "items": items}
    path = pathlib.Path(__file__).parent.parent / "data"
    path.mkdir(exist_ok=True)
    with gzip.open(path / "catalog.json.gz", "wt", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"))
    (path / "report.json").write_text(json.dumps(report, indent=2))
    print("REPORT", report)
    if not items:
        sys.exit("No items scraped from any store")


if __name__ == "__main__":
    main()
