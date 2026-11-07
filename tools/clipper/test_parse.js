// Run: node test_parse.js
const assert = require('assert');
const P = require('./parse.js');

// size parsing
assert.deepStrictEqual(P.parseSize('2 x 355 mL'), [710, 'ml']);
assert.deepStrictEqual(P.parseSize('500 g'), [500, 'g']);
assert.deepStrictEqual(P.parseSize('12 ct'), [12, 'each']);
assert.deepStrictEqual(P.parseSize('per lb'), [null, null]);

// Loblaw-style product (packaged)
const milk = { code: '20123_EA', name: 'Natrel 2% Milk', brand: 'Natrel', packageSizing: '2 L',
  prices: { price: { value: 5.83, unit: 'ea' }, wasPrice: { value: 6.49 }, comparisonPrices: [{ value: 0.29, quantity: 100, unit: 'ml' }] },
  productImage: [{ imageUrl: 'https://img.example/milk.jpg' }], breadcrumbs: [{ name: 'Dairy & Eggs' }], link: '/en/natrel-milk/p/20123_EA' };
const m = P.loblawItem('superstore', milk);
assert.strictEqual(m.id, 'superstore:20123_EA');
assert.strictEqual(m.price, 5.83); assert.strictEqual(m.was, 6.49);
assert.strictEqual(m.size, 2); assert.strictEqual(m.unit, 'l');
assert.strictEqual(m.cat, 'Dairy & Eggs'); assert.ok(!m.variable);
assert.strictEqual(m.url, 'https://www.realcanadiansuperstore.ca/en/natrel-milk/p/20123_EA');

// by weight
const chicken = { code: '1_KG', name: 'Chicken Thighs', packageSizing: 'approx. 1 kg', prices: { price: { value: 12.1, unit: 'kg' } } };
const c = P.loblawItem('wholesaleclub', chicken);
assert.ok(c.variable); assert.strictEqual(c.unit, 'kg'); assert.strictEqual(c.size, 1);

// size missing: derived from the comparison price
const rice = { code: '2', name: 'Basmati Rice', prices: { price: { value: 12 }, comparisonPrices: [{ value: 0.3, quantity: 100, unit: 'g' }] } };
const r = P.loblawItem('superstore', rice);
assert.strictEqual(r.unit, 'g'); assert.strictEqual(Math.round(r.size), 4000);

// out of stock and malformed are skipped
assert.strictEqual(P.loblawItem('superstore', { code: '3', name: 'x', inventoryIndicator: 'OUT_OF_STOCK', prices: { price: { value: 1 } } }), null);
assert.strictEqual(P.loblawItem('superstore', { name: 'no code', prices: { price: { value: 1 } } }), null);
assert.strictEqual(P.loblawProducts({ results: [milk, { foo: 1 }] }).length, 1);
assert.deepStrictEqual(P.loblawProducts(null), []);
assert.ok(P.loblawItem('superstore', { code: '4', name: 'Chips 200 g', prices: { price: { value: 3 } }, breadcrumbs: [{ name: 'Snacks' }] }).taxable);

// Walmart NEXT_DATA walk
const next = { props: { pageProps: { initialData: { searchResult: { itemStacks: [{ items: [
  { usItemId: '555', name: 'Great Value Large Eggs 12 ct', brand: 'Great Value', priceInfo: { currentPrice: { price: 3.93 }, wasPrice: { price: 4.5 } },
    imageInfo: { thumbnailUrl: 'https://i5.walmartimages.ca/x.jpg' }, canonicalUrl: '/en/ip/eggs/555' },
  { usItemId: '556', name: 'No price' },
  { notAProduct: true } ] }] } } } } };
const found = P.walmartProducts(next);
assert.strictEqual(found.length, 1);
const w = P.walmartItem(found[0]);
assert.strictEqual(w.id, 'walmart:555'); assert.strictEqual(w.price, 3.93); assert.strictEqual(w.was, 4.5);
assert.strictEqual(w.size, 12); assert.strictEqual(w.unit, 'each');

