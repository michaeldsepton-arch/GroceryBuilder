# Budget Basket: handoff

Written 2026-10-29 at the end of the first build session. A new Claude session should read this first, then `CLAUDE.md`.

## What this is
**Budget Basket** is an Android app (Flutter) for one household, two users: the owner (the person chatting with Claude, tests and tunes the app) and their wife, who uses it day to day to plan grocery shopping in **Red Deer, Alberta**. Prices are in CAD. The family is **Muslim**: see "Halal rules" below, they are a hard requirement.

The app:
- Searches products across the Red Deer stores in one place, with price, photo, sale price and **unit prices** (per 100 g / 100 mL / each, plus per kg and per lb everywhere).
- Has a cart with **5% GST** (Alberta has no PST; basic groceries are GST-exempt, snacks/drinks/household/etc. are taxable) and a **weekly budget** (default $100). It shows budget, cart total, left to spend, and what was already spent earlier in the week.
- Has Frequent items (favourites + often bought) with **aisle and freezer/fridge spot**, a Shop mode checklist by aisle, items the family adds themselves with a photo (for stores without online shopping), backup/restore, an in-app **self-updater**, and **price-drop alerts**.
- Has a Recipes tab: "Our book" (the wife's recipes, to be transcribed from photos), "Discover" (672 recipes), "Saved". Each ingredient suggests the cheapest product covering the needed amount, with Substitute and Browse options buttons and Add all to cart.

## Stores
| Store | Notes |
|---|---|
| Real Canadian Superstore | 5016 51 Ave, Red Deer. Loblaw pickup store id **1579**. |
| Wholesale Club | 6350 67th St (67th Street). Loblaw banner. |
| Walmart | **6375 50 Ave, Red Deer, AB T4N 3Z2** (closest to Blackfalds). Walmart's own store id is not known yet. |
| FreshCo | Red Deer; not wired up. |
| Shoppers Drug Mart | Clearview; its site returns Access Denied to automated access; not wired up. |
| Dollarama | Clearview and beside Superstore; no online shop, manual items. |
| Co-op | Clearview; added to the app as a store with no online catalog (manual items). Unknown whether it has online shopping or a flyer page. |
| Red Deer Halal Meat & Asian Food | No online shop; 6 meats seeded (see below). |

Seed stores live in `lib/data/db.dart` (`seedStores`); they are inserted on every launch with `ConflictAlgorithm.ignore`, so adding one reaches existing installs.

Halal market meats (all per lb, read from the in-store board photo): chicken leg without skin $3.99, drumsticks $3.89, wings $5.99, thighs $5.99, breast $6.99, beef regular qeema $7.99. Seeded once from `assets/seed/halal.json` (setting `seed_halal_v1`). The owner only wants chicken and beef from that market, and only regular qeema.

## Halal rules (hard requirements)
- **Pork, alcohol, gelatin are never shown**: not in store products, recipes, or substitutes. One shared term list: `assets/recipes/haram_terms.json`, used by the app (`lib/data/halal.dart`) and the recipe builder (`tools/build_recipes.py`). Keep both in sync by only editing the JSON. Matching is by whole word; `conditional` terms (bacon, ham, sausage...) are allowed when a halal-ish word (beef, turkey, chicken, halal, vegan...) is in the same field; `allow` strips lookalikes (root beer, wine vinegar...). Non-alcoholic beer is hidden on purpose.
- **Vanilla extract is not allowed** (alcohol based). The family uses **vanilla bean paste**. The builder converts "vanilla extract/essence" to "Vanilla bean paste" 1:1 in recipes; the app converts typed recipes; store products named "vanilla extract" are hidden.
- **Setting "Halal meat only"** (More, default on): hides supermarket meat that is not halal-certified (anything meat-like not from the halal market and not marked halal). Recipe meat suggestions prefer the halal market.
- Recipe checks are done field by field (title, each ingredient, each step) so an exception word in one field cannot excuse another.

## Architecture
```
lib/
  main.dart                 app shell, tabs: Search, Recipes, Cart, My stuff (Frequent + Add items), More
  theme.dart                green palette from the logo, Fraunces headings
  models/                   models.dart (Item, Store, CartLine, PriceAlert), units.dart (unit price math), recipe.dart
  data/
    db.dart                 sqflite schema v3 (stores, items, item_meta, cart, trips, settings, budgets,
                            user_recipes, recipe_meta, price_history)
    repo.dart               queries, catalog import (applyCatalog), alerts, price history, backup
    matching.dart           recipe need parsing + relevance + cheapest-pack logic
    recipe_repo.dart        recipe loading, substitutions, suggestions
    halal.dart              the filter
    services.dart           catalog download, in-app updater (GitHub releases)
    backup.dart             zip export/import
  state/app_state.dart      ChangeNotifier holding cart/budget/alerts/recipes
  screens/, widgets/        UI
assets/recipes/             catalog.json (generated), book.json (generated, empty so far), haram_terms.json,
                            substitutions.json, aliases.json
recipes_src/catalog/*.txt   97 hand-written recipes in a small text format (see tools/build_recipes.py docstring)
recipes_src/book/           the wife's book goes here as .txt files in the same format
tools/build_recipes.py      builds assets/recipes/*.json (CI also runs it with --mealdb)
tools/fetch_seed_images.py  CI step: Wikimedia Commons photos for seed items and recipes
tools/clipper/              Edge/Chrome extension: saves store page data the user browses (see below)
tools/local_scraper/        Playwright collector; BLOCKED by store bot protection, do not use
scraper/                    GitHub-hosted scraper (Loblaw/Walmart); paused, not working
.github/workflows/build.yml build + sign + release the APK; scrape.yml (manual only, schedule disabled)
test/                       Dart tests; tools/clipper/test_parse.js is a Node test
```

### Data flow for prices
Prices reach the app as a gzip JSON catalog `catalog.json.gz` published as an asset on a GitHub **pre-release tagged `catalog`**. The app downloads it on launch / More, Refresh prices, and `Repo.applyCatalog` **replaces every non-custom item** (so the file must be cumulative), while personal data (favourites, aisle notes, custom items, cart) is kept. Format:
`{"generated": iso, "stores": [{id,name,color,location,online}], "items": [{id:"store:code", store, name, brand, img, price, was, size, unit(g|kg|lb|oz|ml|l|each), variable(bool: sold by weight, price is per size), taxable, cat, url}]}`.
`applyCatalog` also records `price_history` for watched items (favourites, bought before, in cart) and filters haram items.

### Items and units
An `Item` has `price` for `sizeValue sizeUnit`. `variable` items (produce, meat) are sold by weight: price applies per size (for example $5.99 per 1 lb) and the cart quantity is **grams**. Everything weight-based is shown in both lb and kg. Cart quantity for fixed items is a count.

### Recipes
- Ingredient `search` is the store search term. `matching.dart` parses the recipe amount (g/kg/lb/oz, cups/tbsp/tsp to mL, cans/jars/bunches as packs, cloves/pinches as one purchase, plain counts), scores relevance by **whole words and product type** ("garlic butter" is not garlic), then picks the pack covering the need for the least money. Items with unknown pack size fall back to cheapest unit price but avoid bulk packs. `eggs`/counts use a count inferred from the name ("12 Eggs"). Aliases (`aliases.json`) widen the search (coriander/cilantro...).
- 672 recipes ship: 97 hand-written + ~575 from TheMealDB fetched at build time and halal-filtered. Cuisines/meals are normalised in the builder.

### Self-update
The app's applicationId is **`ca.budgetbasket.app`** and the release key is permanent: changing either forces an uninstall. Each push to the branch builds, signs, and publishes a GitHub release `v1.0.<run number>` with `budget-basket.apk` (arm64 only, about 40 MB). `versionCode` = run number. The app checks `releases/latest` (More, Check for app updates, also on launch) and compares the number after the last dot of the tag with its build number. The repo **must stay public** for this to work.

## Build and release
- Workflow: `.github/workflows/build.yml`. It fails fast if the signing secret is missing. Steps: fetch Wikimedia photos (non-fatal), build recipe catalogue with `--mealdb` (non-fatal), `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`, write signing config, `flutter build apk --release --target-platform android-arm64`, publish release. A full run takes about 9 to 12 minutes.
- **Signing secrets** (GitHub repo secrets, already added by the owner): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (budgetbasket), `ANDROID_KEY_PASSWORD`. The values were generated in the first session's sandbox (`secrets/`, git-ignored) and are NOT in the repo. **The owner must have a private backup of the keystore base64 and passwords. If it is lost, the app can never be updated in place again.** Do not print or commit these values.
- The branch everything lives on is `claude/exciting-lovelace-0cjf8v` (the repo's only branch and default). Pushes to `main` or `claude/**` trigger a build.
- Latest release at handoff: **v1.0.14**. Code checks: about 44 Dart tests pass (halal filter, matching, recipes, alerts, smoke widget tests on real screens) plus `node tools/clipper/test_parse.js`.
- Local checks: Flutter SDK 3.47 (`flutter analyze`, `flutter test`). Test gotchas learned: sqflite_ffi needs a real file per boot (in-memory DB is shared), DB futures need `tester.runAsync`, tests turn off web images via `ImagePolicy.network = false`, and `Roboto` is loaded from the SDK so text widths are realistic.

## What is NOT working or NOT done
1. **Automatic price collection is blocked.** Superstore, Wholesale Club (Loblaw) and Walmart all use bot protection. GitHub-hosted scraping and the Playwright collector (`tools/local_scraper`) are refused, so there is **no live Red Deer price data yet**. Do not try to get around bot protection (stealth/anti-detect browsers, header spoofing, swapping browsers to avoid detection). Earlier attempts at that were refused by the safety layer and the owner was told so. Allowed approaches: the passive **Clipper extension** (below), the user browsing and sending screenshots/recordings, manual items.
2. **Clipper extension** (`tools/clipper`): built and unit-tested with synthetic data, **never run against the real sites**. The Loblaw/PC Express product field names are a best guess (`code`, `name`, `brand`, `packageSizing`, `prices.price.value/unit`, `prices.wasPrice.value`, `prices.comparisonPrices`, `productImage[0].imageUrl`, `breadcrumbs`, `link`, `inventoryIndicator`). First real run: have the owner click "Copy diagnostics" in the popup and paste it, then fix `parse.js`. Walmart parsing is ported from the Python version that did return ~619 items from page data in CI. Install: `edge://extensions`, Developer mode, Load unpacked `tools\clipper`. Export, then `publish.bat` (needs `gh auth login`) uploads `catalog.json.gz` to the `catalog` release.
3. **The existing `catalog` release asset is stale test data** (619 Walmart items scraped by CI from an unknown default store, id 1061). It will be replaced by the first real export. Do not trust it.
4. Walmart store pinning, FreshCo, Shoppers Drug Mart, Co-op adapters: not done.
5. **The app has not been run on a real phone.** Only analyzer, unit and widget tests. Expect rough edges and ask the owner for feedback.
6. Proposed but not built: **phone notifications** for price drops (background check about twice a day, local notification), a **daily scheduled** export on the PC (Windows Task Scheduler), a trips-history screen, per-store shopping list totals, smaller APK work (already arm64 only).
7. TheMealDB ingredient names are generic; matching quality vs real Red Deer products is untested until real price data exists. Tune `aliases.json` / `SEARCH_ALIASES` in `tools/build_recipes.py` from real misses.
8. Recipe images from Wikimedia for 2 hand-written recipes (Chocolate Chip Cookies, Vegetable Biryani) were not found; they show a placeholder.

## The wife's recipe book (next task)
The owner photographed the book and is sending the photos (first attempt was uploading a `Recipes` folder via GitHub's web page; the upload was too big to commit in one go, so send in batches of 10 to 15 or attach in chat). One photo was corrupted when copying from phone to Google Drive; the owner asked Claude to infer which recipe is missing from the **index pages** of the book and the numbering of the other photos. Public repo caveat: transcribed recipes will be in the public repo (the owner was told).
To add them: transcribe into `recipes_src/book/<name>.txt` using the DSL, then `python3 tools/build_recipes.py` (writes `assets/recipes/book.json`), run tests, push, wait for the build, and the owner updates the app in-app. DSL example:
```
== Recipe title
cuisine: Pakistani | meal: dinner | minutes: 45 | servings: 4
- 500 g | Chicken thighs | chicken thighs
- 1 tsp | Cumin | cumin
> Step one.
> Step two.
note: any remarks (for example "page 42, handwritten, amount unclear")
```
Rules: keep the owner's wording, flag unreadable words or amounts in `note:` instead of guessing, apply the halal rules, use vanilla bean paste. If a recipe contains something the filter blocks (pork, wine...), tell the owner rather than silently dropping it.

## Owner preferences and working style
- Wants to be asked clarifying questions before big decisions, and wants things automated, not manual entry.
- Windows PC (user folder `C:\Users\Acer`, project copy in `C:\Users\Acer\Documents\Budget Basket`). Phone is Android 17.
- Prefers recommendations with a clear default. Likes visible, honest status (what is tested, what is not).
- GitHub account `michaeldsepton-arch`, repo `GroceryBuilder`, public.

## Quick commands
```bash
flutter pub get && flutter analyze && flutter test         # checks
python3 tools/build_recipes.py                              # rebuild recipe JSON (add --mealdb only in CI)
node tools/clipper/test_parse.js                            # extension parser tests
```
