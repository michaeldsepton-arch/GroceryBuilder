// Reads the product (or the products) on the page you are looking at, for "Add to app".
// It only reads what the page already shows: it never loads other pages, scrolls or clicks.
// Needs parse.js (BBParse) loaded first. Used by the extension popup and by the bookmarklet.
(function (root) {
  const P = root.BBParse;

  // [host fragment, store id, store name, colour, link pattern for the store's own product id]
  const KNOWN = [
    ['walmart.', 'walmart', 'Walmart', 0xFF0071CE, /\/ip\/(?:[^/?#]+\/)?(\d{5,})/],
    ['realcanadiansuperstore.', 'superstore', 'Real Canadian Superstore', 0xFFD9232D, /\/p\/([A-Za-z0-9]+(?:_[A-Za-z]+)?)(?:[/?#]|$)/],
    ['wholesaleclub.', 'wholesaleclub', 'Wholesale Club', 0xFFE8731A, /\/p\/([A-Za-z0-9]+(?:_[A-Za-z]+)?)(?:[/?#]|$)/],
    ['nofrills.', 'nofrills', 'No Frills', 0xFFFFC20E, /\/p\/([A-Za-z0-9]+(?:_[A-Za-z]+)?)(?:[/?#]|$)/],
    ['freshco.', 'freshco', 'FreshCo', 0xFF2E8B3D, null],
    ['shoppersdrugmart.', 'shoppers', 'Shoppers Drug Mart', 0xFFC8102E, null],
  ];
  const PALETTE = [0xFF6B4FA0, 0xFF1F7A8C, 0xFFB5651D, 0xFF4A6FA5, 0xFF8C3B5E];

  function storeOf(host) {
    for (let i = 0; i < KNOWN.length; i++) {
      if (host.indexOf(KNOWN[i][0]) >= 0) return { id: KNOWN[i][1], name: KNOWN[i][2], color: KNOWN[i][3], link: KNOWN[i][4] };
    }
    const base = host.replace(/^(www|shop|m|www2)\./, '').replace(/\.(com|ca|net|org|co|shop|store)(\.[a-z]{2})?$/, '');
    const id = base.replace(/[^a-z0-9]+/g, '') || 'other';
    const name = base.split(/[.\-]/).map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1); }).join(' ');
    let h = 0;
    for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
    return { id: id, name: name, color: PALETTE[h % PALETTE.length], link: null };
  }

  const num = function (v) {
    if (typeof v === 'number') return v;
    if (typeof v === 'string') { const m = /\d+(?:\.\d+)?/.exec(v.replace(/,/g, '')); return m ? parseFloat(m[0]) : null; }
    return null;
  };
  const text = function (el) { return el ? (el.innerText || el.textContent || '').trim() : ''; };
  const absUrl = function (u) { try { return new URL(u, location.href).href; } catch (e) { return ''; } };

  // The store's own product id from a link, so the same product is recognised later.
  function pidOf(store, url, fallback) {
    let u;
    try { u = new URL(url, location.href); } catch (e) { u = null; }
    if (u && store.link) { const m = store.link.exec(u.pathname + u.search); if (m) return m[1]; }
    if (u && u.hostname === location.hostname) {
      const p = u.pathname.replace(/\/+$/, '');
      if (p.split('/').length >= 3 || /\d{4,}/.test(p)) return p;
    }
    return fallback || null;
  }

  function hash(s) { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0; return h.toString(36); }

  // ---- 1. data the page publishes about its products (schema.org) ----
  function ldObjects() {
    const out = [];
    document.querySelectorAll('script[type="application/ld+json"]').forEach(function (s) {
      let j;
      try { j = JSON.parse(s.textContent); } catch (e) { return; }
      (function walk(o, d) {
        if (!o || typeof o !== 'object' || d > 8) return;
        if (Array.isArray(o)) { o.forEach(function (x) { walk(x, d + 1); }); return; }
        out.push(o);
        ['@graph', 'itemListElement', 'item', 'mainEntity', 'hasVariant'].forEach(function (k) { if (o[k]) walk(o[k], d + 1); });
      })(j, 0);
    });
    return out;
  }
  const isType = function (o, t) { const x = o['@type']; return Array.isArray(x) ? x.indexOf(t) >= 0 : x === t; };

  function offerOf(o) {
    let off = o.offers;
    if (Array.isArray(off)) off = off[0];
    if (off && off.offers) off = Array.isArray(off.offers) ? off.offers[0] : off.offers;
    return off || {};
  }

  function fromLd(store) {
    const items = [];
    ldObjects().forEach(function (o) {
      if (!isType(o, 'Product') || !o.name) return;
      const off = offerOf(o);
      const price = num(off.price !== undefined ? off.price : (off.lowPrice !== undefined ? off.lowPrice : (off.priceSpecification || {}).price));
      if (price === null || price <= 0) return;
      let img = o.image;
      if (Array.isArray(img)) img = img[0];
      if (img && typeof img === 'object') img = img.url;
      const url = absUrl(off.url || o.url || location.href);
      const brand = typeof o.brand === 'object' && o.brand ? o.brand.name : o.brand;
      items.push({ name: String(o.name), brand: brand ? String(brand) : '', price: price, img: img ? absUrl(img) : '', url: url,
        pid: pidOf(store, url, o.sku ? String(o.sku) : null), sizeText: o.size || o.weight || '', from: 'ld' });
    });
    return items;
  }

  // ---- 2. the main product on a product page (page title, picture, price shown) ----
  function metaContent(sel) { const el = document.querySelector(sel); return el ? (el.getAttribute('content') || '').trim() : ''; }

  function fromPage(store) {
    const name = text(document.querySelector('h1')) || metaContent('meta[property="og:title"]') || document.title;
    if (!name) return [];
    let price = num(metaContent('meta[property="product:price:amount"]') || metaContent('meta[property="og:price:amount"]') ||
      metaContent('meta[itemprop="price"]') || text(document.querySelector('[itemprop="price"]')));
    let was = null, variable = false, size = null, unit = null;
    if (price === null) {
      // the price shown beside the title: the nearest block around the heading that holds a $ amount
      let el = document.querySelector('h1');
      for (let i = 0; el && i < 8; i++, el = el.parentElement) {
        const t = el.innerText || '';
        if (/\$\s*\d/.test(t) && t.length < 1500) {
          const c = P.parseCardText(t.split('\n').slice(0, 30).join('\n'));
          if (c) { price = c.price; was = c.was; variable = c.variable; size = c.size; unit = c.unit; }
          break;
        }
      }
    }
    if (price === null || price <= 0) return [];
    const img = metaContent('meta[property="og:image"]');
    return [{ name: name, brand: '', price: price, was: was, variable: variable, size: size, unit: unit, img: img ? absUrl(img) : '',
      url: location.href, pid: pidOf(store, location.href, null), sizeText: '', from: 'page' }];
  }

  // ---- 3. product cards on a search or category page ----
  function fromCards(store) {
    const items = [], done = {};
    const idOf = function (a) {
      let u;
      try { u = new URL(a.href, location.href); } catch (e) { return null; }
      if (store.link) { const m = store.link.exec(u.pathname); return m ? m[1] : null; }
      const p = u.pathname.replace(/\/+$/, '');
      if (u.origin !== location.origin || p.split('/').length < 3) return null;
      return /\d{4,}|\/(?:product|products|p|pd|prod|item|ip)\//i.test(p) ? p : null;
    };
    const cardFor = function (a) {
      let el = a;
      for (let i = 0; i < 9 && el.parentElement; i++) {
        const par = el.parentElement, ids = {};
        let n = 0;
        par.querySelectorAll('a[href]').forEach(function (x) { const id = idOf(x); if (id && !ids[id]) { ids[id] = 1; n++; } });
        if (n > 1) return null;
        el = par;
        if (/\$\s*\d/.test(el.innerText || '')) return el;
      }
      return null;
    };
    const links = document.querySelectorAll('a[href]');
    for (let i = 0; i < links.length; i++) {
      const a = links[i], id = idOf(a);
      if (!id || done[id]) continue;
      done[id] = 1;
      const card = cardFor(a);
      if (!card) continue;
      const q = function (sel) { return text(card.querySelector(sel)); };
      const name = q('[data-testid*="title" i],[data-automation-id*="title" i],[data-testid*="name" i],[itemprop="name"],h2,h3') ||
        a.getAttribute('aria-label') || (card.querySelector('img') || {}).alt || text(a);
      const img = card.querySelector('img');
      items.push({ cardText: text(card), name: String(name).split('\n')[0].trim(), brand: q('[data-testid*="brand" i],[data-automation-id*="brand" i]'),
        sizeText: q('[data-testid*="size" i],[data-testid*="package" i]'), img: img ? (img.currentSrc || img.src || '') : '', url: a.href, pid: id, from: 'card' });
    }
    return items;
  }

  function finish(store, r) {
    let name = P.cleanName(r.name).replace(/\s*\|.*$/, '').replace(/\s+-\s+(Walmart|Real Canadian Superstore|No Frills|FreshCo|Costco)[^]*$/i, '').trim();
    if (!name || name.charAt(0) === '$') return null;
    let price = r.price, was = r.was, variable = !!r.variable, size = r.size, unit = r.unit;
    if (r.cardText) {
      const c = P.parseCardText(r.cardText);
      if (!c) return null;
      price = c.price; was = c.was; variable = c.variable; size = c.size; unit = c.unit;
    }
    if (typeof price !== 'number' || !(price > 0)) return null;
    if (!variable && r.sizeText) { const sz = P.parseSize(String(r.sizeText)); if (sz[0]) { size = sz[0]; unit = sz[1]; } }
    if (!variable && !size) { const sz = P.parseSize(name); size = sz[0]; unit = sz[1]; }
    const pid = r.pid || hash(name + '|' + price);
    const out = P.mk(store.id, pid, name, price, { brand: r.brand, img: r.img, was: was && was > price ? was : null, size: size || 1, unit: unit || 'each',
      variable: variable, taxable: P.guessTaxable(name, ''), url: r.url, src: 'phone' });
    out.seen = new Date().toISOString();
    return out;
  }

  function run() {
    const store = storeOf(location.hostname);
    const ld = fromLd(store);
    const onProductPage = ld.length === 1 || /^product$/i.test(metaContent('meta[property="og:type"]')) ||
      (store.link && store.link.test(location.pathname)) || /\/(?:ip|p|product|products|pd|prod|item)\/[^/]/i.test(location.pathname);
    let raw;
    if (onProductPage) {
      raw = ld.length ? ld.slice(0, 1) : fromPage(store);
      if (!raw.length) raw = fromCards(store);
    } else {
      raw = ld.length > 1 ? ld : fromCards(store);
      if (!raw.length && ld.length) raw = ld;
      if (!raw.length) raw = fromPage(store);
    }
    const seen = {}, items = [];
    raw.forEach(function (r) {
      const it = finish(store, r);
      if (it && !seen[it.id]) { seen[it.id] = 1; items.push(it); }
    });
    return { store: { id: store.id, name: store.name, color: store.color }, items: items, page: { url: location.href, title: document.title }, kind: onProductPage ? 'product' : 'list' };
  }

  root.BBExtract = { run: run, storeOf: storeOf };
})(typeof globalThis !== 'undefined' ? globalThis : this);