// store hints
const h = P.walmartStoreHints('{"defaultNearestStoreId":"3098","address":"6375 50 Ave, Red Deer"}');
assert.deepStrictEqual(h.ids, ['3098']); assert.ok(h.redDeer);
assert.ok(!P.walmartStoreHints('{"deliveryStore":"1061"}').redDeer);

// category-page tile shape (nested, "pricing", string prices)
const tile = { productId: '999_EA', title: 'Basmati Rice', brand: 'Tilda', packageSize: '4.54 kg',
  pricing: { price: '18.99', wasPrice: '21.99' }, link: '/en/rice/p/999_EA' };
const tiles = P.loblawProducts({ layout: { sections: { list: { components: [{ data: { productTiles: [tile, { x: 1 }] } }] } } } });
assert.strictEqual(tiles.length, 1);
const ti = P.loblawItem('superstore', tiles[0]);
assert.strictEqual(ti.id, 'superstore:999_EA'); assert.strictEqual(ti.price, 18.99); assert.strictEqual(ti.was, 21.99);
assert.strictEqual(ti.size, 4.54); assert.strictEqual(ti.unit, 'kg');

// on-screen card text
let ct = P.parseCardText('Natrel 2% Milk 2 L $5.83 was $6.49 $0.29/100mL');
assert.strictEqual(ct.price, 5.83); assert.strictEqual(ct.was, 6.49); assert.strictEqual(ct.unit, 'l');
ct = P.parseCardText('Chicken Thighs $5.99/lb $13.21/kg');
assert.ok(ct.variable); assert.strictEqual(ct.unit, 'lb'); assert.strictEqual(ct.price, 5.99);
ct = P.parseCardText('Eggs 12 ct Save $1.00 $3.99');
assert.strictEqual(ct.price, 3.99); assert.strictEqual(ct.size, 12);
assert.strictEqual(P.parseCardText('Out of stock'), null);
const di = P.domItem('walmart', { id: '123456', name: 'Great Value Rice 2 kg', text: 'Great Value Rice 2 kg $4.97', url: 'https://www.walmart.ca/en/ip/rice/123456' });
assert.strictEqual(di.id, 'walmart:123456'); assert.strictEqual(di.size, 2); assert.strictEqual(di.unit, 'kg'); assert.strictEqual(di.src, 'dom');

// real Walmart shapes: search result (priceInfo objects) and carousel (price + strings)
const wm1 = P.walmartItem({ usItemId: '6000191275106', name: 'Marcangelo Pork Kabobs, 8 kabobs, 640 g', brand: 'Marcangelo',
  priceInfo: { currentPrice: { price: 9.97 }, wasPrice: { price: 13.97 }, unitPrice: { priceString: '$1.56/100g' } },
  category: { path: [{ name: 'Root' }, { name: 'Grocery' }, { name: 'Meat, Seafood & Alternatives' }, { name: 'Kebabs' }] },
  canonicalUrl: '/en/ip/x/6000191275106?athAsset=abc', availabilityStatus: 'IN_STOCK' });
assert.strictEqual(wm1.price, 9.97); assert.strictEqual(wm1.was, 13.97); assert.strictEqual(wm1.size, 640); assert.strictEqual(wm1.unit, 'g');
assert.strictEqual(wm1.cat, 'Meat, Seafood & Alternatives'); assert.strictEqual(wm1.url, 'https://www.walmart.ca/en/ip/x/6000191275106');
const wm2 = P.walmartItem({ usItemId: '6HPRZK7OEXKZ', name: 'Tim Hortons Beef Soup, 540 ml Can', price: 2.24,
  priceInfo: { linePrice: '$2.24', wasPrice: '$3.34', unitPrice: '41.0 ¢/100ml' }, category: { categoryPath: 'Root/Grocery/Pantry Food/Soups' } });
assert.strictEqual(wm2.price, 2.24); assert.strictEqual(wm2.was, 3.34); assert.strictEqual(wm2.size, 540); assert.strictEqual(wm2.unit, 'ml');
assert.strictEqual(wm2.cat, 'Pantry Food');
assert.strictEqual(P.walmartItem({ usItemId: '1', name: 'Gone', price: 3, isOutOfStock: true }), null);
const wm3 = P.walmartItem({ usItemId: '2', name: 'Bananas', price: 1.5, salesUnitType: 'WEIGHT', priceInfo: { unitPrice: '$1.50/lb' } });
assert.ok(wm3.variable); assert.strictEqual(wm3.unit, 'lb');

