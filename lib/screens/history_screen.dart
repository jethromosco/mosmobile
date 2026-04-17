import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/category_map.dart';
import '../db/db_helper.dart';

class HistoryScreen extends StatefulWidget {
  final String category;

  const HistoryScreen({
    super.key,
    required this.category,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _historyEntries = [];
  bool _isLoading = true;

  /// Format date from YYYY-MM-DD or M/D/YY to MM/DD/YY format
  String _formatDate(String dateStr) {
    try {
      // Try parsing as YYYY-MM-DD format (standard SQL date)
      if (dateStr.contains('-')) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final month = parts[1].padLeft(2, '0');
          final day = parts[2].padLeft(2, '0');
          final year = parts[0].substring(2); // Get last 2 digits of year
          return '$month/$day/$year';
        }
      }
      
      // Try parsing as M/D/YY format (already partial)
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          final month = parts[0].padLeft(2, '0');
          final day = parts[1].padLeft(2, '0');
          final year = parts[2].length == 2 ? parts[2] : parts[2].substring(parts[2].length - 2);
          return '$month/$day/$year';
        }
      }
      
      return dateStr; // Return as-is if parsing fails
    } catch (e) {
      debugPrint('[HISTORY] Error formatting date "$dateStr": $e');
      return dateStr;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final dbFileName = categoryDbMap[widget.category] ?? '';
      if (dbFileName.isEmpty) {
        debugPrint('[HISTORY] Invalid category: ${widget.category}');
        return;
      }

      final db = await _dbHelper.openCategoryDb(dbFileName);
      if (db == null) {
        debugPrint('[HISTORY] Failed to open database');
        return;
      }

      // Get today's date in YYYY-MM-DD format for filtering
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      debugPrint('[HISTORY] Today\'s date: $todayStr');

      // Get the LATEST transaction for each unique product (type, id_size, od_size, th_size, brand)
      // ONLY from TODAY (current session) - ignore historical transactions from imported file
      final rows = await db.rawQuery(
        '''SELECT rowid, * FROM transactions 
           WHERE is_restock=2 
           AND date=?
           AND rowid IN (
             SELECT MAX(rowid) FROM transactions 
             WHERE is_restock=2 
             AND date=?
             GROUP BY type, id_size, od_size, th_size, brand
           )
           ORDER BY date DESC, rowid DESC''',
        [todayStr, todayStr],
      );

      debugPrint('[HISTORY] Loaded ${rows.length} unique products edited today');

      if (!mounted) return;

      setState(() {
        _historyEntries = rows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[ERROR] _loadHistory: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _copyToClipboard() async {
    try {
      final stringBuffer = StringBuffer();

      for (int i = 0; i < _historyEntries.length; i++) {
        final entry = _historyEntries[i];
        final date = _formatDate(entry['date'] ?? '');
        final type = entry['type'] ?? '';
        final idSize = entry['id_size'] ?? '';
        final odSize = entry['od_size'] ?? '';
        final thSize = entry['th_size'] ?? '';
        final brand = entry['brand'] ?? '';
        final name = entry['name'] ?? '';
        final quantity = entry['quantity'] ?? 0;

        // Reconstruct product name
        final productName = '$type $idSize-$odSize-$thSize $brand';

        // Format: "Product Name\nDate | ACTION | Quantity\n\n"
        stringBuffer.writeln(productName);
        stringBuffer.writeln('$date | $name | $quantity');
        
        // Add blank line between entries (except after the last one)
        if (i < _historyEntries.length - 1) {
          stringBuffer.writeln();
        }
      }

      debugPrint('[HISTORY] Clipboard content:\n${stringBuffer.toString()}');

      await Clipboard.setData(ClipboardData(text: stringBuffer.toString()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('History copied to clipboard'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[ERROR] _copyToClipboard: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copy failed: $e'),
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
        title: Text('History — ${widget.category}'),
        centerTitle: true,
        actions: [
          if (_historyEntries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy All',
              onPressed: _copyToClipboard,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyEntries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Theme.of(context).disabledColor,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No history found',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historyEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _historyEntries[index];
                    final date = _formatDate(entry['date'] ?? '');
                    final type = entry['type'] ?? '';
                    final idSize = entry['id_size'] ?? '';
                    final odSize = entry['od_size'] ?? '';
                    final thSize = entry['th_size'] ?? '';
                    final brand = entry['brand'] ?? '';
                    final name = entry['name'] ?? '';
                    final quantity = entry['quantity'] ?? 0;

                    // Reconstruct product name
                    // Reconstruct product name
                    final productName = '$type $idSize-$odSize-$thSize $brand';

                    // Determine if ACTUAL or RESET and get appropriate color
                    final isActual = name == 'ACTUAL';
                    final accentColor = isActual ? const Color(0xFF66BB6A) : const Color(0xFFE53935);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  date,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.2),
                                    border: Border.all(color: accentColor, width: 1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$name | $quantity',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
