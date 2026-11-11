#!/usr/bin/env python3
"""Builds install-bookmarklet.html: the same "Add to app" reader as a bookmark, for phone browsers that cannot run
extensions (Chrome on Android). Run again after changing parse.js or extract.js.  Usage: python make_bookmarklet.py"""
import json
import pathlib
import urllib.parse

HERE = pathlib.Path(__file__).resolve().parent

PANEL = r"""
(function(){
  var old=document.getElementById('bb-add-panel'); if(old) old.remove();
  var r=BBExtract.run();
  var d=document.createElement('div'); d.id='bb-add-panel';
  d.style.cssText='position:fixed;left:8px;right:8px;bottom:8px;max-height:70vh;overflow:auto;z-index:2147483647;background:#fffcf5;color:#1b2a23;font:15px/1.4 system-ui,sans-serif;border:2px solid #1f5a43;border-radius:16px;padding:12px;box-shadow:0 4px 18px #0006';
  function b(t,f,p){var x=document.createElement('button');x.textContent=t;x.onclick=f;x.style.cssText='font:inherit;margin:6px 6px 0 0;padding:10px 14px;border-radius:12px;border:1px solid #1f5a43;'+(p?'background:#1f5a43;color:#fff':'background:#fff;color:#1f5a43');return x;}
  var h=document.createElement('div'); h.style.fontWeight='700'; h.textContent='Budget Basket: '+r.items.length+' item'+(r.items.length==1?'':'s')+' found on '+r.store.name; d.appendChild(h);
  if(!r.items.length){var m=document.createElement('div');m.textContent="No product with a price found. Open the product's own page, or a search page that shows prices.";d.appendChild(m);}
  r.items.slice(0,40).forEach(function(i){var l=document.createElement('div');l.style.cssText='padding:4px 0;border-top:1px solid #0002';l.textContent=i.name+'  $'+i.price.toFixed(2);d.appendChild(l);});
  var file=null;
  if(r.items.length){
    var data={type:'budget-basket-items',version:1,generated:new Date().toISOString(),stores:[r.store],items:r.items.map(function(i){delete i.src;return i;})};
    var n='budget-basket-add-'+new Date().toISOString().replace(/[-:T]/g,'').slice(0,12)+'.bbitems.json';
    var blob=new Blob([JSON.stringify(data)],{type:'application/json'});
    d.appendChild(b('Save file for the app',function(){var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=n;document.body.appendChild(a);a.click();a.remove();},true));
    try{file=new File([blob],n,{type:'application/json'});}catch(e){}
    if(file&&navigator.canShare&&navigator.canShare({files:[file]})) d.appendChild(b('Share…',function(){navigator.share({files:[file],title:'Budget Basket items'}).catch(function(){});}));
  }
  d.appendChild(b('Close',function(){d.remove();}));
  document.body.appendChild(d);
})();
"""


def main():
    code = (HERE / "parse.js").read_text(encoding="utf-8") + "\n" + (HERE / "extract.js").read_text(encoding="utf-8") + "\n" + PANEL
    url = "javascript:" + urllib.parse.quote(code, safe="")
    page = PAGE.replace("/*URL*/", json.dumps(url))
    (HERE / "install-bookmarklet.html").write_text(page, encoding="utf-8")
    print("wrote install-bookmarklet.html,", len(url) // 1024, "KB")


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Add to Budget Basket: set up on your phone</title>
<style>
:root{--bg:#f7f2e6;--card:#fffcf5;--ink:#1b2a23;--mute:#6b7a72;--green:#1f5a43;--line:rgba(23,63,48,.16)}
@media (prefers-color-scheme:dark){:root{--bg:#16201b;--card:#1e2b25;--ink:#e8efe9;--mute:#9db0a5;--green:#6fc29a;--line:rgba(255,255,255,.16)}}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,sans-serif;padding:16px;max-width:640px;margin:auto}
h1{font-size:24px}li{margin:8px 0}button{font:inherit;background:var(--green);color:#fff;border:0;border-radius:12px;padding:12px 18px}
textarea{width:100%;height:90px;font:12px monospace;border:1px solid var(--line);border-radius:10px;background:var(--card);color:var(--ink)}
.mute{color:var(--mute)}
</style></head><body>
<h1>Add to Budget Basket</h1>
<p>Chrome on Android cannot run extensions, so this is the same thing as a bookmark. Set it up once.</p>
<ol>
<li>Press <b>Copy</b> below.</li>
<li>In Chrome, bookmark any page (menu ⋮ → ☆). Then menu ⋮ → <b>Bookmarks</b> → press and hold the new bookmark → <b>Edit</b>.</li>
<li>Name it <b>Add to app</b>. Replace the address (URL) with what you copied (paste), and save.</li>
</ol>
<button id="copy">Copy</button> <span id="ok" class="mute"></span>
<p class="mute">If pasting says nothing happened, long-press the box below, Select all, Copy.</p>
<textarea id="t" readonly></textarea>
<h2>Using it</h2>
<ol>
<li>On a store website, open the product (or a search page that shows prices).</li>
<li>Tap the address bar, type <b>Add to app</b> and tap the bookmark in the suggestions.</li>
<li>A box appears with what it found. Tap <b>Save file for the app</b>.</li>
<li>In Budget Basket: More → <b>Add items from a file</b>, pick the file from Downloads.</li>
</ol>
<p class="mute">Items already in the app are never added twice, and nothing in the app is replaced or removed.</p>
<script>
const U=/*URL*/;
document.getElementById('t').value=U;
document.getElementById('copy').onclick=async()=>{try{await navigator.clipboard.writeText(U);document.getElementById('ok').textContent='Copied.'}catch(e){document.getElementById('t').select();document.getElementById('ok').textContent='Select all and copy from the box.'}};
</script></body></html>
"""

if __name__ == "__main__":
    main()
