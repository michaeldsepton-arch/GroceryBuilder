# Budget Basket Clipper (Edge / Chrome extension)

You browse Walmart, Superstore and Wholesale Club normally. The extension saves the products, prices and sale
prices on the pages **you open**, then exports them for the Budget Basket app.

It does **not** open pages, search, click, scroll or send requests to the stores. It only keeps a copy of data
your own browser already received. Nothing leaves your PC until you publish.

## Install (once, Edge)
1. Open `edge://extensions`, turn on **Developer mode** (left side).
2. Click **Load unpacked** and pick the `tools\clipper` folder inside Budget Basket.
3. Pin the extension (puzzle icon, then the pin) so you can see its basket icon.
(Chrome: `chrome://extensions`, same steps.)

## Every week (about 10 to 15 minutes)
1. On each site, pick your Red Deer store the normal way (Superstore: 5016 51 Ave; Wholesale Club: 67th Street;
   Walmart: 6375 50 Ave). A green "Budget Basket: N items saved" note shows when a page was captured.
2. Open a category (or search for what you buy) and **just scroll down it**. Every product card that appears
   on screen is saved with its price and sale price, no need to open products. Scroll slowly enough for the
   cards to load. The extension never scrolls for you.
3. Click the extension icon. It shows a count per store and whether it could confirm the Red Deer store.
   Click **Export prices for the app**.
4. Double-click `publish.bat` (needs `gh auth login` once). In the app: **More, Refresh prices**.

Items you captured earlier stay in the file for 45 days, so each week adds to the list instead of replacing it.

## If the numbers look wrong
Click **Copy diagnostics** and paste it into the chat.
