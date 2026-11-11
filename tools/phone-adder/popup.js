const $ = (id) => document.getElementById(id);
const api = typeof browser !== 'undefined' && browser.runtime ? browser : chrome;

function say(text, bad) {
  const m = $('msg');
  m.textContent = text;
  m.className = 'msg' + (bad ? ' bad' : '');
  m.style.display = text ? 'block' : 'none';
}

async function load() {
  const st = await api.storage.local.get(['pending', 'stores']);
  return { items: st.pending || {}, stores: st.stores || {} };
}

async function render() {
  const { items, stores } = await load();
  const list = Object.values(items);
  $('list').hidden = !list.length;
  $('list').innerHTML = '';
  list.slice(-60).reverse().forEach((it) => {
    const row = document.createElement('div');
    row.className = 'it';
    const size = it.unit && it.unit !== 'each' ? ' · ' + it.size + ' ' + it.unit : '';
    row.innerHTML = '<div class="n"><b></b><span class="mute"></span></div><div class="p"></div><button title="Remove">x</button>';
    row.querySelector('b').textContent = it.name;
    row.querySelector('.mute').textContent = (stores[it.store] ? stores[it.store].name : it.store) + size;
    row.querySelector('.p').textContent = '$' + it.price.toFixed(2);
    row.querySelector('button').onclick = async () => {
      const s = await load();
      delete s.items[it.id];
      await api.storage.local.set({ pending: s.items });
      render();
    };
    $('list').appendChild(row);
  });
  $('count').textContent = list.length ? list.length + ' item' + (list.length === 1 ? '' : 's') + ' ready to save' : 'Nothing added yet.';
  $('save').disabled = !list.length;
  $('clear').disabled = !list.length;
  $('share').hidden = !(navigator.canShare && list.length);
}

$('add').onclick = async () => {
  say('');
  $('add').disabled = true;
  try {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (!tab || !/^https?:/.test(tab.url || '')) throw new Error('Open a store web page first, then press Add.');
    await api.scripting.executeScript({ target: { tabId: tab.id }, files: ['parse.js', 'extract.js'] });
    const res = await api.scripting.executeScript({ target: { tabId: tab.id }, func: () => globalThis.BBExtract.run() });
    const r = res && res[0] && res[0].result;
    if (!r || !r.items.length) {
      say("Couldn't find a product with a price on this page. Open the product's own page, or a search page that shows prices, and try again.", true);
    } else {
      const s = await load();
      let added = 0;
      r.items.forEach((it) => { if (!s.items[it.id]) { s.items[it.id] = it; added++; } });
      s.stores[r.store.id] = r.store;
      await api.storage.local.set({ pending: s.items, stores: s.stores });
      const dup = r.items.length - added;
      say(added + ' added from ' + r.store.name + (dup ? ' (' + dup + ' already on your list)' : '') + '.');
    }
  } catch (e) {
    say(String(e && e.message || e), true);
  }
  $('add').disabled = false;
  render();
};

async function buildFile() {
  const { items, stores } = await load();
  const list = Object.values(items);
  const used = {};
  list.forEach((i) => { used[i.store] = true; });
  const data = {
    type: 'budget-basket-items', version: 1, generated: new Date().toISOString(),
    stores: Object.keys(used).map((k) => stores[k]).filter(Boolean),
    items: list.map((i) => { const c = Object.assign({}, i); delete c.src; return c; }),
  };
  const d = new Date(), p = (n) => String(n).padStart(2, '0');
  const name = 'budget-basket-add-' + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + '.bbitems.json';
  return { name, blob: new Blob([JSON.stringify(data)], { type: 'application/json' }), count: list.length };
}

$('save').onclick = async () => {
  const f = await buildFile();
  const url = URL.createObjectURL(f.blob);
  try {
    if (api.downloads) {
      await api.downloads.download({ url, filename: f.name, saveAs: false });
    } else {
      const a = document.createElement('a');
      a.href = url; a.download = f.name; a.click();
    }
    say(f.count + ' items saved as ' + f.name + ' in your Downloads. Open Budget Basket → More → Add items from a file and pick it.');
  } catch (e) {
    say('Could not save the file: ' + (e && e.message || e), true);
  }
};

$('share').onclick = async () => {
  const f = await buildFile();
  const file = new File([f.blob], f.name, { type: 'application/json' });
  try {
    if (navigator.canShare({ files: [file] })) await navigator.share({ files: [file], title: 'Budget Basket items' });
    else say('Sharing is not available here; use Save file.', true);
  } catch (e) { /* cancelled */ }
};

$('clear').onclick = async () => {
  await api.storage.local.set({ pending: {} });
  say('List cleared.');
  render();
};

render();
