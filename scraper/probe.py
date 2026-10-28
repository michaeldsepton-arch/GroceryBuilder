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
WEB = {"User-Agent": loblaw.UA, "Accept-Language": "en-CA", "Accept": "text/html,application/json"}


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


lob("A v2 current", "/v2/products/search", base)
b = copy.deepcopy(base); b.pop("userData")
lob("B no userData", "/v2/products/search", b)
lob("C v1", "/v1/products/search", base)
b = copy.deepcopy(base); b.pop("pickupType"); b.pop("offerType")
lob("D minimal", "/v2/products/search", b)
lob("E extra headers", "/v2/products/search", base,
    extra={"x-application-type": "Web", "x-loblaw-tenant-id": "ONLINE_GROCERIES", "Business-User-Agent": "PCXWEB"})
lob("F GET search", "/v1/products/search?term=milk&banner=superstore&storeId=1579&lang=en", method="GET")

# Walmart: find Red Deer / Blackfalds stores
for u in ["https://www.walmart.ca/en/stores-near-me/red-deer-supercentre",
          "https://www.walmart.ca/en/stores-near-me",
          "https://www.walmart.ca/en/stores-near-me/alberta"]:
    t = http("walmart " + u, u, show=200)
    if t:
        print("   red deer mentions:", sorted(set(re.findall(r'[^"<>]{0,80}Red Deer[^"<>]{0,80}', t)))[:12])
        print("   store ids:", sorted(set(re.findall(r'/stores-near-me/[a-z0-9-]+/(\d+)', t)))[:20])
for u in ["https://www.shoppersdrugmart.ca/", "https://www.freshco.com/"]:
    http("reach " + u, u, show=150)
