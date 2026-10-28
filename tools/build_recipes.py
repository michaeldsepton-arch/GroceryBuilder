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


CUISINE_BY_COUNTRY = {}
for _cuisine, _names in {
    "Indian": ["india"], "Pakistani": ["pakistan"], "South Asian": ["bangladesh", "sri lanka", "nepal", "afghanistan"],
    "Arab": ["lebanon", "syria", "jordan", "saudi arabia", "iraq", "uae", "united arab emirates", "palestine", "yemen", "kuwait", "oman", "qatar", "bahrain", "arab"],
    "Persian": ["iran"], "Turkish": ["turkey", "turkiye", "türkiye"], "Egyptian": ["egypt"], "Moroccan": ["morocco"],
    "North African": ["algeria", "tunisia", "libya", "algerian", "tunisian"],
    "African": ["ethiopia", "nigeria", "ghana", "kenya", "south africa", "senegal", "tanzania", "uganda", "somalia", "sudan", "eritrea"],
    "Mediterranean": ["greece", "spain", "portugal", "malta", "cyprus", "albania", "croatia"],
    "Italian": ["italy"], "French": ["france"], "Chinese": ["china"], "Japanese": ["japan"],
    "Asian": ["thailand", "vietnam", "malaysia", "indonesia", "philippines", "singapore", "cambodia", "laos", "korea", "south korea", "myanmar", "taiwan"],
    "Mexican": ["mexico"],
    "Latin American": ["colombia", "venezuela", "argentina", "brazil", "peru", "chile", "cuba", "ecuador", "bolivia", "uruguay", "paraguay", "dominican republic", "puerto rico", "guatemala", "costa rica", "panama", "el salvador", "honduras", "nicaragua"],
    "Caribbean": ["jamaica", "antigua", "antigua and barbuda", "barbados", "trinidad", "trinidad and tobago", "haiti", "bahamas", "guyana", "caribbean"],
    "Western": ["united states", "usa", "american", "canada", "canadian", "australia", "australian", "united kingdom", "uk", "england", "british", "scotland", "ireland", "irish", "new zealand", "norway", "netherlands", "sweden", "denmark", "finland", "germany", "austria", "switzerland", "belgium", "poland", "polish", "russia", "ukraine", "hungary", "czech republic", "romania", "bulgaria", "serbia", "lithuania", "latvia", "estonia", "iceland"],
}.items():
    for _n in _names:
        CUISINE_BY_COUNTRY[_n] = _cuisine


for _dem, _cuisine in {
    "jamaican": "Caribbean", "trinidadian": "Caribbean", "haitian": "Caribbean", "cuban": "Latin American",
    "thai": "Asian", "vietnamese": "Asian", "malaysian": "Asian", "filipino": "Asian", "indonesian": "Asian", "korean": "Asian",
    "japanese": "Japanese", "chinese": "Chinese", "mexican": "Mexican", "italian": "Italian", "french": "French",
    "greek": "Mediterranean", "spanish": "Mediterranean", "portuguese": "Mediterranean", "croatian": "Mediterranean",
    "lebanese": "Arab", "syrian": "Arab", "jordanian": "Arab", "iraqi": "Arab", "saudi arabian": "Arab", "palestinian": "Arab",
    "egyptian": "Egyptian", "moroccan": "Moroccan", "indian": "Indian", "pakistani": "Pakistani", "turkish": "Turkish",
    "iranian": "Persian", "persian": "Persian", "kenyan": "African", "ethiopian": "African", "nigerian": "African",
    "irish": "Western", "british": "Western", "american": "Western", "canadian": "Western", "australian": "Western",
    "dutch": "Western", "polish": "Western", "russian": "Western", "ukrainian": "Western", "norwegian": "Western",
}.items():
    CUISINE_BY_COUNTRY.setdefault(_dem, _cuisine)


def normalize_cuisine(area):
    a = (area or "").strip()
    if not a:
        return "International"
    return CUISINE_BY_COUNTRY.get(a.lower(), a if a[:1].isupper() and a.lower() not in CUISINE_BY_COUNTRY else "International")


MEAL_HINTS = [
    ("drink", r"smoothie|lassi|juice|lemonade|\btea\b|coffee|shake\b|\bdrink|punch|mocktail|cooler|cordial"),
    ("bread", r"\bbread\b|\bnaan\b|focaccia|\brolls?\b|\bbuns?\b|\bpita\b|flatbread|\broti\b|chapati|paratha|baguette|brioche|sourdough|\bloaf\b|bagel|scone|biscuits?\b|cornbread|tortilla"),
    ("dessert", r"cake|cookie|pudding|\bpie\b|tart\b|brownie|ice cream|halwa|kheer|cheesecake|crumble|mousse|custard|fudge|pancake|waffle|donut|doughnut|muffin|cupcake|sorbet|tiramisu|trifle|pavlova|baklava|truffle|candy|sweets?\b"),
    ("lunch", r"soup|salad|sandwich|\bwrap\b|burger|tacos?\b|sub\b|panini|quesadilla|\bbowl\b|chowder|gazpacho"),
    ("breakfast", r"breakfast|omelette|omelet|porridge|granola|oats|shakshuka|scrambled|french toast|hash browns|eggs benedict|brunch"),
]

