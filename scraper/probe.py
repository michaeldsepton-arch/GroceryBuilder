"""Diagnostics for the scrapers: shows what each store's server answers so the adapters can be fixed."""
import copy
import datetime
import json
import re
import sys
import urllib.error
import urllib.request

import loblaw

banner, sid = "superstore", "1579"
base = {
    "pagination": {"from": 0, "size": 10}, "banner": banner,
    "cartId": "00000000-0000-0000-0000-000000000000", "lang": "en",
    "date": datetime.date.today().strftime("%d%m%Y"), "storeId": sid,
    "pcId": False, "pickupType": "STORE", "offerType": "ALL", "term": "milk",
    "userData": {"domainUserId": "00000000-0000-0000-0000-000000000000", "sessionId": "00000000-0000-0000-0000-000000000000"},
}
WEB = {"User-Agent": loblaw.UA, "Accept": "text/html,application/json"}


def http(label, url, body=None, method=None, headers=None, show=600):
    h = dict(WEB)
    h.update(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=h, method=method or ("POST" if data else "GET"))
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            txt = r.read().decode("utf-8", "replace")
            print(f"== {label}: {r.status} len={len(txt)}\n{txt[:show]}")
            return txt
    except urllib.error.HTTPError as e:
        print(f"== {label}: HTTP {e.code} {e.read().decode('utf-8', 'replace')[:500]}")
    except Exception as e:
        print(f"== {label}: {type(e).__name__} {e}")


def lob(label, path, body=None, method=None, extra=None):
    h = {"x-apikey": loblaw.APIKEY, "Site-Banner": banner, "Content-Type": "application/json",
         "Origin": "https://www.realcanadiansuperstore.ca", "Referer": "https://www.realcanadiansuperstore.ca/"}
    h.update(extra or {})
    return http(label, loblaw.API + path, body, method, h)



PCX = {"x-application-type": "Web", "x-loblaw-tenant-id": "ONLINE_GROCERIES", "Business-User-Agent": "PCXWEB"}
lob("G pcx headers, no accept-language", "/v2/products/search", base, extra=PCX)
b = copy.deepcopy(base); b["lang"] = "en"
lob("H pcx + Accept-Language en", "/v2/products/search", b, extra=dict(PCX, **{"Accept-Language": "en"}))
b = copy.deepcopy(base); b["cartId"] = "0"; b.pop("userData")
lob("I pcx, no userData, cartId 0", "/v2/products/search", b, extra=PCX)

# Walmart: which store does the site think we are near Blackfalds / Red Deer?
for postal in ["T4M 0A1", "T4N 0A1"]:
    ck = "walmart.nearestPostalCode=" + postal.replace(" ", "%20")
    t = http("walmart search near " + postal, "https://www.walmart.ca/en/search?q=milk", headers={"Accept-Language": "en-CA", "Cookie": ck}, show=0)
    if t:
        m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', t, re.S)
        print("   has NEXT_DATA:", bool(m))
        blob = m.group(1) if m else t
        for key in ["Red Deer", "Blackfalds"]:
            print("   ", key, [blob[max(0, i.start()-120):i.end()+120] for i in re.finditer(key, blob)][:3])
        print("   store-ish keys:", sorted(set(re.findall(r'"([A-Za-z]*[sS]tore[A-Za-z]*)"\s*:\s*("?[^,}\]]{1,40})', blob)))[:25])
for u in ["https://www.walmart.ca/api/bsp/stores?lat=52.27&lng=-113.81",
          "https://www.walmart.ca/en/stores-near-me/api/search?postalCode=T4M0A1"]:
    http("walmart store api " + u, u, headers={"Accept-Language": "en-CA"}, show=400)

t = http("freshco home", "https://www.freshco.com/", show=0)
if t:
    print("   api-ish urls:", sorted(set(re.findall(r'https://[a-z0-9.-]*(?:sobeys|freshco|voila|empire)[a-z0-9./_-]*api[a-z0-9./_?=&-]*', t)))[:15])
    print("   red deer:", [t[max(0, i.start()-100):i.end()+100] for i in re.finditer("Red Deer", t)][:2])
