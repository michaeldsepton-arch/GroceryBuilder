import 'units.dart';

class Store {
  Store({
    required this.id,
    required this.name,
    required this.color,
    this.location = '',
    this.hasOnline = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int color;
  final String location;
  final bool hasOnline;
  final int sortOrder;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'location': location,
        'has_online': hasOnline ? 1 : 0,
        'sort_order': sortOrder,
      };

  factory Store.fromMap(Map<String, Object?> m) => Store(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as int,
        location: (m['location'] as String?) ?? '',
        hasOnline: (m['has_online'] as int? ?? 1) == 1,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );
}

/// A product at a store. [price] is the shelf price for [sizeValue] [sizeUnit].
/// When [variable] is true the item is sold by weight (produce, meat): the
/// price applies to the size (e.g. $5.99 per 1 lb) and the cart quantity is a
/// weight rather than a count.
class Item {
  Item({
    required this.id,
    required this.storeId,
    required this.name,
    required this.price,
    this.brand = '',
    this.imageUrl,
    this.photoPath,
    this.wasPrice,
    this.sizeValue = 1,
    this.sizeUnit = Unit.each,
    this.variable = false,
    this.taxable = false,
    this.category = '',
    this.url,
    this.custom = false,
    this.updated,
    this.favourite = false,
    this.aisle = '',
    this.spot = '',
    this.note = '',
    this.timesBought = 0,
  });

  final String id;
  final String storeId;
  final String name;
  final String brand;
  final String? imageUrl;
  final String? photoPath;
  final double price;
  final double? wasPrice;
  final double sizeValue;
  final Unit sizeUnit;
  final bool variable;
  final bool taxable;
  final String category;
  final String? url;
  final bool custom;
  final String? updated;

  // Personal metadata (joined from item_meta).
  final bool favourite;
  final String aisle;
  final String spot;
  final String note;
  final int timesBought;

  double get _baseAmount => sizeValue * sizeUnit.baseFactor;

  UnitPrice get unitPrice =>
      UnitPrice(sizeUnit.kind, _baseAmount <= 0 ? price : price / _baseAmount);

  bool get onSale => wasPrice != null && wasPrice! > price;

  /// Whole-number percent off the regular price (0 when not on sale).
  int get discountPct => onSale ? ((1 - price / wasPrice!) * 100).round() : 0;

  /// Cost of [qty] in the cart. For variable items qty is in grams.
  double lineCost(double qty) =>
      variable ? unitPrice.perBase * qty : price * qty;

  String get sizeText => variable
      ? 'per ${sizeBoth(sizeValue, sizeUnit)}'
      : (sizeUnit == Unit.each && sizeValue == 1
          ? ''
          : sizeBoth(sizeValue, sizeUnit));

  Item withMeta(Map<String, Object?>? m) => Item(
        id: id,
        storeId: storeId,
        name: name,
        brand: brand,
        imageUrl: imageUrl,
        photoPath: photoPath,
        price: price,
        wasPrice: wasPrice,
        sizeValue: sizeValue,
        sizeUnit: sizeUnit,
        variable: variable,
        taxable: taxable,
        category: category,
        url: url,
        custom: custom,
        updated: updated,
        favourite: (m?['favourite'] as int? ?? 0) == 1,
        aisle: (m?['aisle'] as String?) ?? '',
        spot: (m?['spot'] as String?) ?? '',
        note: (m?['note'] as String?) ?? '',
        timesBought: (m?['times_bought'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'store_id': storeId,
        'name': name,
        'brand': brand,
        'image_url': imageUrl,
        'photo_path': photoPath,
        'price': price,
        'was_price': wasPrice,
        'size_value': sizeValue,
        'size_unit': sizeUnit.name,
        'variable': variable ? 1 : 0,
        'taxable': taxable ? 1 : 0,
        'category': category,
        'url': url,
        'custom': custom ? 1 : 0,
        'updated': updated,
      };

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        name: m['name'] as String,
        brand: (m['brand'] as String?) ?? '',
        imageUrl: m['image_url'] as String?,
        photoPath: m['photo_path'] as String?,
        price: (m['price'] as num).toDouble(),
        wasPrice: (m['was_price'] as num?)?.toDouble(),
        sizeValue: (m['size_value'] as num?)?.toDouble() ?? 1,
        sizeUnit: Unit.parse(m['size_unit'] as String?),
        variable: (m['variable'] as int? ?? 0) == 1,
        taxable: (m['taxable'] as int? ?? 0) == 1,
        category: (m['category'] as String?) ?? '',
        url: m['url'] as String?,
        custom: (m['custom'] as int? ?? 0) == 1,
        updated: m['updated'] as String?,
        favourite: (m['favourite'] as int? ?? 0) == 1,
        aisle: (m['aisle'] as String?) ?? '',
        spot: (m['spot'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
        timesBought: (m['times_bought'] as int?) ?? 0,
      );
}

class CartLine {
  CartLine(this.item, this.qty, this.got);
  final Item item;

  /// Count for fixed items, grams for variable (by-weight) items.
  final double qty;
  final bool got;

  double get cost => item.lineCost(qty);
  double get tax => item.taxable ? cost * gstRate : 0;
}

const double gstRate = 0.05;

class Trip {
  Trip(this.id, this.date, this.subtotal, this.tax, this.itemCount);
  final int id;
  final DateTime date;
  final double subtotal;
  final double tax;
  final int itemCount;
  double get total => subtotal + tax;
}

enum AlertKind { drop, sale }

/// A favourite/often-bought item whose price fell, or that is on sale now.
class PriceAlert {
  PriceAlert(this.item, this.oldPrice, this.newPrice, this.when, this.kind);
  final Item item;
  final double oldPrice;
  final double newPrice;
  final DateTime when;
  final AlertKind kind;

  double get saved => oldPrice - newPrice;
  int get pct => oldPrice <= 0 ? 0 : ((saved / oldPrice) * 100).round();
}

class PricePoint {
  PricePoint(this.price, this.wasPrice, this.seen);
  final double price;
  final double? wasPrice;
  final DateTime seen;
}
