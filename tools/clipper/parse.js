// Turns the data a store page already holds into Budget Basket catalog items.
// Same logic as scraper/loblaw.py and scraper/walmart.py. Used by the page
// script and by test_parse.js under Node.
(function (root) {
  const UNIT_MAP = { g: 'g', kg: 'kg', lb: 'lb', lbs: 'lb', oz: 'oz', ml: 'ml', l: 'l', ct: 'each', count: 'each',
    ea: 'each', each: 'each', pk: 'each', pack: 'each' };
  const SIZE_RE = /(?:(\d+(?:\.\d+)?)\s*[x×]\s*)?(\d+(?:\.\d+)?)\s*(kg|g|lbs?|oz|ml|l|ct|count|ea|each|pk|pack)\b/i;
  const TAXABLE = new RegExp('\\b(pop|soda|soft drink|carbonated|energy drink|chips?|crisps|candy|candies|chocolate|gum|' +
    'snack|popcorn|pretzels?|cleaning|laundry|detergent|paper towel|toilet|tissue|diaper|shampoo|conditioner|soap|' +
    'toothpaste|cosmetic|makeup|vitamin|supplement|medicine|pharmacy|household|pet|cat|dog|toy|electronics|clothing|' +
    'kitchen|garden|auto|battery|candle|cosmetics|beauty|health|baby care|prepared meal|deli ready|hot food)\\b', 'i');

  function parseSize(text) {
    if (!text) return [null, null];
    const m = SIZE_RE.exec(text);
    if (!m) return [null, null];
    const mult = m[1] ? parseFloat(m[1]) : 1;
    const unit = UNIT_MAP[m[3].toLowerCase()];
    return unit ? [parseFloat(m[2]) * mult, unit] : [null, null];
  }

  function guessTaxable() {
    return TAXABLE.test(Array.prototype.filter.call(arguments, Boolean).join(' '));
  }

  function mk(store, pid, name, price, extra) {
    const d = { id: store + ':' + pid, store: store, name: String(name || '').trim(), price: Math.round(price * 100) / 100 };
    Object.keys(extra || {}).forEach(function (k) {
      const v = extra[k];
      if (v !== null && v !== undefined && v !== '' && v !== false) d[k] = v;
    });
    return d;
  }

  // ---- Real Canadian Superstore / Wholesale Club (PC Express product JSON) ----
  function loblawItem(banner, p) {
    const prices = p.prices || {};
    const price = prices.price && prices.price.value;
    if (price === undefined || price === null || p.inventoryIndicator === 'OUT_OF_STOCK') return null;
    if (!p.code || !p.name) return null;
    const was = prices.wasPrice && prices.wasPrice.value;
    const sizing = p.packageSizing || '';
    let sz = parseSize(sizing), size = sz[0], unit = sz[1];
    const pu = prices.price && prices.price.unit;
    const variable = ['lb', 'kg', '100g'].indexOf(pu) >= 0 || /\b(approx|per)\b/i.test(sizing);
    let isVariable = false;
    if (variable) {
      isVariable = true;
      if (pu === 'lb') { size = 1; unit = 'lb'; }
      else if (pu === 'kg') { size = 1; unit = 'kg'; }
      else { size = 100; unit = 'g'; }
    } else if (size === null) {
      const c = (prices.comparisonPrices || [{}])[0] || {};
      if (c.value && c.quantity && c.unit) {
        unit = { g: 'g', ml: 'ml', ea: 'each', kg: 'kg', l: 'l' }[c.unit] || 'each';
        size = (price / c.value) * c.quantity;
      } else { size = 1; unit = 'each'; }
    }
    const crumbs = (p.breadcrumbs || []).map(function (c) { return (c && c.name) || String(c); }).join(' ');
    const cat = p.breadcrumbs && p.breadcrumbs[0] ? (p.breadcrumbs[0].name || '') : '';
    const img = p.productImage && p.productImage[0] ? p.productImage[0].imageUrl : null;
    const host = banner === 'superstore' ? 'realcanadiansuperstore' : 'wholesaleclub';
    return mk(banner, p.code, p.name, price, {
      brand: p.brand, img: img, was: (was && was > price) ? was : null, size: Math.round(size * 1000) / 1000, unit: unit,
      variable: isVariable, taxable: guessTaxable(p.name, crumbs), cat: cat,
      url: p.link ? 'https://www.' + host + '.ca' + p.link : null,
    });
  }

  // The search API answers { results: [ ...products ] }; accept any such list.
  function loblawProducts(json) {
    if (!json || typeof json !== 'object') return [];
    const arr = Array.isArray(json.results) ? json.results : [];
    return arr.filter(function (p) { return p && p.code && p.prices; });
  }

  // ---- Walmart.ca (Next.js page data) ----
  function walmartProducts(root) {
    const found = [];
    (function walk(o) {
      if (Array.isArray(o)) { o.forEach(walk); return; }
      if (o && typeof o === 'object') {
        if ('usItemId' in o && 'name' in o && ('priceInfo' in o || 'price' in o)) found.push(o);
        Object.keys(o).forEach(function (k) { walk(o[k]); });
      }
    })(root);
    return found;
  }

  function walmartItem(p) {
    const pi = p.priceInfo || {};
    const price = (pi.currentPrice && pi.currentPrice.price) !== undefined ? (pi.currentPrice || {}).price : p.price;
    if (typeof price !== 'number') return null;
    const wasRaw = pi.wasPrice && pi.wasPrice.price;
    const sz = parseSize(p.name || '');
    const img = (p.imageInfo && p.imageInfo.thumbnailUrl) || p.image;
    return mk('walmart', p.usItemId, p.name, price, {
      brand: p.brand, img: img, was: (typeof wasRaw === 'number' && wasRaw > price) ? wasRaw : null,
      size: sz[0] || 1, unit: sz[1] || 'each', taxable: guessTaxable(p.name),
      url: p.canonicalUrl ? 'https://www.walmart.ca' + p.canonicalUrl : null,
    });
  }

  // Which store was the page showing prices for? (used to warn about wrong stores)
  function walmartStoreHints(text) {
    const ids = {};
    const re = /"(?:storeId|nearestStoreId|fulfillmentStoreId|defaultNearestStoreId|deliveryStore|pickupStoreId)"\s*:\s*"?(\d{2,6})/g;
    let m;
    while ((m = re.exec(text))) ids[m[1]] = true;
    return { ids: Object.keys(ids), redDeer: /6375\s*50\s*(Ave|Avenue)|Red Deer/i.test(text) };
  }

  root.BBParse = { parseSize: parseSize, guessTaxable: guessTaxable, loblawItem: loblawItem, loblawProducts: loblawProducts,
    walmartProducts: walmartProducts, walmartItem: walmartItem, walmartStoreHints: walmartStoreHints };
  if (typeof module !== 'undefined') module.exports = root.BBParse;
})(typeof globalThis !== 'undefined' ? globalThis : this);
