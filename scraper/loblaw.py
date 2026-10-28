"""Real Canadian Superstore / Wholesale Club via the PC Express API.

The store locator is queried for Red Deer, AB so we only ever list what the
Red Deer store really stocks for pickup (not Calgary-only or delivery-only).
"""
import datetime
import json
import sys
import time
import traceback
import urllib.request

from common import SEARCH_TERMS, guess_taxable, item, parse_size

API = "https://api.pcexpress.ca/pcx-bff/api"
APIKEY = "C1xujSegT5j3ap3yexJjqhOfELwGKYvz"  # public key used by the Loblaw web apps
UA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36"

BANNERS = {
    "superstore": {"banner": "superstore", "name": "Real Canadian Superstore", "color": 0xFFD9232D},
    "wholesaleclub": {"banner": "wholesaleclub", "name": "Wholesale Club", "color": 0xFFE8731A},
}
MAX_PER_TERM = 48


def call(path, banner, body=None):
    headers = {
        "x-apikey": APIKEY, "Site-Banner": banner, "Accept": "application/json",
        "Content-Type": "application/json", "User-Agent": UA,
        "Origin": f"https://www.{'realcanadiansuperstore' if banner == 'superstore' else 'wholesaleclub'}.ca",
        "x-application-type": "Web", "x-loblaw-tenant-id": "ONLINE_GROCERIES",
    }
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{API}{path}", data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read())


def find_store(banner_key, city="Red Deer"):
    banner = BANNERS[banner_key]["banner"]
    locs = call(f"/v1/pickup-locations?bannerIds={banner}", banner)
    hits = [l for l in locs if (l.get("address", {}).get("town", "") or "").lower() == city.lower()
            and (l.get("address", {}).get("region", "") or "").upper() in ("AB", "ALBERTA")]
    if hits:
        print(f"[{banner_key}] raw location sample: {json.dumps(hits[0])[:800]}")
    print(f"[{banner_key}] pickup locations in {city}: {[(h.get('id'), h.get('name'), h.get('address', {}).get('line1')) for h in hits]}")
    return hits


def search(banner_key, store_id, term):
    banner = BANNERS[banner_key]["banner"]
    body = {
        "pagination": {"from": 0, "size": MAX_PER_TERM}, "banner": banner,
        "cartId": "00000000-0000-0000-0000-000000000000", "lang": "en",
        "date": datetime.date.today().strftime("%d%m%Y"), "storeId": str(store_id),
        "pcId": False, "pickupType": "STORE", "offerType": "ALL", "term": term,
        "userData": {"domainUserId": "00000000-0000-0000-0000-000000000000", "sessionId": "00000000-0000-0000-0000-000000000000"},
    }
    return call("/v2/products/search", banner, body)


def to_item(banner_key, p):
    prices = p.get("prices") or {}
    price = (prices.get("price") or {}).get("value")
    if price is None or p.get("inventoryIndicator") == "OUT_OF_STOCK":
        return None
    was = (prices.get("wasPrice") or {}).get("value")
    sizing = p.get("packageSizing") or ""
    size, unit = parse_size(sizing)
    variable = (prices.get("price") or {}).get("unit") in ("lb", "kg", "100g") or "approx" in sizing.lower() or "per" in sizing.lower()
    if variable:
        pu = (prices.get("price") or {}).get("unit") or "lb"
        size, unit = (1, "lb" if pu == "lb" else "kg") if pu in ("lb", "kg") else (100, "g")
    elif size is None:
        # fall back to the comparison price ("$0.45 / 100g") when the pack size is missing
        cmp_ = (prices.get("comparisonPrices") or [{}])[0]
        if cmp_.get("value") and cmp_.get("quantity") and cmp_.get("unit"):
            unit = {"g": "g", "ml": "ml", "ea": "each", "kg": "kg", "l": "l"}.get(cmp_["unit"], "each")
            size = float(price) / float(cmp_["value"]) * float(cmp_["quantity"])
        else:
            size, unit = 1, "each"
    imgs = p.get("productImage") or []
    img = (imgs[0].get("imageUrl") if imgs else None)
    crumbs = " ".join(c.get("name", "") if isinstance(c, dict) else str(c) for c in (p.get("breadcrumbs") or []))
    cat = (p.get("breadcrumbs") or [{}])[0].get("name", "") if p.get("breadcrumbs") else ""
    return item(banner_key, p["code"], p.get("name", ""), price,
                brand=p.get("brand"), img=img, was=was, size=round(size, 3), unit=unit,
                variable=variable, taxable=guess_taxable(p.get("name"), crumbs), cat=cat,
                url=f"https://www.{'realcanadiansuperstore' if banner_key == 'superstore' else 'wholesaleclub'}.ca{p.get('link', '')}")


def scrape(banner_key):
    out, stores = {}, []
    locs = find_store(banner_key)
    if not locs:
        print(f"[{banner_key}] no Red Deer store found", file=sys.stderr)
        return [], []
    loc = locs[0]
    loc["id"] = loc.get("storeId") or loc.get("id") or loc.get("locationId")
    print(f"[{banner_key}] using store id {loc['id']}")
    stores.append({"id": banner_key, "name": BANNERS[banner_key]["name"], "color": BANNERS[banner_key]["color"],
                   "location": f"{loc.get('address', {}).get('line1', '')}, Red Deer", "online": True})
    for term in SEARCH_TERMS:
        try:
            res = search(banner_key, loc["id"], term)
        except Exception as e:
            print(f"[{banner_key}] '{term}' failed: {type(e).__name__} {e}", file=sys.stderr)
            if term == SEARCH_TERMS[0]:
                traceback.print_exc()
            if "403" in str(e) or "401" in str(e):
                break  # blocked: don't hammer
            continue
        if term == SEARCH_TERMS[0]:
            print(f"[{banner_key}] raw product sample: {json.dumps((res.get('results') or [{}])[0])[:1500]}")
        for p in res.get("results", []):
            try:
                it = to_item(banner_key, p)
            except Exception as e:
                print("parse error", e, file=sys.stderr)
                continue
            if it:
                out[it["id"]] = it
        time.sleep(0.4)
    print(f"[{banner_key}] {len(out)} items")
    return stores, list(out.values())
