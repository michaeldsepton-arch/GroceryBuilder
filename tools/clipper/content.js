// Collects product data the page already received and stores it locally.
// It never navigates, clicks, scrolls or requests anything.
(function () {
  const host = location.hostname;
  const store = host.indexOf('walmart') >= 0 ? 'walmart' : host.indexOf('realcanadiansuperstore') >= 0 ? 'superstore' : 'wholesaleclub';
  const P = globalThis.BBParse;
  let pending = { items: [], hints: null, samples: [] };
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
    el.textContent = 'Budget Basket: ' + shown + ' items saved';
    el.style.opacity = '1';
    clearTimeout(el.__t);
    el.__t = setTimeout(function () { el.style.opacity = '0'; }, 2500);
  }

  function flush() {
    timer = null;
    const batch = pending;
    pending = { items: [], hints: null, samples: [] };
    if (!batch.items.length && !batch.hints) return;
    chrome.storage.local.get(['items', 'storeInfo', 'samples'], function (st) {
      const items = st.items || {}, info = st.storeInfo || {}, samples = st.samples || {};
      const now = new Date().toISOString();
      batch.items.forEach(function (it) { it.seen = now; items[it.id] = it; });
      const cur = info[store] || { ids: [], redDeer: false };
      if (batch.hints) {
        batch.hints.ids.forEach(function (i) { if (cur.ids.indexOf(i) < 0) cur.ids.push(i); });
        cur.redDeer = cur.redDeer || batch.hints.redDeer;
      }
      cur.lastSeen = now;
      info[store] = cur;
      const s = samples[store] || [];
      batch.samples.forEach(function (x) { if (s.length < 3) s.push(x); });
      samples[store] = s;
      chrome.storage.local.set({ items: items, storeInfo: info, samples: samples });
      if (batch.items.length) toast(batch.items.length);
    });
  }
  function queue() { if (!timer) timer = setTimeout(flush, 800); }

  function addItem(it, raw) {
    if (!it) return;
    pending.items.push(it);
    if (raw) pending.samples.push(raw);
    queue();
  }

  function fromWalmart(json) {
    P.walmartProducts(json).forEach(function (p) { addItem(P.walmartItem(p), p); });
  }

  window.addEventListener('message', function (ev) {
    const d = ev.data;
    if (ev.source !== window || !d || !d.__bb) return;
    try {
      if (store === 'walmart') {
        fromWalmart(d.body);
      } else {
        P.loblawProducts(d.body).forEach(function (p) { addItem(P.loblawItem(store, p), p); });
        try {
          const sid = d.req && JSON.parse(d.req).storeId;
          if (sid) { pending.hints = pending.hints || { ids: [], redDeer: false }; pending.hints.ids.push(String(sid)); queue(); }
        } catch (e) {}
      }
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
})();
