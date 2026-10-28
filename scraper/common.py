"""Shared helpers: size parsing, tax guess, catalog item shape."""
import re

# Terms we sweep per store. Each returns up to MAX_PER_TERM products, so this
# list is what decides what ends up in the catalog. Edit freely.
SEARCH_TERMS = [l.strip() for l in open(__file__.replace("common.py", "terms.txt")) if l.strip() and not l.startswith("#")]

UNIT_MAP = {
    "g": "g", "gram": "g", "grams": "g", "kg": "kg", "kilogram": "kg",
    "lb": "lb", "lbs": "lb", "pound": "lb", "oz": "oz", "ounce": "oz",
    "ml": "ml", "l": "l", "litre": "l", "liter": "l", "litres": "l", "liters": "l",
    "ea": "each", "each": "each", "ct": "each", "count": "each", "pk": "each", "pack": "each",
    "un": "each", "unit": "each",
}

SIZE_RE = re.compile(
    r"(?:(\d+(?:\.\d+)?)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|lbs?|oz|ml|l|ct|count|ea|each|pk|pack)\b",
    re.I,
)

TAXABLE_WORDS = re.compile(
    r"\b(pop|soda|soft drink|carbonated|energy drink|chips?|crisps|candy|candies|chocolate|gum|"
    r"snack|popcorn|pretzels?|cleaning|laundry|detergent|paper towel|toilet|tissue|diaper|"
    r"shampoo|conditioner|soap|toothpaste|cosmetic|makeup|vitamin|supplement|medicine|"
    r"pharmacy|household|pet|cat|dog|toy|electronics|clothing|kitchen|garden|auto|battery|"
    r"candle|cosmetics|beauty|health|baby care|prepared meal|deli ready|hot food|alcohol)\b",
    re.I,
)


def parse_size(text):
    """'2 x 355 mL' -> (710, 'ml'); returns (None, None) when unknown."""
    if not text:
        return None, None
    m = SIZE_RE.search(text)
    if not m:
        return None, None
    mult = float(m.group(1)) if m.group(1) else 1.0
    val = float(m.group(2)) * mult
    unit = UNIT_MAP.get(m.group(3).lower().rstrip("s") if m.group(3).lower() not in UNIT_MAP else m.group(3).lower())
    return (val, unit) if unit else (None, None)


def guess_taxable(*texts):
    return bool(TAXABLE_WORDS.search(" ".join(t for t in texts if t)))


def item(store, pid, name, price, **kw):
    d = {"id": f"{store}:{pid}", "store": store, "name": name.strip(), "price": round(float(price), 2)}
    for k, v in kw.items():
        if v not in (None, "", False):
            d[k] = v
    return d
