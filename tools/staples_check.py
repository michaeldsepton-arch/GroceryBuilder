#!/usr/bin/env python3
"""Preview which items the app shows as 'everyday items' (assets/seed/staples.json).

Same rules as lib/data/staples.dart and lib/data/matching.dart (the word lists are read from matching.dart so
they cannot drift). Usage:
  python tools/staples_check.py catalog.json.gz                 counts per group and store
  python tools/staples_check.py catalog.json.gz --group veg     sample items of one group
  python tools/staples_check.py catalog.json.gz --entry Honey   sample items of one entry (name starts with)
  python tools/staples_check.py catalog.json.gz --dropped N     sample of in-scope items that are NOT everyday
  python tools/staples_check.py catalog.json.gz --photos        write the missing-photo report
"""
import collections
import gzip
import json
import math
import pathlib
import random
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import scope_check as sc  # noqa: E402

MATCHING = (ROOT / "lib/data/matching.dart").read_text(encoding="utf-8")
STAPLES = json.loads((ROOT / "assets/seed/staples.json").read_text(encoding="utf-8"))


def dart_set(name):
    m = re.search(r"const %s = \{(.*?)\};" % re.escape(name), MATCHING, re.S)
    return set(re.findall(r"'([^']+)'", m.group(1)))


def sing(w):
    if len(w) < 4:
        return w
    if w.endswith("ies"):
        return w[:-3] + "y"
    if w.endswith("oes"):
        return w[:-2]
    if w.endswith("ss"):
        return w
    if w.endswith("s"):
        return w[:-1]
    return w


PREPARED, NOISE, UNIT_WORDS = dart_set("_prepared"), dart_set("_noise"), dart_set("_unitWords")
HEADS, STRICT, DIVERTING, DIV_AFTER = dart_set("_heads"), dart_set("_strict"), dart_set("_diverting"), dart_set("_divertingAfter")
PREPARED_S, HEADS_S, STRICT_S = {sing(w) for w in PREPARED}, {sing(w) for w in HEADS}, {sing(w) for w in STRICT}
CUT = re.compile(r"\s(?:with|in|for|from|made|contains)\s|,|\s-\s|\||;", re.I)
CUT1 = re.compile(r"\s(?:with|in|for|from|made|contains)\s", re.I)


def tokens(s):
    return [sing(t) for t in re.split(r"[^a-z0-9]+", s.lower()) if t]


def main_tokens(name):
    cut = re.sub(r"[()®™&]", " ", CUT.split(name)[0])
    return [t for t in tokens(cut) if not re.match(r"^\d", t) and t not in UNIT_WORDS]


def relevance(name, brand, term_tokens):
    nt = main_tokens(name)
    if not term_tokens or not nt:
        return 0
    if name.split(",")[0].count("/") >= 2:
        return 0
    term_set = set(term_tokens)
    for t in term_tokens:
        if t not in nt:
            return 0
    whole = [t for t in tokens(re.sub(r"[()®™&]", " ", CUT1.split(name)[0])) if not re.match(r"^\d", t) and t not in UNIT_WORDS and len(t) > 1]
    for last in {nt[-1], *(whole[-1:])}:
        if last in HEADS_S and last not in term_set:
            return 0
    for k in range(0, len(nt) - len(term_tokens)):
        if nt[k:k + len(term_tokens)] == term_tokens and nt[k + len(term_tokens)] in DIV_AFTER and nt[k + len(term_tokens)] not in term_set:
            return 0
    for n in nt:
        if n in term_set:
            continue
        if n in STRICT_S or n in DIVERTING:
            return 0
    brand_set = set(tokens(brand))
    extra = bad = 0
    for n in nt:
        if n in term_set:
            continue
        if len(n) < 3 or n in NOISE or n in brand_set:
            continue
        extra += 1
        if n in PREPARED_S:
            bad += 1
    score = 1 / (1 + 0.25 * extra) - 0.5 * min(bad, 2)
    if nt[:len(term_tokens)] == term_tokens:
        score += 0.2
    if len(nt) >= len(term_tokens) and nt[len(nt) - len(term_tokens):] == term_tokens:
        score += 0.3
    if "/" in name:
        score -= 0.3
    return score