// real Superstore card texts
ct = P.parseCardText('Pure Basmati Rice\nsale:\n$15.99\n, formerly:\nLimit 4, after limit $18.99');
assert.strictEqual(ct.price, 15.99); assert.strictEqual(ct.was, 18.99);
const pb = P.domItem('superstore', { id: '1_EA', name: 'Smooth Peanut Butter', text: 'Prepared in Canada\n\n$14.99\n\nKraft\n\nSmooth Peanut Butter\n\n2 kg, $0.75/100g' });
assert.strictEqual(pb.price, 14.99); assert.strictEqual(pb.size, 2); assert.strictEqual(pb.unit, 'kg');
const menu = 'Super Value Picks\n\nCollect & Save!\n\nAd Match\n\nNew Arrivals\n\nValue meals\n\nSuper Coupons\n\nFresh Promise\n\nHome & More\n\n$5 and under\n\nClub Size';
assert.strictEqual(P.domItem('superstore', { id: '2_EA', name: 'Super Value Picks', text: menu }), null);

// same product listed under two ids collapses to one; different price or size stays
const dd = P.dedupe([
  { id: 'superstore:1_EA', store: 'superstore', name: 'Corned Beef', brand: 'Grace', size: 340, unit: 'g', price: 6.5, src: 'dom' },
  { id: 'superstore:2_EA', store: 'superstore', name: 'Corned beef ', brand: 'Grace', size: 340, unit: 'g', price: 6.5, img: 'x.jpg' },
  { id: 'superstore:3_C06', store: 'superstore', name: 'Cola', brand: 'Pepsi', size: 2130, unit: 'ml', price: 3.49 },
  { id: 'superstore:4_C12', store: 'superstore', name: 'Cola', brand: 'Pepsi', size: 2130, unit: 'ml', price: 7.99 },
  { id: 'walmart:5', store: 'walmart', name: 'Corned Beef', brand: 'Grace', size: 340, unit: 'g', price: 6.5 },
]);
assert.strictEqual(dd.length, 4);
assert.strictEqual(dd.filter(function (i) { return i.store === 'superstore' && i.name.trim().toLowerCase() === 'corned beef'; })[0].id, 'superstore:2_EA');

// Walmart prices that arrive in cents, and single pieces listed with their weight
const wc1 = P.walmartItem({ usItemId: '6000191272055', name: 'Great Value Large 12 Eggs', price: 422, priceInfo: { linePrice: '$4.22', wasPrice: '$4.99' } });
assert.strictEqual(wc1.price, 4.22); assert.strictEqual(wc1.was, 4.99);
const wc2 = P.walmartItem({ usItemId: '10052944', name: 'Redpath Dark Brown Sugar 1 kg', price: 277, priceInfo: {} });
assert.strictEqual(wc2.price, 2.77);
const wc3 = P.walmartItem({ usItemId: '6000191272', name: 'Tomato, Roma, Sold in singles, 0.10 - 0.14 KG', price: 0.51, priceInfo: {} });
assert.strictEqual(wc3.price, 0.51); assert.strictEqual(wc3.unit, 'each'); assert.strictEqual(wc3.size, 1); assert.ok(!wc3.variable);
const wc4 = P.walmartItem({ usItemId: 'X1', name: 'Rice 4 kg', price: 12, priceInfo: { currentPrice: { price: 12, priceString: '$12.00' } } });
assert.strictEqual(wc4.price, 12);
const old1 = P.repairOld({ id: 'walmart:6000191272055', store: 'walmart', name: 'Tomato, Roma, Sold in singles, 0.10 - 0.14 KG', price: 51, size: 0.14, unit: 'kg' });
assert.strictEqual(old1.price, 0.51); assert.strictEqual(old1.unit, 'each'); assert.strictEqual(old1.size, 1);
assert.strictEqual(P.repairOld({ id: 'walmart:10052944', store: 'walmart', name: 'Eggs', price: 422 }).price, 4.22);
assert.strictEqual(P.repairOld({ id: 'walmart:4AJB6KXCDI', store: 'walmart', name: 'Ramen Sauce', price: 15 }).price, 15);
assert.strictEqual(P.repairOld({ id: 'walmart:10052944', store: 'walmart', name: 'Eggs', price: 4.22, pv: 2 }).price, 4.22);
assert.strictEqual(P.repairOld({ id: 'walmart:1', store: 'walmart', name: 'X', price: 5, src: 'dom' }).price, 5);
assert.strictEqual(P.repairOld({ id: 'superstore:1_EA', store: 'superstore', name: 'X', price: 500 }).price, 500);

