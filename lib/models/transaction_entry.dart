class TransactionEntry {
  final int? id;
  final String type;
  final double value;
  final String date;
  final int productId;

  TransactionEntry({
    this.id,
    this.type = 'Actual',
    required this.value,
    required this.date,
    required this.productId,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'value': value,
      'date': date,
      'product_id': productId,
    };
  }
}