# Fresh food names are plain: the food is the last word, only package/size words may follow and no
# "processed" word may come before ("Ground Ginger", "Crispy Onions", "Ginger Beer" are not fresh ginger).
TAIL_OK = NOISE | set(STAPLES["rules"]["tail_ok"])
BAD_PREFIX = set(STAPLES["rules"]["bad_prefix"])


def plain(name, brand, pt, fresh=True, tails=None):
    nt = main_tokens(name)
    bset = set(tokens(brand))
    n = len(pt)
    for k in range(len(nt) - n, -1, -1):
        if nt[k:k + n] != pt:
            continue
        tail = [t for t in nt[k + n:] if t not in bset and len(t) > 1]
        head = [t for t in nt[:k] if t not in bset]
        bad_tail = [t for t in tail if t not in TAIL_OK]
        if not bad_tail and not (fresh and any(t in BAD_PREFIX for t in head)):
            return True
        if tails is not None:
            tails.update(bad_tail)
    return False


# ---- staples ----
ENTRIES = []  # dict per entry
for g in STAPLES["groups"]:
    gopts = g.get("opts", {})
    for e in g["items"]:
        opts = e[3] if len(e) > 3 else {}
        ENTRIES.append({"group": g["id"], "gname": g["name"], "name": e[0], "src": e[2],
                        "phrases": [p.strip().lower() for p in e[1].split("|") if p.strip()],
                        "x": [x.lower() for x in (opts.get("x", []) + gopts.get("x", []))], "end": opts.get("e", gopts.get("e", False)), "b": [b.lower() for b in opts.get("b", [])], "l": opts.get("l")})

INDEX = collections.defaultdict(list)  # token -> [(entry index, phrase tokens)]
for k, e in enumerate(ENTRIES):
    for p in e["phrases"]:
        pt = tokens(p)
        if pt:
            INDEX[pt[0]].append((k, pt, p))


def phrase_in(text, phrase):
    return re.search(r"(?<![a-z0-9])" + re.escape(phrase) + r"s?(?![a-z0-9])", text) is not None


def litres(i):
    u = (i.get("unit") or "each").lower()
    f = {"ml": 1, "l": 1000}.get(u)
    if f:
        return float(i.get("size") or 0) * f / 1000
    m = re.search(r"(\d+(?:\.\d+)?)\s*(ml|l|litres?|liters?)(?![a-z])", i["name"].lower())
    if m:
        return float(m.group(1)) * (1 if m.group(2).startswith("l") else 0.001)
    return None


TAILS = collections.Counter()


def match(i):
    """The entry the item belongs to, or None."""
    name, brand = i["name"], i.get("brand") or ""
    lower = name.lower()
    toks = set(main_tokens(name))
    brand_l = brand.lower()
    best = None
    for t in toks:
        for k, pt, p in INDEX.get(t, ()):
            e = ENTRIES[k]
            if best is not None and best[0] == k:
                continue
            if relevance(name, brand, pt) <= 0:
                continue
            if any(phrase_in(lower, x) for x in e["x"]):
                continue
            if e["end"] and not plain(name, brand, pt, e["end"] == "fresh", TAILS):
                continue
            if e["l"]:
                v = litres(i)
                if v is None or not any(a <= v <= b for a, b in e["l"]):
                    continue
            best = (k, p)
    if best:
        return ENTRIES[best[0]]
    if brand_l:
        for e in ENTRIES:
            if e["b"] and any(phrase_in(brand_l, b) for b in e["b"]):
                if e["l"]:
                    continue
                return e
    return None


R = STAPLES["rules"]
F = {"g": 1, "kg": 1000, "lb": 453.59237, "oz": 28.349523125, "ml": 1, "l": 1000}