// real Superstore category-tile shapes
const tomato = P.loblawItem('superstore', { productId: '20143381001_KG', title: 'Roma Tomatoes', packageSizing: '$7.69/1kg $3.49/1lb',
  pricing: { price: '0.92', wasPrice: null, displayPrice: 'about $0.92' }, pricingUnits: { type: 'SOLD_BY_EACH_PRICED_BY_WEIGHT', unit: 'ea', weighted: false }, textBadge: '' });
assert.strictEqual(tomato.price, 0.92); assert.strictEqual(tomato.unit, 'each'); assert.strictEqual(tomato.size, 1); assert.ok(!tomato.variable);
const mini = P.loblawItem('superstore', { productId: '21247300001_EA', title: 'Yellow Mini Potatoes', packageSizing: '0.68 kg, $0.51/100g',
  pricing: { price: '3.50', wasPrice: null }, pricingUnits: { type: 'SOLD_BY_EACH', unit: 'ea', weighted: false }, textBadge: '' });
assert.strictEqual(mini.price, 3.5); assert.strictEqual(mini.size, 0.68); assert.strictEqual(mini.unit, 'kg'); assert.ok(!mini.variable);
const beef = P.loblawItem('superstore', { productId: '1_KG', title: 'Lean Ground Beef', packageSizing: '$33.66/1kg $15.27/1lb',
  pricing: { price: '33.66' }, pricingUnits: { type: 'SOLD_BY_WEIGHT', unit: 'kg', weighted: true }, textBadge: '' });
assert.ok(beef.variable); assert.strictEqual(beef.unit, 'kg'); assert.strictEqual(beef.price, 33.66);
assert.strictEqual(P.loblawItem('superstore', { productId: '2_KG', title: 'Red Peppers', pricing: { price: '2.01' }, textBadge: 'out-of-stock' }), null);

// on-screen weight-priced card: "about $3.76" with a $/kg shelf rate is ONE piece, not a kilo
const cf = P.domItem('superstore', { id: '20143564_KG', name: 'Cauliflower Florets', text: 'about $3.76\n\nCauliflower Florets\n\n$9.90/1kg $4.49/1lb' });
assert.strictEqual(cf.price, 3.76); assert.strictEqual(cf.unit, 'each'); assert.strictEqual(cf.size, 1); assert.ok(!cf.variable);
const gb = P.domItem('superstore', { id: '1_KG', name: 'Lean Ground Beef', text: '$33.66/1kg $15.27/1lb\n\nLean Ground Beef' });
assert.ok(gb.variable); assert.strictEqual(gb.unit, 'kg');

assert.strictEqual(P.repairOld({ id: 'walmart:10035490', store: 'walmart', name: 'Taco Sauce', price: 397, pv: 2 }).price, 3.97);
assert.strictEqual(P.repairOld({ id: 'walmart:9', store: 'walmart', name: 'Big case', price: 12000, pv: 2 }).price, 12000);

assert.strictEqual(P.cleanName('Click here to go to Dare Real Fruit Gummies 300 g product detail page'), 'Dare Real Fruit Gummies 300 g');
assert.strictEqual(P.repairOld({ id: 'freshco:1', store: 'freshco', name: 'Click here to go to Mangoes Red 3 Count product detail page', price: 3 }).name, 'Mangoes Red 3 Count');

console.log('all parse tests passed');
