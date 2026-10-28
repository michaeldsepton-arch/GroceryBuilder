#!/usr/bin/env python3
"""Builds assets/recipes/catalog.json and book.json.

Sources:
  recipes_src/catalog/*.txt   hand-written catalogue (this repo)
  recipes_src/book/*.txt      the family recipe book, transcribed from photos
  --mealdb                    TheMealDB (CI only), filtered for halal
Anything mentioning pork, alcohol or gelatin is dropped using the same term
list as the app (assets/recipes/haram_terms.json).

DSL:
  == Title
  cuisine: X | meal: dinner | minutes: 30 | servings: 4 | img: search words
  - qty | Ingredient name | store search term (optional)
  > A method step
  note: free text
"""
import argparse
import json
import pathlib
import re
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
TERMS = json.loads((ROOT / "assets/recipes/haram_terms.json").read_text())


def _word(t):
    return re.compile(r"(?<![a-z0-9])" + re.escape(t) + r"(?![a-z0-9])", re.I)


HARD = [_word(t) for t in TERMS["hard"]]
COND = {_word(k): [x.lower() for x in v] for k, v in TERMS["conditional"].items()}
ALLOW = [a.lower() for a in TERMS["allow"]]


def is_haram(text):
    s = (text or "").lower()
    for a in ALLOW:
        s = s.replace(a, " ")
    if any(r.search(s) for r in HARD):
        return True
    return any(k.search(s) and not any(x and x in s for x in v) for k, v in COND.items())


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def parse_dsl(path, source):
    out, cur = [], None
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith("== "):
            cur = {"title": line[3:].strip(), "ingredients": [], "steps": [], "tags": [], "source": source}
            out.append(cur)
        elif cur is None:
            continue
        elif line.startswith("- "):
            parts = [p.strip() for p in line[2:].split("|")]
            while len(parts) < 3:
                parts.append("")
            cur["ingredients"].append({"qty": parts[0], "name": parts[1], "search": parts[2] or parts[1]})
        elif line.startswith(">"):
            cur["steps"].append(line[1:].strip())
        elif line.lower().startswith("note:"):
            cur["notes"] = line[5:].strip()
        elif ":" in line:
            for kv in line.split("|"):
                k, _, v = kv.partition(":")
                k, v = k.strip().lower(), v.strip()
                if k == "minutes":
                    cur["minutes"] = int(v)
                elif k == "servings":
                    cur["servings"] = int(v)
                elif k in ("cuisine", "meal", "img"):
                    cur[k] = v
                elif k == "tags":
                    cur["tags"] = [t.strip() for t in v.split(",")]
    return out


MEALDB_MEAL = {"Dessert": "dessert", "Breakfast": "breakfast", "Starter": "snack", "Side": "snack"}
MEALDB_AREA = {
    "Indian": "Indian", "Egyptian": "Egyptian", "Moroccan": "Moroccan", "Turkish": "Turkish", "Tunisian": "North African",
    "Greek": "Mediterranean", "Italian": "Italian", "Lebanese": "Arab", "Syrian": "Arab", "Jordanian": "Arab",
    "Saudi Arabian": "Arab", "Pakistani": "Pakistani", "Iraqi": "Arab", "Malaysian": "Asian", "Thai": "Asian",
    "Chinese": "Chinese", "Japanese": "Japanese", "Vietnamese": "Asian", "Mexican": "Mexican", "British": "Western",
    "American": "Western", "Canadian": "Western", "French": "French", "Spanish": "Mediterranean", "Jamaican": "Caribbean",
}


def fetch_mealdb():
    seen, out = set(), []
    for ch in "abcdefghijklmnopqrstuvwxyz":
        try:
            with urllib.request.urlopen(f"https://www.themealdb.com/api/json/v1/1/search.php?f={ch}", timeout=30) as r:
                meals = json.loads(r.read()).get("meals") or []
        except Exception as e:
            print("mealdb", ch, e, file=sys.stderr)
            continue
        for m in meals:
            if m["idMeal"] in seen:
                continue
            seen.add(m["idMeal"])
            ings = []
            for i in range(1, 21):
                name = (m.get(f"strIngredient{i}") or "").strip()
                if name:
                    ings.append({"qty": (m.get(f"strMeasure{i}") or "").strip(), "name": name, "search": name})
            steps = [s.strip() for s in re.split(r"\r?\n+", m.get("strInstructions") or "") if len(s.strip()) > 3]
            steps = [re.sub(r"^(step\s*)?\d+[.)]?\s*", "", s, flags=re.I) for s in steps]
            area = MEALDB_AREA.get(m.get("strArea"), m.get("strArea") or "")
            out.append({
                "id": "mealdb:" + m["idMeal"], "title": m["strMeal"], "source": "catalog",
                "cuisine": area, "meal": MEALDB_MEAL.get(m.get("strCategory"), "dinner"),
                "image": (m.get("strMealThumb") or "") + "/medium", "ingredients": ings, "steps": steps,
                "tags": [t for t in (m.get("strTags") or "").split(",") if t],
            })
    return out


def finish(recipes, prefix):
    res, dropped = [], 0
    for r in recipes:
        r.setdefault("id", f"{prefix}:{slug(r['title'])}")
        blob = " ".join([r["title"]] + [f"{i['name']} {i['search']}" for i in r["ingredients"]] + r["steps"])
        if is_haram(blob):
            dropped += 1
            print("  dropped (haram filter):", r["title"])
            continue
        img = ROOT / "assets/recipes/images" / f"{slug(r['title'])}.jpg"
        if "image" not in r and img.exists():
            r["image"] = f"asset:assets/recipes/images/{img.name}"
        r.pop("img", None)
        r.pop("source", None)
        res.append(r)
    return res, dropped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mealdb", action="store_true")
    a = ap.parse_args()
    cat = []
    for f in sorted((ROOT / "recipes_src/catalog").glob("*.txt")):
        cat += parse_dsl(f, "catalog")
    titles = {r["title"].lower() for r in cat}
    if a.mealdb:
        cat += [r for r in fetch_mealdb() if r["title"].lower() not in titles]
    book = []
    for f in sorted((ROOT / "recipes_src/book").glob("*.txt")):
        book += parse_dsl(f, "book")
    cat, d1 = finish(cat, "cat")
    book, d2 = finish(book, "book")
    (ROOT / "assets/recipes/catalog.json").write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")))
    (ROOT / "assets/recipes/book.json").write_text(json.dumps(book, ensure_ascii=False, indent=1))
    print(f"catalog: {len(cat)} recipes ({d1} dropped); book: {len(book)} ({d2} dropped)")


if __name__ == "__main__":
    main()
