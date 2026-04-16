import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../models/product.dart';
import '../models/transaction_entry.dart';

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  final Map<String, Database?> _databases = {};

  DbHelper._internal();

  factory DbHelper() {
    return _instance;
  }

  /// Opens a specific category's .db from internal app storage
  Future<Database?> openCategoryDb(String dbFileName) async {
    if (kIsWeb) return null;
    try {
      if (_databases.containsKey(dbFileName) && _databases[dbFileName] != null) {
        return _databases[dbFileName];
      }

      final dbPath = await getDbPath(dbFileName);
      debugPrint('[DB] Opening DB at: $dbPath');
      final db = await openDatabase(dbPath, readOnly: false);
      _databases[dbFileName] = db;
      debugPrint('[DB] File opened: $dbFileName');
      return db;
    } catch (e) {
      debugPrint('[ERROR] openCategoryDb: $e');
      return null;
    }
  }

  /// Returns true if the .db file exists in internal storage
  Future<bool> dbExists(String dbFileName) async {
    if (kIsWeb) return false;
    try {
      final dbPath = await getDbPath(dbFileName);
      final exists = await File(dbPath).exists();
      debugPrint('[DB] dbExists($dbFileName): $exists at $dbPath');
      return exists;
    } catch (e) {
      debugPrint('[ERROR] dbExists: $e');
      return false;
    }
  }

  /// Copies an imported .db file from phone storage into app internal storage
  /// Handles both real file paths and Android content URIs from file_picker
  Future<bool> importDb(String sourcePath, String dbFileName) async {
    if (kIsWeb) {
      debugPrint('[DB] importDb skipped on web');
      return false;
    }
    try {
      debugPrint('[DB] Import started: $sourcePath → $dbFileName');

      // Get destination path in app internal storage
      final appDir = await getApplicationDocumentsDirectory();
      final destPath = path.join(appDir.path, dbFileName);

      debugPrint('[DB] Destination path: $destPath');

      Uint8List? fileBytes;

      // Method 1: Try reading as content URI using Flutter's asset channel
      // This is required for Android content:// URIs from file picker
      try {
        // Try direct File read first (works if it's a real path)
        final sourceFile = File(sourcePath);
        if (await sourceFile.exists()) {
          fileBytes = await sourceFile.readAsBytes();
          debugPrint('[DB] Read via direct File: ${fileBytes.length} bytes');
        }
      } catch (e) {
        debugPrint('[DB] Direct file read failed: $e — trying content URI method');
      }

      // Method 2: Use content URI via platform channel if direct read failed
      if (fileBytes == null || fileBytes.isEmpty) {
        try {
          const channel = MethodChannel('mosco_mobile/file_reader');
          final bytes = await channel.invokeMethod<Uint8List>('readFile', {'uri': sourcePath});
          if (bytes != null && bytes.isNotEmpty) {
            fileBytes = bytes;
            debugPrint('[DB] Read via platform channel: ${fileBytes.length} bytes');
          }
        } catch (e) {
          debugPrint('[DB] Platform channel failed: $e');
        }
      }

      // Method 3: Use sqflite getDatabasesPath as fallback destination
      if (fileBytes == null || fileBytes.isEmpty) {
        debugPrint('[ERROR] Could not read source file bytes from: $sourcePath');
        return false;
      }

      // Verify it's a valid SQLite file (starts with SQLite magic bytes)
      if (fileBytes.length < 16) {
        debugPrint('[ERROR] File too small to be a valid SQLite database');
        return false;
      }

      final magic = String.fromCharCodes(fileBytes.sublist(0, 6));
      debugPrint('[DB] File magic bytes: $magic');
      if (!magic.startsWith('SQLite')) {
        debugPrint('[ERROR] File does not appear to be a SQLite database');
        // Continue anyway — some SQLite files have different headers
      }

      // Write bytes to destination
      final destFile = File(destPath);
      await destFile.writeAsBytes(fileBytes, flush: true);

      // Verify write succeeded
      final written = await destFile.length();
      debugPrint('[DB] Written: $written bytes to $destPath');

      if (written == 0) {
        debugPrint('[ERROR] Written file is empty!');
        return false;
      }

      debugPrint('[DB] Import successful: $dbFileName ($written bytes)');
      return true;

    } catch (e) {
      debugPrint('[ERROR] importDb: $e');
      return false;
    }
  }

  /// Returns the full local path of a stored .db file
  Future<String> getDbPath(String dbFileName) async {
    if (kIsWeb) return '';
    try {
      final appDir = await getApplicationDocumentsDirectory();
      return path.join(appDir.path, dbFileName);
    } catch (e) {
      debugPrint('[ERROR] getDbPath: $e');
      return '';
    }
  }

  /// Searches products by innerDiameter, outerDiameter, thickness
  /// Searches products by innerDiameter, outerDiameter, thickness
  /// Dynamically discovers table and column names from the actual database
  Future<List<Product>> searchProducts(String dbFileName, String rawInput) async {
    if (kIsWeb) return [];
    try {
      final regExp = RegExp(r'\d+(\.\d+)?');
      final matches = regExp.allMatches(rawInput);
      final nums = matches.map((m) => double.parse(m.group(0)!)).toList();

      debugPrint('[SEARCH] Raw input: "$rawInput"');
      debugPrint('[SEARCH] Extracted numbers: $nums');

      if (nums.length < 3) {
        debugPrint('[SEARCH] Need 3 numbers, got ${nums.length}');
        return [];
      }

      nums.sort();
      final thk = nums[0];
      final id = nums[1];
      final od = nums[2];

      debugPrint('[SEARCH] THK=$thk, ID=$id, OD=$od');

      final db = await openCategoryDb(dbFileName);
      if (db == null) return [];

      // Discover real table name
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
      );
      debugPrint('[DB] All tables: $tables');

      if (tables.isEmpty) {
        debugPrint('[ERROR] No tables found in database');
        return [];
      }

      // Try 'products' first, then fall back to first available table
      String tableName = 'products';
      final tableNames = tables.map((t) => t['name'] as String).toList();
      if (!tableNames.contains('products')) {
        tableName = tableNames.first;
        debugPrint('[DB] "products" table not found, using: $tableName');
      }

      // Discover real column names
      final cols = await db.rawQuery('PRAGMA table_info($tableName)');
      final colNames = cols.map((c) => c['name'] as String).toList();
      debugPrint('[DB] Columns in $tableName: $colNames');

      // Try to find ID/OD/THK columns with flexible name matching
      String? idCol = _findColumn(colNames, ['id', 'inner_diameter', 'inner', 'ID', 'bore']);
      String? odCol = _findColumn(colNames, ['od', 'outer_diameter', 'outer', 'OD']);
      String? thkCol = _findColumn(colNames, ['thk', 'thickness', 'th', 'THK', 'height', 'width']);

      debugPrint('[DB] Matched columns → ID: $idCol, OD: $odCol, THK: $thkCol');

      if (idCol == null || odCol == null || thkCol == null) {
        debugPrint('[ERROR] Could not find ID/OD/THK columns. Available: $colNames');
        return [];
      }

      // Try exact match first
      var results = await db.rawQuery(
        'SELECT * FROM $tableName WHERE CAST("$idCol" AS REAL)=? AND CAST("$odCol" AS REAL)=? AND CAST("$thkCol" AS REAL)=?',
        [id, od, thk],
      );

      debugPrint('[SEARCH] Exact match results: ${results.length}');

      // If no results, try with tolerance ±0.1
      if (results.isEmpty) {
        debugPrint('[SEARCH] Trying with ±0.1 tolerance...');
        results = await db.rawQuery(
          '''SELECT * FROM $tableName 
             WHERE ABS(CAST("$idCol" AS REAL) - ?) < 0.11 
             AND ABS(CAST("$odCol" AS REAL) - ?) < 0.11 
             AND ABS(CAST("$thkCol" AS REAL) - ?) < 0.11''',
          [id, od, thk],
        );
        debugPrint('[SEARCH] Tolerance match results: ${results.length}');
      }

      // Map results using actual column names
      return results.map((row) {
        debugPrint('[DB] Row: $row');
        return Product.fromMapDynamic(
          row,
          idCol: idCol,
          odCol: odCol,
          thkCol: thkCol,
        );
      }).toList();
    } catch (e) {
      debugPrint('[ERROR] searchProducts: $e');
      return [];
    }
  }

  /// Helper to find column name from list of candidates
  String? _findColumn(List<String> available, List<String> candidates) {
    for (final candidate in candidates) {
      if (available.any((col) => col.toLowerCase() == candidate.toLowerCase())) {
        return available.firstWhere(
          (col) => col.toLowerCase() == candidate.toLowerCase(),
        );
      }
    }
    return null;
  }

  /// Inserts a new ACTUAL transaction row
  /// Matches desktop app's exact schema with is_restock=2 for ACTUAL counts
  Future<bool> saveTransaction(String dbFileName, TransactionEntry entry) async {
    if (kIsWeb) {
      debugPrint('[DB] saveTransaction skipped on web');
      return false;
    }
    try {
      final db = await openCategoryDb(dbFileName);
      if (db == null) {
        debugPrint('[ERROR] saveTransaction: Failed to open database');
        return false;
      }

      final data = entry.toMap();
      debugPrint('[TRANSACTION] Full data map: $data');
      debugPrint('[TRANSACTION] Inserting: date=${entry.date}, type=${entry.productType}, quantity=${entry.quantity}, is_restock=${entry.isRestock}, notes=${entry.notes}');
      debugPrint('[TRANSACTION] Notes type: ${entry.notes.runtimeType}, value: "${entry.notes}"');

      // Try to insert with all columns (including notes)
      try {
        final rowId = await db.insert('transactions', data);
        debugPrint('[TRANSACTION] Saved: ${entry.productName} - qty=${entry.quantity}, is_restock=${entry.isRestock}, rowId=$rowId');
        debugPrint('[TRANSACTION] Inserted notes value: "${entry.notes}"');
        return true;
      } catch (insertError) {
        // If insert fails (likely due to missing notes column), try without notes
        debugPrint('[DB] First insert attempt failed: $insertError. Trying without notes column...');
        final dataWithoutNotes = {...data};
        dataWithoutNotes.remove('notes');
        
        try {
          await db.insert('transactions', dataWithoutNotes);
          debugPrint('[TRANSACTION] Saved (without notes): ${entry.productName} - qty=${entry.quantity}, is_restock=${entry.isRestock}');
          return true;
        } catch (retryError) {
          debugPrint('[ERROR] Both insert attempts failed. First: $insertError. Second: $retryError');
          rethrow;
        }
      }
    } catch (e) {
      debugPrint('[ERROR] saveTransaction: $e');
      return false;
    }
  }

  /// Exports (shares) the .db file using share_plus
  /// Exports the .db file with WAL checkpoint to ensure single self-contained file
  Future<void> exportDb(String dbFileName) async {
    if (kIsWeb) {
      debugPrint('[DB] Web platform detected - database operations not supported on web');
      return;
    }
    try {
      // Get database path
      final dbPath = await getDbPath(dbFileName);

      // Use cached database connection if available, otherwise open temporarily
      Database? db = _databases[dbFileName];
      bool shouldClose = false;
      
      if (db == null) {
        db = await openDatabase(dbPath);
        shouldClose = true;
      }

      debugPrint('[DB] Executing WAL checkpoint before export...');
      // Use rawQuery for PRAGMA statements (execute doesn't work for PRAGMA on Android)
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      debugPrint('[DB] WAL checkpoint completed');
      
      // Only close if we opened it temporarily
      if (shouldClose) {
        await db.close();
      }

      // Export the file via share
      await Share.shareXFiles(
        [XFile(dbPath)],
        subject: 'MOSCO Database Export',
      );
      debugPrint('[DB] File exported: $dbFileName');
    } catch (e) {
      debugPrint('[ERROR] exportDb: $e');
      rethrow;
    }
  }

  /// Get current stock count for a product from transactions
  Future<int> getCurrentStock(String dbFileName, int productId) async {
    if (kIsWeb) return 0;
    try {
      final db = await openCategoryDb(dbFileName);
      if (db == null) return 0;

      // Discover transactions table name
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();
      debugPrint('[DB] Tables for stock calc: $tableNames');

      // Try common transaction table names
      String? txTable = _findTableName(tableNames, [
        'transactions', 'transaction', 'stock_transactions', 'inventory_transactions'
      ]);

      if (txTable == null) {
        debugPrint('[ERROR] No transactions table found');
        return 0;
      }

      // Get all transactions for this product
      final rows = await db.rawQuery(
        'SELECT * FROM $txTable WHERE product_id=? ORDER BY rowid ASC',
        [productId],
      );

      debugPrint('[STOCK] Found ${rows.length} transactions for product $productId');

      int stock = 0;
      for (final row in rows) {
        debugPrint('[STOCK] Row: $row');
        final type = row['type']?.toString().toLowerCase() ?? '';
        final value = double.tryParse(row['value']?.toString() ?? '0') ?? 0;

        if (type == 'actual') {
          stock = value.toInt(); // sets exact stock
        } else if (type == 'restock' || type == 'fabrication') {
          stock += value.toInt(); // adds to stock
        } else if (type == 'sale') {
          stock -= value.toInt(); // subtracts from stock
        }
      }

      debugPrint('[STOCK] Calculated stock for product $productId: $stock');
      return stock < 0 ? 0 : stock;

    } catch (e) {
      debugPrint('[ERROR] getCurrentStock: $e');
      return 0;
    }
  }

  /// Get product price from database
  Future<double> getProductPrice(String dbFileName, int productId) async {
    if (kIsWeb) return 0.0;
    try {
      final db = await openCategoryDb(dbFileName);
      if (db == null) return 0.0;

      // Find products table
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();
      String tableName = tableNames.contains('products') ? 'products' : tableNames.first;

      // Get price column — try common names
      final cols = await db.rawQuery('PRAGMA table_info($tableName)');
      final colNames = cols.map((c) => c['name'] as String).toList();
      final priceCol = _findColumn(colNames, ['price', 'srp', 'selling_price', 'cost', 'unit_price']);

      if (priceCol == null) {
        debugPrint('[DB] No price column found in $tableName');
        return 0.0;
      }

      final rows = await db.rawQuery(
        'SELECT "$priceCol" FROM $tableName WHERE rowid=?',
        [productId],
      );

      if (rows.isEmpty) return 0.0;
      return double.tryParse(rows.first[priceCol]?.toString() ?? '0') ?? 0.0;

    } catch (e) {
      debugPrint('[ERROR] getProductPrice: $e');
      return 0.0;
    }
  }

  /// Helper to find table name
  String? _findTableName(List<String> available, List<String> candidates) {
    for (final candidate in candidates) {
      if (available.any((t) => t.toLowerCase() == candidate.toLowerCase())) {
        return available.firstWhere(
          (t) => t.toLowerCase() == candidate.toLowerCase(),
        );
      }
    }
    return null;
  }
}
