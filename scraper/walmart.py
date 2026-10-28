"""Walmart.ca adapter (best effort).

Walmart.ca is a Next.js app: search result pages embed the product list in a
__NEXT_DATA__ JSON blob. Store pricing depends on cookies naming the store, so
we pin the Red Deer store. Walmart often blocks datacenter IPs; when that
happens this adapter reports it and the app falls back to manual items.
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request

from common import SEARCH_TERMS, guess_taxable, item, parse_size

UA = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
# Fill in once the closest Red Deer store id is confirmed (see data/report.json
# and the probe output in the workflow log).
STORE_ID = ""  # Walmart 6375 50 Ave, Red Deer: collected by tools/local_scraper instead
POSTAL = "T4N 0A1"


def fetch(url):
    cookies = f"walmart.nearestPostalCode={urllib.parse.quote(POSTAL)}; defaultNearestStoreId={STORE_ID}; deliveryCatchmentStoreId={STORE_ID}"
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en-CA", "Cookie": cookies,
                                               "Accept": "text/html,application/xhtml+xml"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read().decode("utf-8", "replace")


def products_from(html):
    m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        return []
    data = json.loads(m.group(1))
    found = []

    def walk(o):
        if isinstance(o, dict):
            if "usItemId" in o and "name" in o and ("priceInfo" in o or "price" in o):
                found.append(o)
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(data)
    return found


def scrape():
    if not STORE_ID:
        # Walmart ignores the postal-code cookie and serves a default store (1061),
        # so unpinned results would not be Red Deer prices. Skip until pinned.
        print('[walmart] skipped: Red Deer store id not pinned yet')
        return [], []
    out = {}
    for term in SEARCH_TERMS[:60]:
        try:
            html = fetch("https://www.walmart.ca/en/search?q=" + urllib.parse.quote(term))
        except Exception as e:
            print(f"[walmart] '{term}' failed: {e}", file=sys.stderr)
            if "403" in str(e) or "412" in str(e) or "429" in str(e):
                break
            continue
        if term == SEARCH_TERMS[0]:
            ids = sorted(set(re.findall(r'"(?:storeId|nearestStoreId|defaultNearestStoreId)"\s*:\s*"?(\d+)', html)))
            print(f"[walmart] store ids mentioned in page: {ids}; sample: {json.dumps((products_from(html) or [{}])[0])[:1500]}")
        for p in products_from(html):
            pi = p.get("priceInfo") or {}
            price = (pi.get("currentPrice") or {}).get("price") or p.get("price")
            if not isinstance(price, (int, float)):
                continue
            size, unit = parse_size(p.get("name", ""))
            img = (p.get("imageInfo") or {}).get("thumbnailUrl") or p.get("image")
            it = item("walmart", p["usItemId"], p["name"], price, brand=p.get("brand"), img=img,
                      size=size or 1, unit=unit or "each", taxable=guess_taxable(p.get("name")),
                      url="https://www.walmart.ca" + (p.get("canonicalUrl") or ""))
            out[it["id"]] = it
        time.sleep(0.6)
    print(f"[walmart] {len(out)} items")
    stores = [{"id": "walmart", "name": "Walmart", "color": 0xFF0071CE, "location": "Red Deer", "online": True}]
    return stores, list(out.values())
