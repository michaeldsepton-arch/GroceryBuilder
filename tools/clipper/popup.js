const STORES = {
  superstore: { id: 'superstore', name: 'Real Canadian Superstore', color: 0xFFD9232D, location: '5016 51 Ave, Red Deer', online: true },
  wholesaleclub: { id: 'wholesaleclub', name: 'Wholesale Club', color: 0xFFE8731A, location: '6350 67th St, Red Deer', online: true },
  walmart: { id: 'walmart', name: 'Walmart', color: 0xFF0071CE, location: '6375 50 Ave, Red Deer', online: true },
};
const STALE_DAYS = 45;
const $ = (id) => document.getElementById(id);

function storeStatus(key, info) {
  if (!info || !info.lastSeen) return ['', ''];
  if (key === 'superstore') {
    const ids = info.ids || [];
    if (ids.length && ids.every((i) => i === '1579')) return ['ok', 'Red Deer store confirmed (id 1579)'];
    if (ids.length) return ['warn', 'Saw store id ' + ids.join(', ') + ': choose your Red Deer store on the site, then clear and re-browse'];
    return ['warn', 'Store not confirmed yet: search for something on the site'];
  }
  if (key === 'walmart') {
    return info.redDeer ? ['ok', 'Page mentions Red Deer / 6375 50 Ave'] : ['warn', 'Could not confirm Red Deer: set your Walmart store to 6375 50 Ave'];
  }
  return ['ok', 'Store id(s): ' + ((info.ids || []).join(', ') || 'unknown') + ': check it is 67th Street'];
}

async function render() {
  const st = await chrome.storage.local.get(['items', 'storeInfo']);
  const items = Object.values(st.items || {});
  const info = st.storeInfo || {};
  $('stores').innerHTML = '';
  Object.keys(STORES).forEach((k) => {
    const n = items.filter((i) => i.store === k).length;
    const [cls, text] = storeStatus(k, info[k]);
    const div = document.createElement('div');
    div.className = 'card';
    div.innerHTML = '<div class="row"><span class="name">' + STORES[k].name + '</span><span class="n">' + n + '</span></div>' +
      (text ? '<div class="' + cls + '">' + text + '</div>' : '<div class="tiny">Nothing saved yet</div>') +
      (n ? '<button class="alt" data-clear="' + k + '">Clear ' + STORES[k].name + '</button>' : '');
    $('stores').appendChild(div);
  });
  document.querySelectorAll('[data-clear]').forEach((b) => b.onclick = async () => {
    const k = b.dataset.clear;
    const s = await chrome.storage.local.get(['items', 'storeInfo']);
    const keep = {};
    Object.values(s.items || {}).forEach((i) => { if (i.store !== k) keep[i.id] = i; });
    const inf = s.storeInfo || {}; delete inf[k];
    await chrome.storage.local.set({ items: keep, storeInfo: inf });
    render();
  });
}

async function gzip(text) {
  const cs = new CompressionStream('gzip');
  const w = cs.writable.getWriter();
  w.write(new TextEncoder().encode(text)); w.close();
  return new Response(cs.readable).blob();
}

$('export').onclick = async () => {
  const st = await chrome.storage.local.get(['items', 'storeInfo']);
  const cutoff = Date.now() - STALE_DAYS * 864e5;
  const items = Object.values(st.items || {}).filter((i) => Date.parse(i.seen) >= cutoff).map((i) => { const c = Object.assign({}, i); delete c.seen; return c; });
  if (!items.length) { $('msg').textContent = 'Nothing saved yet. Browse some searches first.'; return; }
  const stores = Object.keys(STORES).filter((k) => items.some((i) => i.store === k)).map((k) => STORES[k]);
  const catalog = { generated: new Date().toISOString(), stores, items };
  const blob = await gzip(JSON.stringify(catalog));
  const url = URL.createObjectURL(blob);
  chrome.downloads.download({ url, filename: 'budget-basket-catalog.json.gz', conflictAction: 'overwrite', saveAs: false }, () => {
    $('msg').textContent = items.length + ' items saved to your Downloads folder as budget-basket-catalog.json.gz. Now double-click publish.bat.';
  });
};

$('diag').onclick = async () => {
  const st = await chrome.storage.local.get(['items', 'storeInfo', 'samples']);
  const counts = {};
  Object.values(st.items || {}).forEach((i) => { counts[i.store] = (counts[i.store] || 0) + 1; });
  const text = JSON.stringify({ version: chrome.runtime.getManifest().version, counts, storeInfo: st.storeInfo, samples: st.samples }, null, 1);
  await navigator.clipboard.writeText(text);
  $('msg').textContent = 'Copied. Paste it into the chat.';
};

render();
