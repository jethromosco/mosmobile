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

      // Assign dimensions using physical logic:
      // OD (outer diameter) = largest, ID (inner diameter) = smallest, TH (thickness) = middle
      nums.sort();
      final id = nums[0];      // Smallest = inner diameter
      final thk = nums[1];     // Middle = thickness
      final od = nums[2];      // Largest = outer diameter

      debugPrint('[SEARCH] ID=$id, OD=$od, THK=$thk');

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

      // Try exact match first — ALWAYS include rowid
      var results = await db.rawQuery(
        'SELECT rowid, * FROM $tableName WHERE CAST("$idCol" AS REAL)=? AND CAST("$odCol" AS REAL)=? AND CAST("$thkCol" AS REAL)=?',
        [id, od, thk],
      );

      debugPrint('[SEARCH] Exact match results: ${results.length}');

      // If no results, try with tolerance ±0.1
      if (results.isEmpty) {
        debugPrint('[SEARCH] Trying with ±0.1 tolerance...');
        results = await db.rawQuery(
          '''SELECT rowid, * FROM $tableName 
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
  Future<int> getCurrentStock(String dbFileName, int productRowId) async {
    if (kIsWeb) return 0;
    try {
      final db = await openCategoryDb(dbFileName);
      if (db == null) return 0;

      debugPrint('[STOCK] Getting stock for productRowId=$productRowId');

      // Get the product from products table FIRST
      final prodRows = await db.rawQuery(
        'SELECT rowid, * FROM products WHERE rowid=?',
        [productRowId],
      );

      if (prodRows.isEmpty) {
        debugPrint('[ERROR] Product not found with rowid=$productRowId');
        return 0;
      }

      final prod = prodRows.first;
      debugPrint('[STOCK] Product data: $prod');

      // Extract product fields from products table
      String? prodTypeCol = _findColumn(prod.keys.toList(), ['type', 'product_type', 'seal_type']);
      String? prodIdCol = _findColumn(prod.keys.toList(), ['id', 'inner_diameter', 'id_size']);
      String? prodOdCol = _findColumn(prod.keys.toList(), ['od', 'outer_diameter', 'od_size']);
      String? prodThkCol = _findColumn(prod.keys.toList(), ['th', 'thk', 'thickness', 'th_size']);
      String? prodBrandCol = _findColumn(prod.keys.toList(), ['brand', 'manufacturer']);

      if (prodTypeCol == null || prodIdCol == null || prodOdCol == null || prodThkCol == null || prodBrandCol == null) {
        debugPrint('[ERROR] Missing product columns. Available: ${prod.keys}');
        return 0;
      }

      final prodType = prod[prodTypeCol]?.toString().trim() ?? '';
      final prodId = prod[prodIdCol];
      final prodOd = prod[prodOdCol];
      final prodThk = prod[prodThkCol];
      final prodBrand = prod[prodBrandCol]?.toString().trim() ?? '';
      
      debugPrint('[STOCK] Product key: type=$prodType, id=$prodId, od=$prodOd, thk=$prodThk, brand=$prodBrand');

      // Find transactions table
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();
      
      String? txTable;
      for (final name in tableNames) {
        if (name.toLowerCase().contains('trans')) {
          txTable = name;
          break;
        }
      }
      if (txTable == null) {
        debugPrint('[ERROR] No transactions table. Tables: $tableNames');
        return 0;
      }

      debugPrint('[STOCK] Using transactions table: $txTable');

      // Get transaction table column names
      final cols = await db.rawQuery('PRAGMA table_info($txTable)');
      final colNames = cols.map((c) => c['name'] as String).toList();
      debugPrint('[STOCK] Transaction columns: $colNames');

      // Find the column names in transactions table
      String? typeCol = _findColumn(colNames, ['type', 'product_type', 'seal_type']);
      String? idCol = _findColumn(colNames, ['id_size', 'id', 'inner_diameter']);
      String? odCol = _findColumn(colNames, ['od_size', 'od', 'outer_diameter']);
      String? thkCol = _findColumn(colNames, ['th_size', 'th', 'thk', 'thickness']);
      String? brandCol = _findColumn(colNames, ['brand', 'manufacturer']);
      String? dateCol = _findColumn(colNames, ['date', 'transaction_date']);
      String? nameCol = _findColumn(colNames, ['name', 'description']);
      String? qtyCol = _findColumn(colNames, ['quantity', 'qty', 'value', 'amount']);
      String? priceCol = _findColumn(colNames, ['price', 'cost', 'amount']);
      String? isRestockCol = _findColumn(colNames, ['is_restock', 'type']);

      if (typeCol == null || idCol == null || odCol == null || thkCol == null || brandCol == null) {
        debugPrint('[ERROR] Missing product key columns in transactions. Available: $colNames');
        return 0;
      }

      if (dateCol == null || nameCol == null || qtyCol == null || priceCol == null || isRestockCol == null) {
        debugPrint('[ERROR] Missing transaction columns. Available: $colNames');
        return 0;
      }

      // Query transactions with ONLY the 6 columns needed, in the CORRECT ORDER
      // Desktop app format: date, name, quantity, price, is_restock, brand
      List<Map<String, dynamic>> rows = [];
      try {
        debugPrint('[STOCK] WHERE clause will use: type="$prodType" (${prodType.runtimeType}), id="$prodId" (${prodId.runtimeType}), od="$prodOd", thk="$prodThk", brand="$prodBrand" (${prodBrand.runtimeType})');
        
        rows = await db.rawQuery(
          'SELECT "$dateCol", "$nameCol", "$qtyCol", "$priceCol", "$isRestockCol", "$brandCol" FROM $txTable '
          'WHERE "$typeCol"=? AND "$idCol"=? AND "$odCol"=? AND "$thkCol"=? AND "$brandCol"=? '
          'ORDER BY "$dateCol" ASC, rowid ASC',
          [prodType, prodId, prodOd, prodThk, prodBrand],
        );
        debugPrint('[STOCK] Query succeeded, found ${rows.length} transactions');
      } catch (e) {
        debugPrint('[ERROR] Transaction query failed: $e');
        return 0;
      }

      if (rows.isEmpty) {
        debugPrint('[STOCK] ⚠️ NO TRANSACTIONS FOUND!');
        debugPrint('[STOCK] Looking for: type=$prodType, id=$prodId, od=$prodOd, thk=$prodThk, brand=$prodBrand');
        
        // Debug: Show ALL transactions to see what's actually in the database
        try {
          final countResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM $txTable');
          final totalCount = countResult.first['cnt'] ?? 0;
          debugPrint('[STOCK] Total transactions in $txTable: $totalCount');
          
          if (totalCount is int && totalCount > 0) {
            debugPrint('[STOCK] Sample transactions (first 10):');
            final allTx = await db.rawQuery('SELECT * FROM $txTable ORDER BY rowid DESC LIMIT 10');
            for (final tx in allTx) {
              debugPrint('[STOCK]   ${tx.toString()}');
            }
            
            // Show distinct product keys in transactions
            debugPrint('[STOCK] Distinct product keys in transactions:');
            final distinctKeys = await db.rawQuery(
              'SELECT DISTINCT "$typeCol", "$idCol", "$odCol", "$thkCol", "$brandCol" FROM $txTable LIMIT 5'
            );
            for (final key in distinctKeys) {
              debugPrint('[STOCK]   $key');
            }
          } else {
            debugPrint('[STOCK] ❌ TRANSACTIONS TABLE IS EMPTY - No transactions have been saved!');
          }
        } catch (e) {
          debugPrint('[STOCK] Could not read all transactions: $e');
        }
        
        return 0;
      }

      debugPrint('[STOCK] First transaction: ${rows.first}');
      debugPrint('[STOCK] Last transaction: ${rows.last}');

      // Process transactions chronologically using desktop app algorithm
      // Rows now contain: date, name, quantity, price, is_restock, brand (in that order)
      int stock = 0;
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        
        // Unpack in the CORRECT ORDER that desktop app expects
        // Index 0: date, 1: name, 2: quantity, 3: price, 4: is_restock, 5: brand
        final qtyVal = row[qtyCol];
        final typeVal = row[isRestockCol];
        
        // Convert is_restock to int (0=Sale, 1=Restock, 2=Actual)
        int typeInt = 0;
        if (typeVal is int) {
          typeInt = typeVal;
        } else if (typeVal is String) {
          if (typeVal.toLowerCase() == 'actual') {
            typeInt = 2;
          } else if (typeVal.toLowerCase() == 'sale') {
            typeInt = 0;
          } else if (typeVal.toLowerCase() == 'restock') {
            typeInt = 1;
          }
        } else {
          typeInt = int.tryParse(typeVal?.toString() ?? '0') ?? 0;
        }

        final qty = double.tryParse(qtyVal?.toString() ?? '0') ?? 0;

        debugPrint('[STOCK] [$i] is_restock=$typeInt, qty=$qty');

        // Apply desktop app algorithm
        if (typeInt == 2) {
          stock = qty.toInt(); // Actual: reset to exact value
          debugPrint('[STOCK] [$i] ACTUAL: reset stock to $stock');
        } else if (typeInt == 1) {
          stock += qty.toInt(); // Restock: add
          debugPrint('[STOCK] [$i] RESTOCK: +${qty.toInt()}, stock now $stock');
        } else if (typeInt == 0) {
          stock -= qty.toInt(); // Sale: subtract
          debugPrint('[STOCK] [$i] SALE: -${qty.toInt()}, stock now $stock');
        }
      }

      // Ensure non-negative
      final result = stock < 0 ? 0 : stock;
      debugPrint('[STOCK] ✓ Final running stock: $result');
      return result;

    } catch (e) {
      debugPrint('[ERROR] getCurrentStock exception: $e');
      return 0;
    }
  }

  /// Get product price from database
  /// Searches for price column using multiple candidate names
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
      debugPrint('[PRICE] Available tables: $tableNames');

      String tableName = tableNames.contains('products') ? 'products' : tableNames.first;
      debugPrint('[PRICE] Using table: $tableName');

      // Get price column — try common names from desktop app
      final cols = await db.rawQuery('PRAGMA table_info($tableName)');
      final colNames = cols.map((c) => c['name'] as String).toList();
      debugPrint('[PRICE] Available columns: $colNames');

      final priceCol = _findColumn(colNames,
        ['price', 'srp', 'selling_price', 'sell_price', 'cost', 'unit_price']);

      if (priceCol == null) {
        debugPrint('[ERROR] No price column found in $tableName. Columns: $colNames');
        return 0.0;
      }

      debugPrint('[PRICE] Using price column: $priceCol');

      final rows = await db.rawQuery(
        'SELECT "$priceCol" FROM $tableName WHERE rowid=?',
        [productId],
      );

      debugPrint('[PRICE] Query result for rowid=$productId: $rows');

      if (rows.isEmpty) {
        debugPrint('[PRICE] No product found for rowid=$productId');
        return 0.0;
      }

      final price = double.tryParse(rows.first[priceCol]?.toString() ?? '0') ?? 0.0;
      debugPrint('[PRICE] Parsed price: $price');
      return price;

    } catch (e) {
      debugPrint('[ERROR] getProductPrice: $e');
      return 0.0;
    }
  }

}
