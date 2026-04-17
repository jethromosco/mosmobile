import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import '../constants/category_map.dart';
import '../db/db_helper.dart';
import '../models/product.dart';
import '../widgets/search_result_tile.dart';
import 'product_detail_screen.dart';
import 'diagnostic_screen.dart';
import 'history_screen.dart';

class SearchScreen extends StatefulWidget {
  final String category;
  final String unit;

  const SearchScreen({
    super.key,
    required this.category,
    required this.unit,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final DbHelper _dbHelper = DbHelper();
  final TextEditingController _searchController = TextEditingController();
  List<Product> _searchResults = [];
  bool _isLoading = false;
  bool _dbExists = false;
  bool _webMode = false;

  @override
  void initState() {
    super.initState();
    _checkDbExists();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkDbExists() async {
    if (kIsWeb) {
      setState(() {
        _webMode = true;
      });
      return;
    }
    final dbFileName = categoryDbMap[widget.category] ?? '';
    final exists = await _dbHelper.dbExists(dbFileName);
    setState(() {
      _dbExists = exists;
    });
  }

  void _onSearchChanged() {
    setState(() {}); // Rebuild to update clear button visibility
    _debounceSearch();
  }

  Future<void> _debounceSearch() async {
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    final input = _searchController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    final regExp = RegExp(r'\d+(\.\d+)?');
    final nums = regExp.allMatches(input).toList();
    if (nums.length < 3) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    await _performSearch(input);
  }

  Future<void> _performSearch(String rawInput) async {
    setState(() {
      _isLoading = true;
    });

    final dbFileName = categoryDbMap[widget.category] ?? '';
    final results = await _dbHelper.searchProducts(dbFileName, rawInput);

    if (!mounted) return;

    setState(() {
      _searchResults = results;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.category} — ${widget.unit}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(category: widget.category),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Diagnose DB',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiagnosticScreen(category: widget.category),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Import / Export',
            onPressed: _showImportExportMenu,
          ),
        ],
      ),
      body: _webMode
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storage,
                    size: 64,
                    color: Theme.of(context).disabledColor,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Database features require the Android app.\nTest the UI only in Chrome.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          : !_dbExists
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.storage,
                        size: 64,
                        color: Theme.of(context).disabledColor,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No database loaded.\nTap the import icon on the Home screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                )
          : Column(
              children: [
                // Modern Search Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g. 30-47-7 or TC 30 x 47 x 7 NOK',
                      hintStyle: const TextStyle(color: Color(0xFF777777)),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFFE53935),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: Color(0xFFE53935)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchResults = []);
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(
                          color: Color(0xFF2C2C2C),
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(
                          color: Color(0xFF2C2C2C),
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(
                          color: Color(0xFFE53935),
                          width: 2,
                        ),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFE53935),
                            ),
                          ),
                        )
                      : _searchResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _searchController.text.isEmpty
                                        ? Icons.search
                                        : Icons.inbox,
                                    size: 64,
                                    color: const Color(0xFF555555),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchController.text.isEmpty
                                        ? 'Enter search terms'
                                        : 'No products found.',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Color(0xFF888888),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    const SizedBox(height: 8),
                                  if (_searchController.text.isNotEmpty)
                                    const Text(
                                      'Try a different search term',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF666666),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 8),
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final product = _searchResults[index];
                                return SearchResultTile(
                                  code: '${product.type} ${product.innerDiameter.toStringAsFixed(1).replaceAll('.0', '')}-${product.outerDiameter.toStringAsFixed(1).replaceAll('.0', '')}-${product.thickness.toStringAsFixed(1).replaceAll('.0', '')}',
                                  brand: product.brand,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ProductDetailScreen(
                                          product: product,
                                          category: widget.category,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                )
              ],
            ),
    );
  }

  Future<void> _importDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: kIsWeb,
      );

      if (result == null) return;

      final pickedFile = result.files.single;

      // Validate .db extension
      if (!pickedFile.name.endsWith('.db')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a valid .db file.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Validate filename matches current category's db
      final expectedDbName = categoryDbMap[widget.category];
      if (expectedDbName != pickedFile.name) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Wrong database file. Expected: $expectedDbName'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      bool success = false;

      if (kIsWeb) {
        // Web: use bytes (testing only, no actual DB write on web)
        if (pickedFile.bytes != null) {
          debugPrint('[DB] File imported: ${pickedFile.name} for category: ${widget.category}');
          success = true; // Simulate success on web for UI testing
        }
      } else {
        // Android: use file path
        if (pickedFile.path != null && expectedDbName != null) {
          success = await _dbHelper.importDb(pickedFile.path!, expectedDbName);
          if (success) {
            debugPrint('[DB] File imported: ${pickedFile.name} for category: ${widget.category}');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                ? 'Database imported successfully!'
                : 'Import failed. Please try again.',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        if (success) {
          setState(() {
            _checkDbExists();
          });
        }
      }
    } catch (e) {
      debugPrint('[ERROR] _importDatabase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImportExportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Choose an action',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _importDatabase();
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Import Database'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _exportDatabase();
                  },
                  icon: const Icon(Icons.upload),
                  label: const Text('Export Database'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDatabase() async {
    try {
      final dbFileName = categoryDbMap[widget.category];
      if (dbFileName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid category.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _dbHelper.exportDb(dbFileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Database exported: $dbFileName'),
            backgroundColor: Colors.green,
          ),
        );

        // Show clear database confirmation dialog
        _showClearDbDialog(dbFileName);
      }
    } catch (e) {
      debugPrint('[ERROR] _exportDatabase: $e');
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

  Future<void> _showClearDbDialog(String dbFileName) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Clear imported database?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove the imported database from this device. Make sure your export was saved successfully before clearing.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Keep',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final cleared = await _dbHelper.clearDb(dbFileName);
      if (!mounted) return;
      
      if (cleared) {
        // Update UI state to show no database loaded
        setState(() {
          _dbExists = false;
          _searchResults = [];
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database cleared successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear database'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