SEARCH_ALIASES = {
    "plain flour": "flour", "self-raising flour": "flour", "self raising flour": "flour", "all-purpose flour": "flour",
    "strong white flour": "bread flour", "wholewheat flour": "whole wheat flour", "wholemeal flour": "whole wheat flour",
    "caster sugar": "sugar", "granulated sugar": "sugar", "white sugar": "sugar", "muscovado sugar": "brown sugar",
    "demerara sugar": "brown sugar", "light brown soft sugar": "brown sugar", "dark brown soft sugar": "brown sugar",
    "double cream": "heavy cream", "whipping cream": "heavy cream", "single cream": "cream", "creme fraiche": "sour cream",
    "extra virgin olive oil": "olive oil", "rapeseed oil": "canola oil", "sunflower oil": "vegetable oil",
    "groundnut oil": "peanut oil", "tomato puree": "tomato paste", "tomato purée": "tomato paste", "passata": "tomato sauce",
    "chopped tomatoes": "diced tomatoes", "tinned tomatoes": "canned tomatoes", "plum tomatoes": "tomatoes",
    "sea salt": "salt", "salt flakes": "salt", "flaky sea salt": "salt", "freshly ground black pepper": "black pepper",
    "coriander": "cilantro", "coriander leaves": "cilantro", "fresh coriander": "cilantro",
    "spring onions": "green onions", "spring onion": "green onions", "scallions": "green onions", "aubergine": "eggplant",
    "courgette": "zucchini", "courgettes": "zucchini", "rocket": "arugula", "swede": "rutabaga", "pak choi": "bok choy",
    "mange tout": "snow peas", "prawns": "shrimp", "king prawns": "shrimp", "tiger prawns": "shrimp",
    "minced beef": "ground beef", "beef mince": "ground beef", "mince": "ground beef", "lamb mince": "ground lamb",
    "minced lamb": "ground lamb", "chicken mince": "ground chicken", "turkey mince": "ground turkey",
    "yoghurt": "yogurt", "plain yoghurt": "plain yogurt", "natural yoghurt": "plain yogurt", "natural yogurt": "plain yogurt",
    "greek yoghurt": "greek yogurt", "cornflour": "cornstarch", "bicarbonate of soda": "baking soda",
    "stock cube": "bouillon cubes", "chicken stock cube": "bouillon cubes", "beef stock cube": "bouillon cubes",
    "vegetable stock cube": "bouillon cubes", "chicken stock": "chicken broth", "beef stock": "beef broth",
    "vegetable stock": "vegetable broth", "digestive biscuits": "graham crackers", "icing sugar": "icing sugar",
    "garlic clove": "garlic", "garlic cloves": "garlic", "ginger root": "ginger", "root ginger": "ginger",
    "red chilli": "red chili", "green chilli": "green chili", "chilli powder": "chili powder", "chilli flakes": "chili flakes",
    "chilli": "chili", "chillies": "chili", "dessicated coconut": "coconut", "desiccated coconut": "coconut",
    "double concentrate tomato paste": "tomato paste", "basmati": "basmati rice", "long grain rice": "rice",
    "lemon juice": "lemon juice", "lime juice": "lime juice", "mixed spice": "allspice", "sultanas": "raisins",
    "golden caster sugar": "sugar", "treacle": "molasses", "black treacle": "molasses", "golden syrup": "corn syrup",
    "pitta bread": "pita bread", "wholemeal bread": "whole wheat bread", "streaky bacon": "turkey bacon",
}
PREP_WORDS = re.compile(r"\b(fresh|freshly|chopped|finely|roughly|sliced|diced|ripe|large|small|medium|extra|good quality|to taste|to serve|for frying|for garnish|optional)\b", re.I)


def search_term(name):
    n = re.sub(r"\(.*?\)", " ", (name or "").lower())
    n = n.split(",")[0]
    if n.strip() in SEARCH_ALIASES:
        return SEARCH_ALIASES[n.strip()]
    n = re.sub(r"\s+", " ", PREP_WORDS.sub(" ", n)).strip()
    return SEARCH_ALIASES.get(n, n or (name or "").strip().lower())


def infer_meal(title, category):
    if category in ("Dessert", "Breakfast"):
        return MEALDB_MEAL[category]
    t = (title or "").lower()
    for meal, pat in MEAL_HINTS:
        if re.search(pat, t):
            return meal
    return MEALDB_MEAL.get(category, "dinner")


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
                    ings.append({"qty": (m.get(f"strMeasure{i}") or "").strip(), "name": name, "search": search_term(name)})
            steps = [s.strip() for s in re.split(r"\r?\n+", m.get("strInstructions") or "") if len(s.strip()) > 3]
            steps = [re.sub(r"^(step\s*)?\d+[.)]?\s*", "", s, flags=re.I) for s in steps]
            area = normalize_cuisine(MEALDB_AREA.get(m.get("strArea"), m.get("strArea") or ""))
            out.append({
                "id": "mealdb:" + m["idMeal"], "title": m["strMeal"], "source": "catalog",
                "cuisine": area, "meal": infer_meal(m["strMeal"], m.get("strCategory")),
                "image": (m.get("strMealThumb") or "") + "/medium", "ingredients": ings, "steps": steps,
                "tags": [t for t in (m.get("strTags") or "").split(",") if t],
            })
    return out


def finish(recipes, prefix):
    res, dropped = [], 0
    for r in recipes:
        r.setdefault("id", f"{prefix}:{slug(r['title'])}")
        # Checked field by field: an exception word ("turkey") in one ingredient
        # must never excuse "bacon" in another.
        fields = [r["title"]] + [f"{i['name']} {i['search']}" for i in r["ingredients"]] + r["steps"]
        if any(is_haram(f) for f in fields):
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
