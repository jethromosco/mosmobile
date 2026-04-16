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
  late TextEditingController _actualCountController;
  bool _isSaving = false;
  int _currentStockCount = 0;

  @override
  void initState() {
    super.initState();
    _actualCountController = TextEditingController();
    _actualCountController.addListener(_onActualCountChanged);
  }

  @override
  void dispose() {
    _actualCountController.dispose();
    super.dispose();
  }

  void _onActualCountChanged() {
    // Reactive update as user types
    setState(() {});
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
        // Clear the actual count field after successful save
        if (isActual) {
          _actualCountController.clear();
        }
        // Optionally navigate back
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) Navigator.pop(context);
        });
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFFE53935);
    final surfaceColor = const Color(0xFF1A1A1A);
    final labelTextStyle = TextStyle(
      fontSize: 12,
      color: Colors.grey[400],
      fontWeight: FontWeight.w500,
    );
    final valueTextStyle = TextStyle(
      fontSize: 16,
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );
    final metricValueStyle = TextStyle(
      fontSize: 24,
      color: primaryColor,
      fontWeight: FontWeight.bold,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Detail'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: surfaceColor,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Header Card
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[800]!, width: 1),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.product.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.category} • ${widget.product.type}',
                      style: labelTextStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Stock & Price Section Header
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'PRODUCT INFO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Product Info Card
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[800]!, width: 1),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Type',
                          style: labelTextStyle,
                        ),
                        Text(
                          widget.product.type,
                          style: valueTextStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Brand',
                          style: labelTextStyle,
                        ),
                        Text(
                          widget.product.brand,
                          style: valueTextStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Actions Section Header
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'ACTIONS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Reset Stock Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          _saveTransaction(0, false);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
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
                            valueColor: AlwaysStoppedAnimation(Colors.white),
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
              const SizedBox(height: 16),

              // Actual Count Section Header
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'ACTUAL COUNT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Actual Count Input Field
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _actualCountController.text.isNotEmpty
                        ? primaryColor
                        : Colors.grey[800]!,
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _actualCountController,
                  keyboardType: TextInputType.number,
                  style: valueTextStyle,
                  decoration: InputDecoration(
                    hintText: 'Enter stock count',
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                    border: InputBorder.none,
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
              ),
              const SizedBox(height: 16),

              // Save Actual Count Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ||
                          _actualCountController.text.isEmpty ||
                          int.tryParse(_actualCountController.text) == null
                      ? null
                      : () {
                          final quantity =
                              int.parse(_actualCountController.text);
                          _saveTransaction(quantity, true);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
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
                            valueColor: AlwaysStoppedAnimation(Colors.white),
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
              const SizedBox(height: 24),

              // Product Specs Section
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'DIMENSIONS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[800]!, width: 1),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildSpecRow('Inner Diameter (ID)', '${widget.product.innerDiameter} mm'),
                    const Divider(height: 16, color: Colors.grey),
                    _buildSpecRow('Outer Diameter (OD)', '${widget.product.outerDiameter} mm'),
                    const Divider(height: 16, color: Colors.grey),
                    _buildSpecRow('Thickness (TH)', '${widget.product.thickness} mm'),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
