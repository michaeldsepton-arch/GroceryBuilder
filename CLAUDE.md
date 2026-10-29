# Budget Basket (Flutter, Android)

Grocery planning app for a Muslim household in Red Deer, Alberta. **Read `HANDOFF.md` first**: it has the full state, architecture, what works, what does not, and the next tasks.

## Rules that always apply
- **Halal**: never show pork, alcohol or gelatin anywhere (products, recipes, substitutes). No vanilla extract: use vanilla bean paste. Edit the single list in `assets/recipes/haram_terms.json`.
- **Never bypass bot protection** on store sites (no stealth/anti-detect browsers, no spoofing, no swapping browsers to avoid detection). Use the passive clipper extension, user-supplied screenshots, or manual items.
- **Never change** `applicationId` (`ca.budgetbasket.app`) or the release signing key; never print or commit signing secrets (they live in GitHub repo secrets).
- Keep the repo public (the in-app updater downloads releases anonymously).
- Work on branch `claude/exciting-lovelace-0cjf8v`. Every push builds and publishes a release (about 10 minutes); run `flutter analyze` and `flutter test` first.
- Currency CAD. GST 5% on taxable items only. Show weights in both lb and kg.

## Current priorities
1. Transcribe the wife's recipe book photos into `recipes_src/book/*.txt` (see HANDOFF.md).
2. Get real price data in through `tools/clipper`, then fix `tools/clipper/parse.js` from the diagnostics.
3. Then: phone notifications for price drops, daily scheduled export, matching tuning.
