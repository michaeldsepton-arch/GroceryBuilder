// Collects product data the page already received or shows on screen and stores
// it locally. It never navigates, clicks, scrolls or requests anything: you
// scroll, it keeps a copy of the product cards that appear.
(function () {
  const host = location.hostname;
  const HOSTS = { walmart: 'walmart', realcanadiansuperstore: 'superstore', wholesaleclub: 'wholesaleclub',
    freshco: 'freshco', shoppersdrugmart: 'shoppers', dollarama: 'dollarama' };
  const store = HOSTS[Object.keys(HOSTS).filter(function (k) { return host.indexOf(k) >= 0; })[0]];
  // stores whose data feed we do not parse: only the cards drawn on screen are read
  const generic = ['freshco', 'shoppers', 'dollarama'].indexOf(store) >= 0;
  const P = globalThis.BBParse;
  let pending = { items: [], hints: null, samples: [], urls: [], api: 0, dom: 0 };
  let timer = null, shown = 0;

  function toast(n) {
    shown += n;
    let el = document.getElementById('bb-clipper-toast');
    if (!el) {
      el = document.createElement('div');
      el.id = 'bb-clipper-toast';
      el.style.cssText = 'position:fixed;right:14px;bottom:14px;z-index:2147483647;background:#1f5a43;color:#fff;font:600 13px system-ui;padding:8px 12px;border-radius:12px;box-shadow:0 2px 8px #0005;transition:opacity .4s;pointer-events:none';
      document.documentElement.appendChild(el);
    }
    el.textContent = 'Budget Basket: ' + shown + ' items saved on this page';
    el.style.opacity = '1';
    clearTimeout(el.__t);
    el.__t = setTimeout(function () { el.style.opacity = '0'; }, 2500);
  }

  function flush() {
    timer = null;
    const batch = pending;
    pending = { items: [], hints: null, samples: [], urls: [], api: 0, dom: 0 };
    if (!batch.items.length && !batch.hints && !batch.urls.length) return;
    chrome.storage.local.get(['items', 'storeInfo', 'samples', 'diag'], function (st) {
      const items = st.items || {}, info = st.storeInfo || {}, samples = st.samples || {}, diag = st.diag || {};
      const now = new Date().toISOString();
      batch.items.forEach(function (it) {
        const old = items[it.id];
        if (old && old.src !== 'dom' && it.src === 'dom') {
          // keep the richer data-feed record, just refresh the price
          old.price = it.price; old.was = it.was || undefined; old.seen = now;
        } else { it.seen = now; items[it.id] = it; }
      });
      const cur = info[store] || { ids: [], redDeer: false };
      if (batch.hints) {
        batch.hints.ids.forEach(function (i) { if (cur.ids.indexOf(i) < 0) cur.ids.push(i); });
        cur.redDeer = cur.redDeer || batch.hints.redDeer;
      }
      cur.lastSeen = now;
      info[store] = cur;
      delete samples[store];
      batch.samples.forEach(function (x) {
        const key = x.k + ':' + store, s = samples[key] || [];
        if (s.length < (x.k === 'weight' ? 8 : 3)) s.push({ parsed: x.parsed, raw: x.raw });
        samples[key] = s;
      });
      const d = diag[store] || { apiItems: 0, domItems: 0, jsonUrls: [] };
      d.apiItems += batch.api; d.domItems += batch.dom;
      batch.urls.forEach(function (u) { if (d.jsonUrls.indexOf(u) < 0 && d.jsonUrls.length < 25) d.jsonUrls.push(u); });
      d.lastPage = location.pathname;
      diag[store] = d;
      chrome.storage.local.set({ items: items, storeInfo: info, samples: samples, diag: diag });
      if (batch.items.length) toast(batch.items.length);
    });
  }
  function queue() { if (!timer) timer = setTimeout(flush, 800); }

  // The department the page is showing, from its address:
  // /en/food/dairy-eggs/c/28003 -> "food dairy eggs". Used when the data has no category.
  function pathCat() {
    return location.pathname.split('/').filter(function (s) { return s && s !== 'en' && s !== 'c' && !/^[\d_]+$/.test(s); })
      .slice(0, 4).join(' ').replace(/[-_]+/g, ' ').slice(0, 80);
  }

  // the price/size related fields of a product, so a diagnostics sample stays small
  function pickRaw(o) {
    if (!o || typeof o !== 'object') return o;
    const out = {};
    Object.keys(o).forEach(function (k) { if (/pric|size|unit|weight|each|code|name|title|packag|sold|text|usItemId/i.test(k)) out[k] = o[k]; });
    return out;
  }

  function addItem(it, raw, kind) {
    if (!it) return;
    if (!it.cat) it.cat = pathCat();
    pending.items.push(it);
    if (kind === 'dom') pending.dom++; else pending.api++;
    if (raw) {
      // items sold by weight or "in singles" are where per-kg / per-each mistakes show up: keep more of those
      const weighty = /_(KG|LB)$/i.test(String(it.id)) || /sold in/i.test(it.name || '');
      pending.samples.push({ k: kind === 'dom' ? 'dom' : (weighty ? 'weight' : 'api'), parsed: it, raw: JSON.stringify(pickRaw(raw)).slice(0, 1500) });
    }
    queue();
  }

  function fromWalmart(json) {
    P.walmartProducts(json).forEach(function (p) { addItem(P.walmartItem(p), p, 'api'); });
  }

  // ---- data the page loads (search, category pages, scrolling) ----
  window.addEventListener('message', function (ev) {
    const d = ev.data;
    if (ev.source !== window || !d || !d.__bb) return;
    try {
      pending.urls.push(String(d.url).replace(/[?#].*$/, '').slice(0, 120));
      if (store === 'walmart') {
        fromWalmart(d.body);
      } else if (!generic) {
        P.loblawProducts(d.body).forEach(function (p) { addItem(P.loblawItem(store, p), p, 'api'); });
        try {
          const sid = d.req && JSON.parse(d.req).storeId;
          if (sid) { pending.hints = pending.hints || { ids: [], redDeer: false }; pending.hints.ids.push(String(sid)); }
        } catch (e) {}
      }
      queue();
    } catch (e) {}
  });

  if (store === 'walmart') {
    const parseNextData = function () {
      const el = document.getElementById('__NEXT_DATA__');
      if (!el || el.__bbDone) return;
      el.__bbDone = true;
      try {
        const text = el.textContent;
        pending.hints = P.walmartStoreHints(text);
        fromWalmart(JSON.parse(text));
        queue();
      } catch (e) {}
    };
    parseNextData();
    new MutationObserver(parseNextData).observe(document.documentElement, { childList: true, subtree: true });
  }

  // ---- what is on screen: product cards the page has drawn as you scroll ----
  const LINK_RE = store === 'walmart' ? /\/ip\/(?:[^/?#]+\/)?(\d{5,})/ : /\/p\/([A-Za-z0-9]+(?:_[A-Za-z]+)?)(?:[/?#]|$)/;
  const seenSig = {};

  function idOf(a) {
    if (generic) {
      let u;
      try { u = new URL(a.href, location.href); } catch (e) { return null; }
      const p = u.pathname.replace(/\/+$/, '');
      if (u.origin !== location.origin || p.split('/').length < 3) return null;
      return /\d{4,}|\/(?:product|products|p|pd|prod|item)\//i.test(p) ? p : null;
    }
    const m = LINK_RE.exec(a.getAttribute('href') || '');
    return m ? m[1] : null;
  }
  function textOf(el) { return el ? (el.innerText || el.textContent || '').trim() : ''; }

  // smallest ancestor of the link that holds a price and only this one product
  function cardFor(a) {
    let el = a;
    for (let i = 0; i < 9 && el.parentElement; i++) {
      const par = el.parentElement;
      const ids = {};
      let n = 0;
      par.querySelectorAll('a[href]').forEach(function (x) { const id = idOf(x); if (id && !ids[id]) { ids[id] = 1; n++; } });
      if (n > 1) return null;
      el = par;
      if (/\$\s*\d/.test(el.innerText || '')) return el;
    }
    return null;
  }

  function scan() {
    let added = 0;
    const cat = textOf(document.querySelector('h1')).slice(0, 60);
    const links = document.querySelectorAll('a[href]');
    const done = {};
    for (let i = 0; i < links.length; i++) {
      const a = links[i], id = idOf(a);
      if (!id || done[id]) continue;
      done[id] = 1;
      const card = cardFor(a);
      if (!card) continue;
      const text = textOf(card);
      if (seenSig[id] === text) continue;
      const q = function (sel) { return textOf(card.querySelector(sel)); };
      const name = q('[data-testid*="title" i],[data-automation-id*="title" i],[data-testid*="name" i],[itemprop="name"],h2,h3') ||
        a.getAttribute('aria-label') || (card.querySelector('img') || {}).alt || textOf(a);
      const img = card.querySelector('img');
      const it = P.domItem(store, {
        id: id, name: name.split('\n')[0].trim(), text: text, cat: cat,
        brand: q('[data-testid*="brand" i],[data-automation-id*="brand" i]'),
        sizeText: q('[data-testid*="size" i],[data-testid*="package" i]'),
        img: img ? (img.currentSrc || img.src || '') : '',
        url: a.href,
      });
      seenSig[id] = text;
      if (it) { addItem(it, { text: text.slice(0, 300) }, 'dom'); added++; }
    }
    return added;
  }

  let scanTimer = null;
  function scanSoon() { if (!scanTimer) scanTimer = setTimeout(function () { scanTimer = null; try { scan(); } catch (e) {} }, 400); }
  window.addEventListener('scroll', scanSoon, { passive: true });
  new MutationObserver(scanSoon).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(scanSoon, 2000);
  scanSoon();
})();
