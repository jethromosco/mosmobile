import 'dart:io';
import 'dart:typed_data';
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

  /// Inserts a new Actual transaction row
  Future<bool> saveTransaction(String dbFileName, TransactionEntry entry) async {
    if (kIsWeb) {
      debugPrint('[DB] Web platform detected - database operations not supported on web');
      return false;
    }
    try {
      final db = await openCategoryDb(dbFileName);
      if (db == null) {
        debugPrint('[ERROR] saveTransaction: Failed to open database');
        return false;
      }

      await db.insert('transactions', entry.toMap());
      debugPrint('[TRANSACTION] Saved: type=${entry.type}, value=${entry.value}, date=${entry.date}');
      return true;
    } catch (e) {
      debugPrint('[ERROR] saveTransaction: $e');
      return false;
    }
  }

  /// Exports (shares) the .db file using share_plus
  Future<void> exportDb(String dbFileName) async {
    if (kIsWeb) {
      debugPrint('[DB] Web platform detected - database operations not supported on web');
      return;
    }
    try {
      final dbPath = await getDbPath(dbFileName);
      await Share.shareXFiles(
        [XFile(dbPath)],
        subject: 'MOSCO Database Export',
      );
      debugPrint('[DB] File exported: $dbFileName');
    } catch (e) {
      debugPrint('[ERROR] exportDb: $e');
    }
  }
}
