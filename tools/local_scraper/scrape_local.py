#!/usr/bin/env python3
"""Budget Basket price collector - runs on YOUR computer, from your home connection.

It drives a real Chromium window the way you would: you pick the Red Deer store
once on each site (--setup), then it searches every term in scraper/terms.txt and
records the product data the page itself loads (prices, sale prices, sizes,
images). Results go to data/catalog.json.gz and, if the GitHub CLI is logged in,
are uploaded to the `catalog` release the app downloads.

  python scrape_local.py --setup          # once: choose your stores in the browser
  python scrape_local.py                  # collect prices + upload
  python scrape_local.py superstore       # only some stores
  python scrape_local.py --no-upload      # collect only
"""
import argparse
import datetime
import gzip
import json
import pathlib
import random
import re
import shutil
import subprocess
import sys
import time
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scraper"))

from common import SEARCH_TERMS  # noqa: E402
import loblaw  # noqa: E402
import walmart  # noqa: E402

PROFILE = pathlib.Path.home() / ".budget-basket-browser"
OUT = ROOT / "data"

STORES = {
    "superstore": {
        "home": "https://www.realcanadiansuperstore.ca/en",
        "search": "https://www.realcanadiansuperstore.ca/en/search?search-bar={q}",
        "pick": "Choose pickup location: Real Canadian Superstore 51 Avenue (5016 51 Ave, Red Deer).",
        "kind": "loblaw", "expect_store_id": "1579",
        "meta": {"id": "superstore", "name": "Real Canadian Superstore", "color": 0xFFD9232D,
                 "location": "5016 51 Ave, Red Deer", "online": True},
    },
    "wholesaleclub": {
        "home": "https://www.wholesaleclub.ca/en",
        "search": "https://www.wholesaleclub.ca/en/search?search-bar={q}",
        "pick": "Choose pickup location: Wholesale Club 67th Street (6350 67th St, Red Deer).",
        "kind": "loblaw", "expect_store_id": None,
        "meta": {"id": "wholesaleclub", "name": "Wholesale Club", "color": 0xFFE8731A,
                 "location": "6350 67th St, Red Deer", "online": True},
    },
    "walmart": {
        "home": "https://www.walmart.ca/en",
        "search": "https://www.walmart.ca/en/search?q={q}",
        "pick": "Set your store to Walmart, 6375 50 Ave, Red Deer, AB T4N 3Z2 (store selector near the top).",
        "kind": "walmart", "expect_text": "6375 50",
        "meta": {"id": "walmart", "name": "Walmart", "color": 0xFF0071CE,
                 "location": "6375 50 Ave, Red Deer", "online": True},
    },
}


def launch(pw, headless):
    return pw.chromium.launch_persistent_context(
        str(PROFILE), headless=headless, locale="en-CA", timezone_id="America/Edmonton",
        viewport={"width": 1280, "height": 900})


def setup(pw, keys):
    ctx = launch(pw, headless=False)
    for k in keys:
        cfg = STORES[k]
        page = ctx.new_page()
        page.goto(cfg["home"])
        print(f"\n[{k}] {cfg['pick']}\n    Press Enter here when done...")
        input()
        page.close()
    ctx.close()
    print("Saved. Now run without --setup.")


def collect_loblaw(ctx, key, cfg):
    items, seen_store = {}, set()
    page = ctx.new_page()
    captured = []

    def on_response(resp):
        if "products/search" in resp.url and resp.request.method == "POST":
            try:
                body = json.loads(resp.request.post_data or "{}")
                seen_store.add(str(body.get("storeId")))
                captured.append(resp.json())
            except Exception:
                pass

    page.on("response", on_response)
    for term in SEARCH_TERMS:
        captured.clear()
        try:
            page.goto(cfg["search"].format(q=urllib.parse.quote(term)), wait_until="networkidle", timeout=60000)
        except Exception as e:
            print(f"  [{key}] '{term}': {e}")
        want = cfg.get("expect_store_id")
        if want and seen_store and want not in seen_store:
            sys.exit(f"[{key}] the site is using store {seen_store}, expected {want}. Run --setup again.")
        for res in captured:
            for p in res.get("results", []):
                try:
                    it = loblaw.to_item(key, p)
                except Exception:
                    continue
                if it:
                    items[it["id"]] = it
        print(f"  [{key}] {term}: total {len(items)}")
        time.sleep(random.uniform(1.5, 3.5))
    print(f"[{key}] store ids used by the site: {seen_store}")
    page.close()
    return list(items.values())


