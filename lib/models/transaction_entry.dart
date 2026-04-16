class TransactionEntry {
  final int? id;
  final String date; // YYYY-MM-DD format
  final String productType; // e.g., "TC", "SC" (from Product.type)
  final String idSize; // Inner diameter as string
  final String odSize; // Outer diameter as string
  final String thSize; // Thickness as string
  final String brand;
  final String productName; // Full product display name
  final int quantity; // Stock count for ACTUAL, or count for RESET (0)
  final double price; // Price/cost
  final int isRestock; // 0=SALE, 1=RESTOCK, 2=ACTUAL
  final String notes; // "ACTUAL" or "RESET" for actual count transactions

  TransactionEntry({
    this.id,
    required this.date,
    required this.productType,
    required this.idSize,
    required this.odSize,
    required this.thSize,
    required this.brand,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.isRestock,
    required this.notes,
  }) {
    // Validate notes is only "ACTUAL" or "RESET"
    if (notes != 'ACTUAL' && notes != 'RESET') {
      throw ArgumentError('Notes must be "ACTUAL" or "RESET", got: $notes');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'type': productType,
      'id_size': idSize,
      'od_size': odSize,
      'th_size': thSize,
      'brand': brand,
      'name': productName,
      'quantity': quantity,
      'price': price,
      'is_restock': isRestock,
      'notes': notes,
    };
  }
}
