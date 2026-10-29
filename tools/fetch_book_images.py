#!/usr/bin/env python3
"""Find a freely licensed photo (Wikimedia Commons) for each recipe in our book.

Run by hand when recipes are added: images land in assets/recipes/images/<slug>.jpg
(the recipe builder picks them up by title) and credits in assets/recipes/ATTRIBUTION_BOOK.md.
Recipes that already have an image are skipped. Each recipe tries its own search
terms first, then a more general dish name, so none stays blank.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build_recipes  # noqa: E402
import fetch_seed_images as fsi  # noqa: E402

# title prefix -> search terms, most specific first. Avoid anything that might show pork or alcohol.
Q = {
    "Malai Chicken": ["malai chicken", "chicken curry"], "Fatayer Dough": ["bread dough", "dough"],
    "Fatayer": ["fatayer", "meat pie arab"], "Corn Soup": ["sweet corn soup", "corn soup"],
    "Fried Noodles": ["crispy fried noodles", "chow mein"], "Punjabi Samosa": ["punjabi samosa", "samosa"],
    "Chatpatti": ["aloo chaat", "chaat"], "Carrot Pickle": ["carrot pickle", "pickled carrots"],
    "Shrimp Biryani": ["shrimp biryani", "prawn biryani", "biryani"], "Samosa Keema": ["keema samosa", "samosa"],
    "Methi Jhingi": ["prawn curry", "shrimp curry"], "Pizza Sauce": ["pizza sauce", "tomato sauce"],
    "Pizza Samosa": ["samosa", "fried samosa"], "Pizza": ["margherita pizza", "homemade pizza"],
    "Mandi / Majboos Masala": ["hawaij spice mix", "spice mix", "spices"], "Masala Dosa": ["masala dosa", "dosa"],
    "Coconut Green Chutney": ["coconut chutney", "green chutney"], "Dahi Vada": ["dahi vada", "dahi bhalla"],
    "Shami Kabab": ["shami kebab", "shami kabab", "kebab"], "Chicken/Mutton Biryani": ["chicken biryani", "biryani"],
    "Shepherd's Pie": ["shepherd's pie", "cottage pie"], "Tuna Kabab": ["tuna cutlet", "fish cutlet", "fish cakes"],
    "Mahshi": ["mahshi", "stuffed zucchini"], "Falafel": ["falafel"], "Spinach Fatayer": ["spinach fatayer", "spinach pie"],
    "Drumstick": ["moringa drumstick", "drumstick vegetable"], "Shrimp and Sweet Potato": ["shrimp curry", "prawn curry"],
    "Achar Masala": ["mango pickle", "achar"], "Bedekar Masala": ["lemon pickle", "lime pickle"],
    "Chicken Ginglic": ["ginger garlic chicken", "chicken curry"], "Butter Chicken": ["butter chicken"],
    "Ras Al-Usfoor": ["arabic meat stew", "lamb stew"], "Lebanese Sambousa": ["sambousek", "lebanese sambousek"],
    "Meat/Chicken Majboos": ["chicken majboos", "chicken mandi", "kabsa"], "Daqqus": ["daqqus", "tomato garlic sauce", "salsa"],
    "Spicy Squash Sabzi": ["squash curry", "pumpkin curry"], "Tomato Chutney": ["tomato chutney"],
    "Chicken Handi": ["chicken handi", "chicken curry"], "Schezwan Sauce": ["schezwan sauce", "chili sauce"],
    "Beef and Broccoli": ["beef and broccoli"], "Chicken Schezwan": ["schezwan chicken", "chilli chicken"],
    "Okra and Meat Gravy": ["okra stew", "bamia"], "Chicken Do Pyaza": ["chicken do pyaza", "chicken curry"],
    "Chilli Potatoes": ["chilli potato", "chili potato"], "Swedish Meatballs": ["swedish meatballs"],
    "Garlic Bread": ["garlic bread"], "Gosht Salan": ["mutton curry", "lamb curry"], "Chicken Salan": ["chicken curry"],
    "Zeera Matar Rice": ["jeera rice", "cumin rice", "pilaf"], "Bolognese": ["spaghetti bolognese", "bolognese"],
    "Bechamel Sauce": ["béchamel sauce", "white sauce"], "Beans Salan": ["bean curry", "rajma"],
    "Muhammarah": ["muhammara", "red pepper dip"], "Soy Sauce Chicken": ["soy sauce chicken"],
    "Chicken Shawarma": ["chicken shawarma", "shawarma"], "Malai Tandoori Chicken": ["malai tikka", "chicken tikka"],
    "Dal Makhani": ["dal makhani"], "Chicken Nachos": ["chicken nachos", "nachos"], "Beef Nachos": ["beef nachos", "nachos"],
    "Sheesh Tawooq": ["shish taouk", "chicken skewers"], "Achari Gosht": ["achari gosht", "mutton curry"],
    "Mutton Karahi": ["mutton karahi", "karahi"], "Arayes": ["arayes", "lebanese kebab bread"],
    "Sliced Aloo Onion": ["aloo pyaz", "fried potato onion", "potato fry"], "Moong Dal Samosa": ["moong dal samosa", "samosa"],
    "Garam Masala Powder": ["garam masala", "indian spices"], "Patora": ["patra colocasia", "alu vadi"],
    "Khichrda": ["haleem", "khichra"], "Sheet Pan Kabab": ["kofta kebab", "kebab tray"],
    "Hashw": ["mandi rice meat", "kabsa"], "Instant Marag": ["bone broth", "meat broth"],
    "Berry Rice": ["zereshk polo", "barberry rice"], "Lahm Bi Ajeen": ["lahm bi ajeen", "lahmacun", "meat pie"],
    "Burger": ["homemade hamburger", "hamburger"], "Turkish Kabab": ["kebab eggplant", "turkish kebab"],
    "Chicken Kabab (Tikki": ["chicken cutlet", "chicken tikki"], "Chicken Nuggets": ["chicken nuggets"],
    "BBQ Chicken": ["barbecue chicken", "grilled chicken"], "Chicken Noodles": ["chicken noodles", "chow mein"],
    "Cheese Chutney Sandwich": ["chutney sandwich", "cheese sandwich"], "Caponata": ["caponata"],
    "Spring Rolls": ["spring rolls"], "Chicken Bhajiya": ["chicken pakora", "pakora"], "Focaccia": ["focaccia"],
    "Chicken Fajitas": ["chicken fajitas", "fajitas"], "Dal Gosht": ["dal gosht", "lentil curry"],
    "Baigan Bechamel": ["moussaka", "eggplant casserole"], "Batata Harra": ["batata harra", "spicy potatoes"],
    "Honey Garlic Glazed Chicken": ["honey garlic chicken", "glazed chicken"], "Fried Rice": ["egg fried rice", "fried rice"],
    "Caramelized Tomato Onion Pasta": ["tomato pasta", "spaghetti tomato sauce"], "Shawarma (Boneless)": ["chicken shawarma", "shawarma"],
    "Mince Meat with Eggs": ["keema eggs", "ground meat eggs", "scrambled eggs"], "Chicken Pot Pie": ["chicken pot pie"],
    "Chicken Mushroom Sandwich": ["chicken sandwich", "mushroom sandwich"], "Aloo Gobi": ["aloo gobi"],
    "Keema Aloo": ["keema aloo", "keema"],
    "Orange Chocolate Marble Cake": ["marble cake", "chocolate orange cake"], "Gulab Jamun": ["gulab jamun"],
    "Seviyan": ["seviyan", "sheer khurma", "vermicelli pudding"], "Gajar ka Halwa": ["gajar ka halwa", "carrot halwa"],
    "Black Forest Gateau": ["black forest cake", "black forest gateau"], "Orange Cake": ["orange cake"],
    "Chocolate Cake (Ganache)": ["chocolate ganache cake", "chocolate cake"], "Orange and Poppy Cake": ["poppy seed cake", "orange cake"],
    "Short Bread Tart Crust": ["shortbread", "tart crust"], "Victoria Sponge Cake": ["victoria sponge cake"],
    "Carrot Cake Cup Cake": ["carrot cupcake", "carrot cake cupcakes"], "Carrot Cake": ["carrot cake"],
    "Pineapple Upside Down Cake": ["pineapple upside down cake"], "Double Chocolate Pound Cake": ["chocolate pound cake", "chocolate cake"],
    "Caramel Popcorn": ["caramel popcorn"], "Luscious Lemon Cake": ["lemon drizzle cake", "lemon cake"],
    "Cinnamon Rolls": ["cinnamon rolls"], "No Bake Cheese Cake": ["cheesecake", "no bake cheesecake"],
    "Chocolate Swiss Roll": ["chocolate swiss roll", "swiss roll"], "Jemma's Chocolate CupCake": ["chocolate cupcake"],
    "Crepes": ["crepes", "crêpes"], "Pancakes": ["pancakes"], "Chocolate Lovers Food Cake": ["chocolate cake"],
    "Donuts": ["doughnuts", "donuts"], "Light Fruit Cake": ["fruit cake", "fruitcake"], "Chocolate Mousse Cake": ["chocolate mousse cake"],
    "Cinnamon Swirl Cake": ["cinnamon swirl cake", "coffee cake"], "Tiramisu": ["tiramisu"],
    "Lemon Strawberry Crumb Bars": ["crumb bars", "lemon bars"], "Bounty Bars": ["coconut chocolate bars", "bounty bar"],
    "Homemade Condensed Milk": ["condensed milk", "sweetened condensed milk"], "Brownies": ["brownies", "brownie"],
    "Chocolate Mousse Swiss Roll": ["chocolate roll cake", "swiss roll"], "Salted Caramel Sauce": ["caramel sauce", "salted caramel"],
    "Chocolate Pudding": ["chocolate pudding"], "Flourless Chocolate Cake": ["flourless chocolate cake", "chocolate cake"],
    "Muller Yogurt": ["fruit yogurt", "yogurt"], "Raspberry Oatmeal Muffin": ["raspberry muffin", "muffin"],
    "Coconut Cake 2": ["coconut cake", "coconut cake slice"], "Coconut Cake": ["coconut cake"],
    "Coconut Sheet Cake": ["coconut cake", "sheet cake"], "Pecan Pie": ["pecan pie"], "Pound Cake": ["pound cake"],
    "Oatmeal Cookies": ["oatmeal cookies"], "Brookies": ["brookies", "brownie cookies"],
    "Strawberry Cheesecake Choc-Chip": ["chocolate chip cookies", "cookies"], "Chocolate Oats Cereal": ["chocolate granola", "granola"],
    "Maple Cinnamon Nut Granola": ["nut granola", "granola"], "Lemon Bars": ["lemon bars"],
    "Chocolate and Peanut Butter Cereal": ["peanut butter granola", "granola"], "Orange Chocolate Cereal": ["granola", "oat clusters"],
}


# Better terms found after reviewing the first results (checked before Q).
FIX = {
    "Malai Chicken": ["creamy chicken curry", "chicken korma"], "Corn Soup": ["corn soup bowl", "cream of corn soup"],
    "Tuna Kabab": ["fish cutlet", "fish cakes", "fish patties"], "Daqqus": ["tomato salsa", "salsa"],
    "Spicy Squash Sabzi": ["pumpkin curry", "kabocha curry"], "Schezwan Sauce": ["chili garlic sauce", "chilli sauce"],
    "Chicken Schezwan": ["chilli chicken", "chicken stir fry"], "Malai Tandoori Chicken": ["chicken tikka", "tandoori chicken"],
    "Pizza Sauce": ["marinara sauce", "tomato sauce in bowl", "tomatoes"], "Focaccia": ["focaccia rosemary", "olive oil bread", "flatbread"],
    "Brownies": ["chocolate brownies", "fudge brownies"], "Brookies": ["brownie cookie", "chocolate cookie"],
    "Lemon Strawberry Crumb Bars": ["date squares", "oat crumble bars", "raspberry bars"], "Chocolate Cake (Ganache)": ["chocolate layer cake", "chocolate cake slice", "chocolate cake"],
    "Light Fruit Cake": ["fruitcake slice", "christmas cake"], "Cinnamon Swirl Cake": ["cinnamon coffee cake", "cinnamon cake"],
    "Donuts": ["glazed doughnuts", "glazed donut"], "Sliced Aloo Onion": ["fried potatoes onions", "potato fry"],
}


def queries(title):
    for key in sorted(FIX, key=len, reverse=True):
        if title.startswith(key):
            return FIX[key]
    for key in sorted(Q, key=len, reverse=True):
        if title.startswith(key):
            return Q[key]
    base = re.sub(r"\(.*?\)", "", title).strip()
    return [base]


def main():
    out_dir = ROOT / "assets" / "recipes" / "images"
    out_dir.mkdir(parents=True, exist_ok=True)
    credits_path = ROOT / "assets" / "recipes" / "ATTRIBUTION_BOOK.md"
    credits = {}
    if credits_path.exists():
        for line in credits_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("- "):
                credits[line.split(":", 1)[0]] = line
    used = set()
    missing = []
    for f in sorted((ROOT / "recipes_src" / "book").glob("*.txt")):
        for r in build_recipes.parse_dsl(f, "book"):
            slug = build_recipes.slug(r["title"])
            out = out_dir / f"{slug}.jpg"
            if out.exists():
                continue
            done = False
            # first try for a photo no other recipe uses, then accept a repeat
            for allow_repeat in (False, True):
                for q in queries(r["title"]):
                    try:
                        hit = fsi.find(q)
                    except Exception as e:  # network hiccup: try the next term
                        print("search failed", q, e, file=sys.stderr)
                        continue
                    if not hit or (hit[1] in used and not allow_repeat):
                        continue
                    url, title, lic, artist, page = hit
                    try:
                        out.write_bytes(fsi.get(url))
                    except Exception as e:
                        print("download failed", title, e, file=sys.stderr)
                        continue
                    used.add(title)
                    credits[f"- Recipe {r['title']}"] = f"- Recipe {r['title']}: {title} by {artist} ({lic}) {page}"
                    print(f"ok {r['title']} <- {q} -> {title}")
                    done = True
                    break
                if done:
                    break
            if not done:
                missing.append(r["title"])
                print("NO IMAGE", r["title"])
    header = "# Book recipe image credits (Wikimedia Commons)\n\n"
    credits_path.write_text(header + "\n".join(credits[k] for k in sorted(credits)) + "\n", encoding="utf-8")
    print("missing:", missing)


if __name__ == "__main__":
    main()
