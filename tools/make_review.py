#!/usr/bin/env python3
"""Builds the review page for the everyday-items list: tools/review/everyday-items-review.html

Everything starts approved. The owner presses "Approve all" (or just keeps the ticks), unticks what is NOT wanted,
then "Download my decisions" and sends the file back. Items unticked are removed from assets/seed/staples.json.
Usage: python tools/make_review.py catalog.json.gz
"""
import collections
import html
import json
import pathlib
import random
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import scope_check as sc  # noqa: E402
import staples_check as st  # noqa: E402

SRC_LABEL = {"list": "Your list", "note": "Your notes", "cat": "Category from your list", "sug": "My suggestion"}

# What was written in the notes screenshots: brand, size and the price seen. Kept as specific products to watch.
NOTES = [
    ("Redpath Special Fine Granulated Sugar 2 kg", "$2.77", "sugar"),
    ("Eggs", "$10.38", "eggs"),
    ("Butter", "$4.97", "butter"),
    ("Malai paneer 20%", "$4.49", "paneer"),
    ("Great Value clear plastic wrap 90 m", "$3.93", "plastic wrap"),
    ("Canola oil 3 L, No Name", "$11", "canola oil"),
    ("Peanut butter", "", "peanut butter"),
    ("Davidoff espresso 57", "$11.99", "espresso"),
    ("Brar's desi ghee 800 g", "$16", "ghee"),
    ("Plain paratha, PRAN, 30", "$10.99", "paratha"),
    ("Chicken leg with skin 2.5 lb (halal market, already in the app at $3.75/lb)", "$9.375", "chicken"),
    ("Marble cheddar cheese, Co-op / Armstrong", "$5", "marble"),
    ("Storage box / deep container for bathroom drawer", "", "storage"),
    ("Tuna, 2 cans", "", "tuna"),
    ("Butterscotch chips", "", "butterscotch"),
    ("Dusting brush", "", "dusting"),
    ("Toor dal", "", "dal"),
    ("Moong dal", "", "dal"),
]


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def main():
    items = st.load(sys.argv[1])
    scoped = [i for i in items if sc.in_scope(i["name"], i.get("brand") or "", i.get("cat") or "")]
    by = collections.defaultdict(list)
    for i in scoped:
        if st.insane(i):
            continue
        e = st.match(i)
        if e:
            by[(e["group"], e["name"])].append(i)
    random.seed(4)
    groups = []
    for g in st.STAPLES["groups"]:
        rows = []
        for e in g["items"]:
            lst = by.get((g["id"], e[0]), [])
            samples = random.sample([i["name"] for i in lst], min(3, len(lst)))
            rows.append({"id": f"{g['id']}:{slug(e[0])}", "name": e[0], "src": e[2], "count": len(lst), "phrases": e[1].replace("|", ", "), "samples": samples})
        groups.append({"id": g["id"], "name": g["name"], "rows": rows, "count": sum(r["count"] for r in rows)})
    notes = [{"id": f"note:{slug(n)}", "name": n, "price": p} for n, p, _ in NOTES]
    data = {"groups": groups, "notes": notes, "total": sum(g["count"] for g in groups), "scoped": len(scoped)}
    out = HERE / "review" / "everyday-items-review.html"
    out.parent.mkdir(exist_ok=True)
    out.write_text(PAGE.replace("/*DATA*/null", json.dumps(data, ensure_ascii=False)), encoding="utf-8")
    print("wrote", out, "-", sum(len(g["rows"]) for g in groups), "items in", len(groups), "groups,", data["total"], "products shown")


PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Budget Basket: everyday items to review</title>
<style>
:root{--bg:#f7f2e6;--card:#fffcf5;--ink:#1b2a23;--mute:#6b7a72;--green:#1f5a43;--green2:#dcebdd;--red:#c8553d;--gold:#9c7a33;--line:rgba(23,63,48,.14)}
@media (prefers-color-scheme:dark){:root{--bg:#16201b;--card:#1e2b25;--ink:#e8efe9;--mute:#9db0a5;--green:#6fc29a;--green2:#27433a;--red:#ef8a73;--gold:#d8b46a;--line:rgba(255,255,255,.14)}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.4 system-ui,Segoe UI,Roboto,sans-serif;padding-bottom:90px}
.wrap{max-width:860px;margin:0 auto;padding:0 16px}
h1{font-size:26px;margin:22px 0 6px}h2{font-size:19px;margin:0}p{margin:6px 0}.mute{color:var(--mute)}
.bar{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 0}
.bar .wrap{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
button{font:inherit;border:1px solid var(--green);background:transparent;color:var(--green);border-radius:12px;padding:8px 14px;cursor:pointer}
button.primary{background:var(--green);color:#fff}button:active{opacity:.8}
.chips{display:flex;gap:6px;flex-wrap:wrap;margin:10px 0}
.chip{border:1px solid var(--line);background:var(--card);border-radius:999px;padding:4px 12px;font-size:14px;cursor:pointer;color:var(--ink)}
.chip.on{background:var(--green2);border-color:var(--green)}
.group{background:var(--card);border:1px solid var(--line);border-radius:18px;margin:14px 0;overflow:hidden}
.ghead{display:flex;align-items:center;gap:10px;padding:12px 14px;background:var(--green2)}
.ghead .n{margin-left:auto;font-size:13px;color:var(--mute)}
.row{display:flex;gap:10px;padding:10px 14px;border-top:1px solid var(--line);align-items:flex-start}
.row input,.ghead input{width:22px;height:22px;margin-top:2px;flex:none;accent-color:var(--green)}
.row.off .t{text-decoration:line-through;color:var(--mute)}
.t{font-weight:600}.sub{font-size:13px;color:var(--mute)}
.badge{display:inline-block;font-size:11px;padding:1px 8px;border-radius:999px;border:1px solid var(--line);margin-left:6px;vertical-align:1px;font-weight:500}
.b-list{color:var(--green)}.b-note{color:var(--gold)}.b-cat{color:var(--mute)}.b-sug{color:var(--red)}
.zero{color:var(--red);font-size:13px}
.foot{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:1px solid var(--line);padding:10px 0}
.foot .wrap{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
details summary{cursor:pointer;color:var(--green);font-size:14px;margin-top:4px}
</style></head><body>
<div class="bar"><div class="wrap">
  <button class="primary" id="all">Approve all</button><button id="none">Untick all</button>
  <span id="count" class="mute"></span>
</div></div>
<div class="wrap">
  <h1>Everyday items to review</h1>
  <p>This is what the app will show when "Show only everyday items" is on. Your whole price list stays on the phone; nothing is deleted.
  Everything starts <b>ticked</b>. Press <b>Approve all</b>, then <b>untick</b> anything you do not want, and press <b>Download my decisions</b> at the bottom. Send me that file.</p>
  <p class="mute">Each line is a group of products that gets kept. The number is how many store products it would show today; examples are underneath. Tick or untick a whole group with its header box.</p>
  <div class="chips" id="chips"></div>
  <div id="notes"></div>
  <div id="groups"></div>
</div>
<div class="foot"><div class="wrap">
  <button class="primary" id="dl">Download my decisions</button><button id="copy">Copy decisions</button><span id="msg" class="mute"></span>
</div></div>
<script>
const DATA=/*DATA*/null;
const LABEL={list:'Your list',note:'Your notes',cat:'Category from your list',sug:'My suggestion'};
let filter='all';
const KEY='bb-everyday-review-v1';
let off=new Set(); try{off=new Set(JSON.parse(localStorage.getItem(KEY)||'[]'))}catch(e){}
const $=s=>document.querySelector(s);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function save(){try{localStorage.setItem(KEY,JSON.stringify([...off]))}catch(e){}}
function allRows(){return DATA.groups.flatMap(g=>g.rows).concat(DATA.notes.map(n=>({id:n.id,name:n.name,src:'note'})))}
function render(){
  const chips=[['all','Everything'],['list','Your list'],['note','Your notes'],['cat','Categories I made'],['sug','My suggestions']];
  $('#chips').innerHTML=chips.map(([k,l])=>`<span class="chip ${filter===k?'on':''}" data-f="${k}">${l}</span>`).join('');
  const show=r=>filter==='all'||r.src===filter;
  $('#notes').innerHTML=(filter==='all'||filter==='note')?`<div class="group"><div class="ghead"><h2>Specific products from your notes</h2><span class="n">brand, size and price you wrote</span></div>`+
    DATA.notes.map(n=>`<label class="row ${off.has(n.id)?'off':''}"><input type="checkbox" data-id="${esc(n.id)}" ${off.has(n.id)?'':'checked'}><div><div class="t">${esc(n.name)}${n.price?` <span class="sub">(seen at ${esc(n.price)})</span>`:''}<span class="badge b-note">Your notes</span></div></div></label>`).join('')+`</div>`:'';
  $('#groups').innerHTML=DATA.groups.map(g=>{
    const rows=g.rows.filter(show); if(!rows.length)return '';
    const ticked=rows.filter(r=>!off.has(r.id)).length;
    return `<div class="group"><div class="ghead"><input type="checkbox" data-g="${g.id}" ${ticked===rows.length?'checked':''}><h2>${esc(g.name)}</h2><span class="n">${g.count} products</span></div>`+
      rows.map(r=>`<label class="row ${off.has(r.id)?'off':''}"><input type="checkbox" data-id="${esc(r.id)}" ${off.has(r.id)?'':'checked'}><div><div class="t">${esc(r.name)}<span class="badge b-${r.src}">${LABEL[r.src]}</span> <span class="sub">${r.count} products</span>${r.count===0?' <span class="zero">none in the stores right now</span>':''}</div>
      ${r.samples.length?`<div class="sub">e.g. ${r.samples.map(esc).join(' · ')}</div>`:''}<details><summary>words matched</summary><div class="sub">${esc(r.phrases)}</div></details></div></label>`).join('')+`</div>`;}).join('');
  const rows=allRows(),on=rows.filter(r=>!off.has(r.id)).length;
  $('#count').textContent=`${on} of ${rows.length} kept`;
}
document.addEventListener('change',e=>{
  const t=e.target; if(t.dataset.id){t.checked?off.delete(t.dataset.id):off.add(t.dataset.id)}
  else if(t.dataset.g){const g=DATA.groups.find(x=>x.id===t.dataset.g);g.rows.filter(r=>filter==='all'||r.src===filter).forEach(r=>t.checked?off.delete(r.id):off.add(r.id))}
  save();render();});
document.addEventListener('click',e=>{const f=e.target.dataset&&e.target.dataset.f;if(f){filter=f;render()}});
$('#all').onclick=()=>{off.clear();save();render()};
$('#none').onclick=()=>{allRows().forEach(r=>off.add(r.id));save();render()};
function result(){
  const rows=allRows();
  const approved=rows.filter(r=>!off.has(r.id)),rejected=rows.filter(r=>off.has(r.id));
  return JSON.stringify({made:new Date().toISOString(),approved:approved.map(r=>r.id),rejected:rejected.map(r=>({id:r.id,name:r.name}))},null,1);
}
$('#dl').onclick=()=>{const b=new Blob([result()],{type:'application/json'}),a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='everyday-items-decisions.json';a.click();$('#msg').textContent='Saved to your Downloads folder.'};
$('#copy').onclick=async()=>{try{await navigator.clipboard.writeText(result());$('#msg').textContent='Copied. Paste it into the chat.'}catch(e){$('#msg').textContent='Could not copy; use Download.'}};
render();
</script></body></html>
"""

if __name__ == "__main__":
    main()
