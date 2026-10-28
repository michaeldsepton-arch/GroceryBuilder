# Local price collector

Runs on your own computer (Windows/Mac/Linux) so the stores see a normal browser on a home connection.

## One-time install
1. Install Python 3.10+ (python.org) and the GitHub CLI (https://cli.github.com), then run `gh auth login`.
2. In this folder:
   ```
   pip install playwright
   playwright install chromium
   ```
3. Choose your stores (a browser opens per store; pick the Red Deer location, press Enter in the terminal):
   ```
   python scrape_local.py --setup
   ```

## Every time you want fresh prices
```
python scrape_local.py
```
It collects prices and sale prices, uploads them, and the app picks them up under **More -> Refresh prices**.
Windows: double-click `run.bat`. Mac: double-click `run.command` (first time: `chmod +x run.command`).

Add or remove search words in `scraper/terms.txt`.
