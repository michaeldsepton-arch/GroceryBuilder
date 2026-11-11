# Budget Basket: Add to app

For a product that is not in the app. On the store's website, open the product (or a search page that shows
prices) and press **Add**. The extension saves a small file (`budget-basket-add-….bbitems.json`). In the app:
**More → Add items from a file**.

- It only reads the page you are looking at. It never loads other pages, scrolls or clicks.
- The app only ever **adds**. An item that is already there (same id, or same store, name and size) is left exactly
  as it is, a price refresh keeps added items, and nothing is replaced or removed. Sending the same file twice is harmless.
- Added items are shown even when "Show only everyday items" is on, because you chose them. Pork, alcohol and
  gelatin are still never shown, and non-halal supermarket meat stays hidden when "Halal meat only" is on.

## Where it runs

| Browser | Works? | How |
| --- | --- | --- |
| Chrome / Edge on a PC | Yes | `chrome://extensions` (or `edge://extensions`) → Developer mode → Load unpacked → this folder |
| **Kiwi Browser on Android** | Yes | Kiwi supports Chrome extensions. Copy this folder to the phone, zip it, then in Kiwi open `chrome://extensions` → Developer mode → **+ (from .zip/.crx)** |
| Firefox on Android | Maybe | Needs the add-on published on addons.mozilla.org (not done) |
| **Chrome on Android** | **No extensions** | Use the bookmark version: open `install-bookmarklet.html` on the phone and follow it. Same reader, same file |

Chrome for Android does not support extensions at all; that is Google's limit, not something the app can change.
Kiwi Browser is no longer updated by its author, so the bookmark is the safer long-term choice on a phone.

## Files

- `extract.js` reads the page: the product data the site publishes (schema.org), the product shown on a product page,
  or the cards on a search page. Known stores (Walmart, Superstore, Wholesale Club, No Frills, FreshCo, Shoppers)
  use the same ids as the main clipper, so the same product is recognised.
- `parse.js` is a copy of `../clipper/parse.js` (shared size, price and name rules). Copy it again if that file changes,
  then run `python make_bookmarklet.py`.
- `popup.html`, `popup.js` keep a running list (so several products can go in one file) and save or share the file.
- `make_bookmarklet.py` builds `install-bookmarklet.html`.

File format: `{"type":"budget-basket-items","version":1,"stores":[{id,name,color}],"items":[{id,store,name,brand,price,was,size,unit,variable,taxable,img,url}]}`.