def insane(i):
    """Prices that cannot be right, or too dear for one item."""
    if i["price"] > R["max_price"]:
        return "over $%d" % R["max_price"]
    u = (i.get("unit") or "each").lower()
    if u in F:
        base = float(i.get("size") or 0) * F[u]
        if base > 0:
            per = i["price"] / base * 100
            vol = u in ("ml", "l")
            if per < (R["min_per_100_volume"] if vol else R["min_per_100_weight"]):
                if not (vol and any(phrase_in(i["name"].lower(), w) for w in R["volume_exempt_words"])):
                    return "unit price too low"
    return None


def load(path):
    raw = pathlib.Path(path).read_bytes()
    return json.loads(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)["items"]


def main():
    a = sys.argv[1:]
    items = load(a[0])
    kept_scope = [i for i in items if sc.in_scope(i["name"], i.get("brand") or "", i.get("cat") or "")]
    rows = []
    for i in kept_scope:
        why = insane(i)
        e = None if why else match(i)
        rows.append((i, e, why))
    random.seed(3)
    if "--group" in a or "--entry" in a:
        key = a[a.index("--group") + 1] if "--group" in a else a[a.index("--entry") + 1].lower()
        sel = [(i, e) for i, e, w in rows if e and ((e["group"] == key) if "--group" in a else e["name"].lower().startswith(key))]
        print(len(sel), "items")
        by = collections.defaultdict(list)
        for i, e in sel:
            by[e["name"]].append(i)
        for n, lst in by.items():
            print(f"\n## {n}: {len(lst)}")
            for i in random.sample(lst, min(int(a[-1]) if a[-1].isdigit() else 14, len(lst))):
                print(f"   {i['store'][:5]:5} {i['price']:6} {i.get('size')}{i.get('unit')} | {i.get('brand','')[:12]:12} | {i['name'][:80]}")
        return
    if "--dropped" in a:
        n = int(a[a.index("--dropped") + 1])
        d = [i for i, e, w in rows if not e and not w]
        print(len(d), "in-scope items not everyday; sample:")
        for i in random.sample(d, min(n, len(d))):
            print(f"   {i['store'][:5]:5} {i['price']:6} | {i['name'][:90]}")
        return
    total = len(rows)
    ok = [(i, e) for i, e, w in rows if e]
    print(f"{len(items)} in catalog, {total} in scope, {len(ok)} everyday ({100*len(ok)//total}%), {sum(1 for _, _, w in rows if w)} hidden by price rules")
    print("by store:", dict(collections.Counter(i["store"] for i, _ in ok)))
    gc = collections.Counter(e["gname"] for _, e in ok)
    ec = collections.Counter(e["name"] for _, e in ok)
    for g in STAPLES["groups"]:
        print(f"\n{g['name']}: {gc[g['name']]}")
        for e in g["items"]:
            print(f"    {ec[e[0]]:5} {e[0]}")
    if "--photos" in a:
        photos_report(ok)


def photos_report(ok):
    out = ROOT / "tools" / "review" / "everyday-items-missing-photos.csv"
    out.parent.mkdir(exist_ok=True)
    by = collections.defaultdict(lambda: [0, 0, 0])
    lines = ["store,group,name,brand,price,size,reason"]
    for i, e in ok:
        s = by[i["store"]]
        s[0] += 1
        if i["store"] == "freshco" and i.get("img"):
            s[2] += 1
            reason = "FreshCo photo blocked outside freshco.com"
        elif not i.get("img") or "badge" in i["img"]:
            s[1] += 1
            reason = "no photo"
        else:
            continue
        lines.append(",".join('"%s"' % str(x).replace('"', "'") for x in (i["store"], e["gname"], i["name"], i.get("brand") or "", i["price"], f"{i.get('size')}{i.get('unit')}", reason)))
    out.write_text("\n".join(lines), encoding="utf-8")
    print("\nPhoto report (everyday items): store: total / no photo / FreshCo blocked photo")
    for s, (t, n, f) in sorted(by.items()):
        print(f"  {s}: {t} / {n} / {f}")
    print("wrote", out)


if __name__ == "__main__":
    main()
