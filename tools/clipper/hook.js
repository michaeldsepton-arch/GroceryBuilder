// Runs inside the page (not extension context). It only LISTENS: when the
// store's own page receives product data, a copy is handed to content.js.
// It sends nothing to the stores and makes no requests of its own.
(function () {
  if (window.__bbHooked) return;
  window.__bbHooked = true;
  const interesting = function (u) { return /api\.pcexpress\.ca|\/_next\/data\//.test(String(u)); };
  const tell = function (url, body, req) {
    try { window.postMessage({ __bb: true, url: String(url), body: body, req: req || null }, '*'); } catch (e) {}
  };

  const origFetch = window.fetch;
  window.fetch = function () {
    const args = arguments;
    const p = origFetch.apply(this, args);
    try {
      const a0 = args[0];
      const url = typeof a0 === 'string' ? a0 : (a0 && a0.url) || '';
      if (interesting(url)) {
        const init = args[1] || {};
        const req = typeof init.body === 'string' ? init.body : null;
        p.then(function (res) { return res.clone().json(); }).then(function (b) { tell(url, b, req); }).catch(function () {});
      }
    } catch (e) {}
    return p;
  };

  const open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (m, u) { this.__bbUrl = u; return open.apply(this, arguments); };
  XMLHttpRequest.prototype.send = function (body) {
    try {
      if (interesting(this.__bbUrl)) {
        const self = this;
        this.addEventListener('load', function () {
          try { tell(self.__bbUrl, JSON.parse(self.responseText), typeof body === 'string' ? body : null); } catch (e) {}
        });
      }
    } catch (e) {}
    return send.apply(this, arguments);
  };
})();
