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
  function num(v) {
    if (typeof v === 'number') return v;
    if (typeof v === 'string') { const m = /\d+(?:\.\d+)?/.exec(v.replace(/,/g, '')); return m ? parseFloat(m[0]) : null; }
    return null;
  }
  // A price may be { value, unit } or a plain number / "$3.99" string.
  function priceVal(o) { return num(o && typeof o === 'object' ? o.value : o); }

  function loblawItem(banner, p) {
    const prices = p.prices || p.pricing || {};
    const price = priceVal(prices.price);
    if (price === null || p.inventoryIndicator === 'OUT_OF_STOCK' || p.stockStatus === 'OUT_OF_STOCK') return null;
    const code = p.code || p.productId || p.sku;
    p = Object.assign({}, p, { code: code, name: p.name || p.title, packageSizing: p.packageSizing || p.packageSize,
      productImage: p.productImage || (p.imageUrl ? [{ imageUrl: p.imageUrl }] : null) });
    if (!p.code || !p.name) return null;
    const was = priceVal(prices.wasPrice);
    const sizing = p.packageSizing || '';
    let sz = parseSize(sizing), size = sz[0], unit = sz[1];
    const pu = prices.price && typeof prices.price === 'object' ? prices.price.unit : null;
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

  // The search API answers { results: [...] }, category pages nest "productTiles"
  // deeper; walk the whole response and pick up anything shaped like a product.
  function loblawProducts(json) {
    const found = [];
    (function walk(o, depth) {
      if (depth > 12 || !o || typeof o !== 'object') return;
      if (Array.isArray(o)) { o.forEach(function (x) { walk(x, depth + 1); }); return; }
      if ((o.code || o.productId || o.sku) && (o.name || o.title) && (o.prices || o.pricing)) { found.push(o); return; }
      Object.keys(o).forEach(function (k) { walk(o[k], depth + 1); });
    })(json, 0);
    return found;
  }

  // ---- Fallback: read what a product card shows on screen ----
  // Text of one card, e.g. "Natrel Milk 2 L $5.83 was $6.49 $0.29/100mL".
  function parseCardText(text) {
    let t = String(text || '').replace(/\s+/g, ' ');
    let was = null;
    const wm = /\b(?:was|reg(?:ular)?\.?|formerly|after limit)\s*(?:price)?:?\s*\$\s*(\d+(?:\.\d{1,2})?)/i.exec(t);
    if (wm) { was = parseFloat(wm[1]); t = t.replace(wm[0], ' '); }
    t = t.replace(/\bsave\s*\$\s*\d+(?:\.\d{1,2})?/ig, ' ')
      .replace(/\$\s*\d+(?:\.\d+)?\s*\/\s*(?:100\s*(?:g|ml)|ea|each|unit)\b/ig, ' ')
      .replace(/\d+\s*for\s*\$\s*\d+(?:\.\d{1,2})?/ig, ' ');
    const pm = /\$\s*(\d{1,4}(?:,\d{3})*(?:\.\d{1,2})?)(\s*(?:\/|per)\s*(lb|kg|100\s*g))?/i.exec(t);
    if (!pm) return null;
    const price = parseFloat(pm[1].replace(/,/g, ''));
    let variable = false, size = null, unit = null;
    if (pm[3]) {
      variable = true;
      const u = pm[3].toLowerCase().replace(/\s+/g, '');
      if (u === 'lb') { size = 1; unit = 'lb'; } else if (u === 'kg') { size = 1; unit = 'kg'; } else { size = 100; unit = 'g'; }
    } else {
      const sz = parseSize(t.replace(/\$\s*[\d.,]+/g, ' '));
      size = sz[0]; unit = sz[1];
    }
    return { price: price, was: (was && was > price) ? was : null, variable: variable, size: size, unit: unit };
  }

  // o: { id, name, brand, img, url, sizeText, text, cat } read from the page.
  function domItem(store, o) {
    // a real product card is a few short lines; menus and filter bars are not
    const lines = String(o.text || '').split(/\n+/).filter(Boolean).length;
    if (lines > 9 || String(o.text || '').length > 300) return null;
    const c = parseCardText(o.text);
    if (!c || !o.id || !o.name || o.name.charAt(0) === '$') return null;
    let size = c.size, unit = c.unit;
    if (!c.variable && o.sizeText) { const sz = parseSize(o.sizeText); if (sz[0]) { size = sz[0]; unit = sz[1]; } }
    if (!c.variable && !size) { const sz = parseSize(o.name); size = sz[0]; unit = sz[1]; }
    return mk(store, o.id, o.name, c.price, {
      brand: o.brand, img: o.img, was: c.was, size: size || 1, unit: unit || 'each', variable: c.variable,
      taxable: guessTaxable(o.name, o.cat), cat: o.cat, url: o.url, src: 'dom',
    });
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

  // "Root/Grocery/Pantry Food/Ketchup" or [{name}] -> ["Pantry Food", "Ketchup"]
  function walmartPath(p) {
    const c = p.category || {};
    let names = Array.isArray(c.path) ? c.path.map(function (x) { return x && x.name; }) : String(c.categoryPath || '').split('/');
    names = names.filter(function (n) { return n && n !== 'Root'; });
    if (names[0] === 'Grocery') names.shift();
    return names;
  }

  function walmartItem(p) {
    const pi = p.priceInfo || {};
    const cur = pi.currentPrice && pi.currentPrice.price;
    const price = typeof cur === 'number' ? cur : (typeof p.price === 'number' ? p.price : num(pi.linePrice));
    if (typeof price !== 'number') return null;
    if (p.isOutOfStock === true || /OUT_OF_STOCK/.test(p.availabilityStatus || '')) return null;
    const wasRaw = pi.wasPrice && typeof pi.wasPrice === 'object' ? pi.wasPrice.price : num(pi.wasPrice);
    const sz = parseSize(p.name || '');
    let size = sz[0], unit = sz[1], variable = false;
    const up = pi.unitPrice && typeof pi.unitPrice === 'object' ? pi.unitPrice.priceString : pi.unitPrice;
    const um = /\/\s*(lb|kg|100\s*g)\b/i.exec(up || '');
    if (!size && um && p.salesUnitType && p.salesUnitType !== 'EACH') {
      variable = true;
      const u = um[1].toLowerCase().replace(/\s+/g, '');
      if (u === 'lb') { size = 1; unit = 'lb'; } else if (u === 'kg') { size = 1; unit = 'kg'; } else { size = 100; unit = 'g'; }
    }
    const img = (p.imageInfo && p.imageInfo.thumbnailUrl) || p.image;
    const path = walmartPath(p);
    return mk('walmart', p.usItemId, p.name, price, {
      brand: p.brand, img: img, was: (typeof wasRaw === 'number' && wasRaw > price) ? wasRaw : null,
      size: size || 1, unit: unit || 'each', variable: variable, taxable: guessTaxable(p.name, path.join(' ')),
      cat: path[0] || '', url: p.canonicalUrl ? 'https://www.walmart.ca' + String(p.canonicalUrl).split('?')[0] : null,
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
    parseCardText: parseCardText, domItem: domItem, walmartProducts: walmartProducts, walmartItem: walmartItem, walmartStoreHints: walmartStoreHints };
  if (typeof module !== 'undefined') module.exports = root.BBParse;
})(typeof globalThis !== 'undefined' ? globalThis : this);
