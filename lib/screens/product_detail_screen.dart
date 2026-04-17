import 'package:flutter/material.dart';
import '../constants/category_map.dart';
import '../db/db_helper.dart';
import '../models/product.dart';
import '../models/transaction_entry.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final String category;

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.category,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final DbHelper _dbHelper = DbHelper();
  bool _isSaving = false;
  int _currentStock = 0;
  double _price = 0.0;
  bool _isLoadingData = true;
  late TextEditingController _actualCountController;

  @override
  void initState() {
    super.initState();
    _actualCountController = TextEditingController();
    _loadProductData();
  }

  @override
  void dispose() {
    _actualCountController.dispose();
    super.dispose();
  }

  Future<void> _loadProductData() async {
    final dbFileName = categoryDbMap[widget.category] ?? '';
    debugPrint('[PRODUCT_DETAIL] Loading data for product: ${widget.product.displayName}');
    debugPrint('[PRODUCT_DETAIL] product.id=${widget.product.id}');
    debugPrint('[PRODUCT_DETAIL] product.innerDiameter=${widget.product.innerDiameter}');
    debugPrint('[PRODUCT_DETAIL] dbFileName=$dbFileName');
    
    final stock = await _dbHelper.getCurrentStock(dbFileName, widget.product.id);
    final price = await _dbHelper.getProductPrice(dbFileName, widget.product.id);
    
    debugPrint('[PRODUCT_DETAIL] Stock result: $stock, Price result: $price');
    
    if (mounted) {
      setState(() {
        _currentStock = stock;
        _price = price;
        _isLoadingData = false;
      });
    }
  }

  Color _stockColor(int stock) {
    if (stock <= 0) return const Color(0xFFE53935); // red = out of stock
    if (stock <= 5) return const Color(0xFFFFA726); // orange = low
    return const Color(0xFF66BB6A); // green = good
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFE53935), size: 28),
            SizedBox(width: 10),
            Text(
              'Reset Stock?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will set the stock count to 0 and save an Actual transaction. This cannot be undone.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFE53935).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFE53935), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Current stock will be lost.',
                      style: TextStyle(color: Color(0xFFE53935), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Reset to 0'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _saveTransaction(0, false);
    }
  }

  Future<void> _saveTransaction(int quantity, bool isActual) async {
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Determine notes field: "ACTUAL" or "RESET" — MUST BE UPPERCASE
      final String notes = !isActual ? 'RESET' : 'ACTUAL';
      debugPrint('[ACTION] Setting notes to: $notes (isActual=$isActual)');

      // Create transaction entry matching desktop app schema
      // For ACTUAL/RESET: name column contains "ACTUAL" or "RESET", product is reconstructed from type/id_size/od_size/th_size/brand
      final entry = TransactionEntry(
        date: dateStr,
        productType: widget.product.type, // e.g., "TC"
        idSize: widget.product.innerDiameter.toString(),
        odSize: widget.product.outerDiameter.toString(),
        thSize: widget.product.thickness.toString(),
        brand: widget.product.brand,
        productName: notes, // "ACTUAL" or "RESET" goes in name column
        quantity: quantity,
        price: 0.0,
        isRestock: 2, // 2 = ACTUAL (green) transaction type
        notes: notes,
      );
      debugPrint('[ACTION] Created entry with notes: ${entry.notes}');

      final dbFileName = categoryDbMap[widget.category] ?? '';
      final saved = await _dbHelper.saveTransaction(dbFileName, entry);

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isActual
                ? 'Stock updated to $quantity'
                : 'Stock reset to 0'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );

        // Reload data
        await _loadProductData();
        _actualCountController.clear();

        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Transaction Saved',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Do you want to export the updated database now?',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Later',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _exportDatabase();
                  },
                  child: const Text('Export Now'),
                ),
              ],
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save transaction'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ERROR] _saveTransaction: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final dbFileName = categoryDbMap[widget.category];
      if (dbFileName == null) return;
      await _dbHelper.exportDb(dbFileName);
      debugPrint('[DB] File exported: $dbFileName');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database exported successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ERROR] exportDb: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Detail'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: _isLoadingData
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFFE53935)),
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product header (simplified)
                    Text(
                      widget.product.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Stock Count Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _stockColor(_currentStock),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Current Stock',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_currentStock',
                            style: TextStyle(
                              color: _stockColor(_currentStock),
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'pieces',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Price Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 20,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Price (SRP)',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _price > 0
                                ? '₱ ${_price.toStringAsFixed(2)}'
                                : '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'per piece',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actual Count Input
                    TextField(
                      controller: _actualCountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter actual stock count',
                        hintStyle: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[800]!,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE53935),
                            width: 2,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey[800]!,
                            width: 1,
                          ),
                        ),
                        suffixIcon: _actualCountController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Color(0xFFE53935),
                                ),
                                onPressed: () {
                                  _actualCountController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () {
                                if (_actualCountController.text.isEmpty ||
                                    int.tryParse(
                                          _actualCountController.text,
                                        ) ==
                                        null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter a valid number',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final quantity = int.parse(
                                  _actualCountController.text,
                                );
                                _saveTransaction(quantity, true);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[700],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'UPDATE ACTUAL COUNT',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Reset Stock Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : _confirmReset,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE53935),
                          side: const BorderSide(
                            color: Color(0xFFE53935),
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          disabledForegroundColor: Colors.grey[700],
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(0xFFE53935),
                                  ),
                                ),
                              )
                            : const Text(
                                'RESET STOCK',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
