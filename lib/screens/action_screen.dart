import 'package:flutter/material.dart';
import '../constants/category_map.dart';
import '../db/db_helper.dart';
import '../models/product.dart';
import '../models/transaction_entry.dart';

class ActionScreen extends StatefulWidget {
  final Product product;
  final String category;

  const ActionScreen({
    super.key,
    required this.product,
    required this.category,
  });

  @override
  State<ActionScreen> createState() => _ActionScreenState();
}

class _ActionScreenState extends State<ActionScreen> {
  final DbHelper _dbHelper = DbHelper();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Action'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.product.displayName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.category,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleResetStock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
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
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleActualCount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: const Color(0xFFE53935),
                    side: const BorderSide(color: Color(0xFFE53935), width: 2),
                    minimumSize: const Size(double.infinity, 60),
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
                          'ACTUAL COUNT',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  void _handleResetStock() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Stock'),
        content: Text('Set stock to 0 for ${widget.product.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _saveTransaction(0);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _handleActualCount() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actual Count'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Enter actual stock count:',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final input = controller.text.trim();
              if (input.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid number.')),
                );
                return;
              }

              try {
                final value = int.parse(input).toDouble();
                if (value < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a non-negative number.')),
                  );
                  return;
                }
                Navigator.pop(context);
                _saveTransaction(value);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid number.')),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTransaction(double value) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Determine notes field: "ACTUAL" or "RESET" — MUST BE UPPERCASE
      final String notes = value == 0 ? 'RESET' : 'ACTUAL';
      debugPrint('[ACTION] Setting notes to: $notes (value=$value)');

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
        quantity: value.toInt(), // Stock count for ACTUAL
        price: 0.0, // Price not used for ACTUAL transactions in desktop app
        isRestock: 2, // 2 = ACTUAL (green) transaction type
        notes: notes, // MUST be exactly "ACTUAL" or "RESET"
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
            content: Text('Stock set to ${value.toInt()}'),
            backgroundColor: Colors.green,
          ),
        );
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Transaction Saved'),
              content: const Text('Do you want to export the updated database now?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Later'),
                ),
                TextButton(
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
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save transaction. Check console for details.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('[ERROR] _saveTransaction: $e');
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportDatabase() async {
    try {
      final dbFileName = categoryDbMap[widget.category];
      if (dbFileName == null) return;
      await _dbHelper.exportDb(dbFileName);
      debugPrint('[DB] File exported: $dbFileName');
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
}