def collect_walmart(ctx, key, cfg):
    items, page = {}, ctx.new_page()
    warned = False
    for term in SEARCH_TERMS:
        try:
            page.goto(cfg["search"].format(q=urllib.parse.quote(term)), wait_until="domcontentloaded", timeout=60000)
            page.wait_for_selector("script#__NEXT_DATA__", state="attached", timeout=20000)
            html = page.content()
        except Exception as e:
            print(f"  [{key}] '{term}': {e}")
            continue
        if not warned and cfg["expect_text"] not in html:
            print(f"  [{key}] WARNING: could not confirm the store is {cfg['expect_text']}... "
                  "run --setup walmart and select the Red Deer store.")
            warned = True
        for p in walmart.products_from(html):
            pi = p.get("priceInfo") or {}
            price = (pi.get("currentPrice") or {}).get("price") or p.get("price")
            if not isinstance(price, (int, float)):
                continue
            was = (pi.get("wasPrice") or {}).get("price")
            size, unit = walmart.parse_size(p.get("name", ""))
            img = (p.get("imageInfo") or {}).get("thumbnailUrl") or p.get("image")
            it = walmart.item("walmart", p["usItemId"], p["name"], price, brand=p.get("brand"), img=img,
                              was=was if isinstance(was, (int, float)) and was > price else None,
                              size=size or 1, unit=unit or "each", taxable=walmart.guess_taxable(p.get("name")),
                              url="https://www.walmart.ca" + (p.get("canonicalUrl") or ""))
            items[it["id"]] = it
        print(f"  [{key}] {term}: total {len(items)}")
        time.sleep(random.uniform(1.5, 3.5))
    page.close()
    return list(items.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stores", nargs="*", help=f"any of {', '.join(STORES)} (default: all)")
    ap.add_argument("--setup", action="store_true")
    ap.add_argument("--no-upload", action="store_true")
    ap.add_argument("--headless", action="store_true", help="hide the browser window")
    a = ap.parse_args()
    keys = a.stores or list(STORES)

    from playwright.sync_api import sync_playwright
    with sync_playwright() as pw:
        if a.setup:
            return setup(pw, keys)
        ctx = launch(pw, a.headless)
        stores, items, report = [], [], {}
        for k in keys:
            cfg = STORES[k]
            try:
                got = collect_loblaw(ctx, k, cfg) if cfg["kind"] == "loblaw" else collect_walmart(ctx, k, cfg)
            except SystemExit:
                raise
            except Exception as e:
                print(f"[{k}] failed: {e}")
                got = []
            if got:
                stores.append(cfg["meta"])
                items += got
            report[k] = len(got)
        ctx.close()

    if not items:
        sys.exit("Nothing collected; not publishing.")
    OUT.mkdir(exist_ok=True)
    cat = {"generated": datetime.datetime.now(datetime.timezone.utc).isoformat(), "stores": stores, "items": items}
    with gzip.open(OUT / "catalog.json.gz", "wt", encoding="utf-8") as f:
        json.dump(cat, f, separators=(",", ":"))
    (OUT / "report.json").write_text(json.dumps(report, indent=2))
    print("Collected:", report, "-> data/catalog.json.gz")

    if a.no_upload:
        return
    if not shutil.which("gh"):
        print("GitHub CLI (gh) not found; upload data/catalog.json.gz to the 'catalog' release manually.")
        return
    repo = "michaeldsepton-arch/GroceryBuilder"
    if subprocess.run(["gh", "release", "view", "catalog", "-R", repo], capture_output=True).returncode != 0:
        subprocess.run(["gh", "release", "create", "catalog", "-R", repo, "--prerelease", "--title",
                        "Price catalog (auto-updated)", "--notes", "Scraped Red Deer prices. Not an app release."], check=True)
    subprocess.run(["gh", "release", "upload", "catalog", "-R", repo, "--clobber",
                    str(OUT / "catalog.json.gz"), str(OUT / "report.json")], check=True)
    print("Uploaded. Open the app -> More -> Refresh prices.")


if __name__ == "__main__":
    main()
