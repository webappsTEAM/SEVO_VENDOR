import '../../../core/utils/json_parsing.dart';

/// One product card of `GET /vendor/stock/` (Web `AdminStockManagementPage`).
class VendorStockProduct {
  const VendorStockProduct({
    required this.productId,
    required this.name,
    required this.state,
    this.image,
    this.vegetableGram,
    this.todayAvailableDisplay,
    this.price,
    this.mrp,
    this.offerPrice,
    this.reorderLevelDisplay,
    this.restockLevelDisplay,
    this.isClaimed = false,
    this.isMine,
  });

  factory VendorStockProduct.fromJson(Map<String, dynamic> json) =>
      VendorStockProduct(
        productId: parseInt(json['product_id']) ?? 0,
        name: parseString(json['name']) ?? 'Product',
        state: parseString(json['state']) ?? 'not_tracked',
        image: parseString(json['image']),
        vegetableGram: parseString(json['vegetable_gram']),
        todayAvailableDisplay: parseString(json['today_available_display']),
        price: parseString(json['price']),
        mrp: parseString(json['mrp']),
        offerPrice: parseString(json['offer_price']),
        reorderLevelDisplay: parseString(json['reorder_level_display']),
        restockLevelDisplay: parseString(json['restock_level_display']),
        isClaimed: json['is_claimed'] == true,
        isMine: json['is_mine'] is bool ? json['is_mine'] as bool : null,
      );

  final int productId;
  final String name;
  final String state;
  final String? image;
  final String? vegetableGram;
  final String? todayAvailableDisplay;
  final String? price;
  final String? mrp;
  final String? offerPrice;
  final String? reorderLevelDisplay;
  final String? restockLevelDisplay;
  final bool isClaimed;
  final bool? isMine;

  /// Web: `p.is_claimed && p.is_mine === false` → managed by another vendor.
  bool get locked => isClaimed && isMine == false;

  String get stateLabel => switch (state) {
    'in_stock' => 'In stock',
    'out_of_stock' => 'Out of stock',
    _ => 'Not tracked',
  };

  /// The MRP shown under the price only when an offer price exists (Web parity).
  String? get mrpNote => (offerPrice ?? '').isNotEmpty && (mrp ?? '').isNotEmpty
      ? 'MRP ₹$mrp'
      : null;

  /// Web patches the card in place with the `data` object returned by a write.
  VendorStockProduct merge(Map<String, dynamic> patch) {
    String? pick(String key, String? current) =>
        patch.containsKey(key) ? parseString(patch[key]) : current;
    return VendorStockProduct(
      productId: productId,
      name: pick('name', name) ?? name,
      state: pick('state', state) ?? state,
      image: pick('image', image),
      vegetableGram: pick('vegetable_gram', vegetableGram),
      todayAvailableDisplay: pick(
        'today_available_display',
        todayAvailableDisplay,
      ),
      price: pick('price', price),
      mrp: pick('mrp', mrp),
      offerPrice: pick('offer_price', offerPrice),
      reorderLevelDisplay: pick('reorder_level_display', reorderLevelDisplay),
      restockLevelDisplay: pick('restock_level_display', restockLevelDisplay),
      isClaimed: patch['is_claimed'] is bool
          ? patch['is_claimed'] as bool
          : isClaimed,
      isMine: patch['is_mine'] is bool ? patch['is_mine'] as bool : isMine,
    );
  }
}

class VendorStockHistoryRow {
  const VendorStockHistoryRow({
    required this.date,
    this.openingDisplay,
    this.restockedGrams,
    this.soldGrams,
    this.closingDisplay,
  });

  factory VendorStockHistoryRow.fromJson(Map<String, dynamic> json) =>
      VendorStockHistoryRow(
        date: parseString(json['date']) ?? '',
        openingDisplay: parseString(json['opening_display']),
        restockedGrams: parseDouble(json['restocked_grams']),
        soldGrams: parseDouble(json['sold_grams']),
        closingDisplay: parseString(json['closing_display']),
      );

  final String date;
  final String? openingDisplay;
  final double? restockedGrams;
  final double? soldGrams;
  final String? closingDisplay;

  static String _grams(double? g, String sign) {
    if (g == null || g == 0) return '—';
    final v = g == g.roundToDouble() ? g.toInt().toString() : g.toString();
    return '$sign${v}g';
  }

  String get restockedLabel => _grams(restockedGrams, '+');
  String get soldLabel => _grams(soldGrams, '-');
}

/// A successful stock write: the message to flash and the card patch, if any.
class VendorStockWriteResult {
  const VendorStockWriteResult({this.message, this.data});

  final String? message;
  final Map<String, dynamic>? data;
}
