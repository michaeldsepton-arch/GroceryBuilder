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

console.log('all parse tests passed');
