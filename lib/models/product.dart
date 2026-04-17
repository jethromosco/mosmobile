import 'package:flutter/foundation.dart';

class Product {
  final int id;
  final double innerDiameter;
  final double outerDiameter;
  final double thickness;
  final String type;
  final String brand;

  Product({
    required this.id,
    required this.innerDiameter,
    required this.outerDiameter,
    required this.thickness,
    required this.type,
    required this.brand,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    double parseNum(dynamic val) {
      if (val == null) return 0.0;
      if (val is double) return val;
      if (val is int) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }
    
    final rowId = map['rowid'] ?? map['_id'] ?? 0;
    debugPrint('[PRODUCT] fromMap: rowid=$rowId, map keys=${map.keys.toList()}');
    
    return Product(
      id: rowId,
      innerDiameter: parseNum(map['id']),
      outerDiameter: parseNum(map['od']),
      thickness: parseNum(map['thk']),
      type: map['type']?.toString() ?? '',
      brand: map['brand']?.toString() ?? '',
    );
  }

  factory Product.fromMapDynamic(
    Map<String, dynamic> map, {
    required String idCol,
    required String odCol,
    required String thkCol,
  }) {
    double parseNum(dynamic val) {
      if (val == null) return 0.0;
      if (val is double) return val;
      if (val is int) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    // Use rowid as primary key to avoid conflict with 'id' dimension column
    final primaryKey = map['rowid'] ?? map['_id'] ?? map['pk'] ?? 0;

    return Product(
      id: primaryKey is int ? primaryKey : int.tryParse(primaryKey.toString()) ?? 0,
      innerDiameter: parseNum(map[idCol]),
      outerDiameter: parseNum(map[odCol]),
      thickness: parseNum(map[thkCol]),
      type: map['type']?.toString() ?? map['seal_type']?.toString() ?? '',
      brand: map['brand']?.toString() ?? map['manufacturer']?.toString() ?? '',
    );
  }

  /// Formats a dimension value by removing unnecessary .0 decimals
  String _formatDimension(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  String get displayName => '$type ${_formatDimension(innerDiameter)}-${_formatDimension(outerDiameter)}-${_formatDimension(thickness)} $brand';
}
