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

console.log('all parse tests passed');
