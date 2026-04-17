import 'dart:io';
import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../constants/category_map.dart';

class DiagnosticScreen extends StatefulWidget {
  final String category;
  const DiagnosticScreen({super.key, required this.category});

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  String _output = 'Running diagnostics...';

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    final buffer = StringBuffer();
    try {
      final dbFileName = categoryDbMap[widget.category]!;
      final dbHelper = DbHelper();

      // Check if file exists
      final exists = await dbHelper.dbExists(dbFileName);
      buffer.writeln('=== FILE CHECK ===');
      buffer.writeln('DB File: $dbFileName');
      buffer.writeln('Exists: $exists');
      buffer.writeln('');

      if (!exists) {
        buffer.writeln('FILE NOT FOUND. Import the database first.');
        setState(() => _output = buffer.toString());
        return;
      }

      // Check file size
      final path = await dbHelper.getDbPath(dbFileName);
      final file = File(path);
      final size = await file.length();
      buffer.writeln('File size: $size bytes');
      buffer.writeln('Path: $path');
      buffer.writeln('');

      // Open DB
      final db = await dbHelper.openCategoryDb(dbFileName);
      if (db == null) {
        buffer.writeln('FAILED TO OPEN DB');
        setState(() => _output = buffer.toString());
        return;
      }

      // List all tables
      buffer.writeln('=== TABLES ===');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );
      for (final t in tables) {
        buffer.writeln('Table: ${t['name']}');
      }
      buffer.writeln('');

      // For each table, show columns and first 2 rows
      for (final t in tables) {
        final tableName = t['name'] as String;
        buffer.writeln('=== TABLE: $tableName ===');

        // Get columns
        final cols = await db.rawQuery('PRAGMA table_info($tableName)');
        buffer.writeln('Columns:');
        for (final c in cols) {
          buffer.writeln('  ${c['name']} (${c['type']})');
        }

        // Get first 2 rows
        final rows = await db.rawQuery('SELECT * FROM $tableName LIMIT 2');
        buffer.writeln('First 2 rows:');
        for (final row in rows) {
          buffer.writeln('  $row');
        }

        // Get row count
        final count = await db.rawQuery('SELECT COUNT(*) as cnt FROM $tableName');
        buffer.writeln('Total rows: ${count.first['cnt']}');
        buffer.writeln('');
      }

      // === DEEP TRANSACTION SCAN ===
      buffer.writeln('');
      buffer.writeln('=== TRANSACTION DEEP SCAN ===');

      // Find transactions table
      String? txTable;
      for (final t in tables) {
        final name = t['name'] as String;
        if (name.toLowerCase().contains('trans')) {
          txTable = name;
          break;
        }
      }

      if (txTable != null) {
        buffer.writeln('Transactions table: $txTable');
        buffer.writeln('');

        // Show all columns
        final txCols = await db.rawQuery('PRAGMA table_info($txTable)');
        buffer.writeln('Columns:');
        for (final c in txCols) {
          buffer.writeln('  ${c['name']} (${c['type']})');
        }
        buffer.writeln('');

        // Show first 5 rows raw — no filtering
        final txRows = await db.rawQuery('SELECT rowid, * FROM $txTable LIMIT 5');
        buffer.writeln('First 5 rows (raw):');
        for (final row in txRows) {
          buffer.writeln('  $row');
        }
        buffer.writeln('');

        // Show total count
        final txCount = await db.rawQuery('SELECT COUNT(*) as cnt FROM $txTable');
        buffer.writeln('Total transactions: ${txCount.first['cnt']}');
        buffer.writeln('');

        // Show distinct type values
        final types = await db.rawQuery(
          'SELECT DISTINCT type FROM $txTable LIMIT 20'
        );
        buffer.writeln('Distinct type values: $types');
        buffer.writeln('');

        // Show all column names that might be a product FK
        final allCols = txCols.map((c) => c['name'] as String).toList();
        buffer.writeln('All transaction column names: $allCols');
        buffer.writeln('');

        // === FK COLUMN SEARCH ===
        buffer.writeln('=== FK COLUMN SEARCH ===');
        for (final col in allCols) {
          try {
            final sample = await db.rawQuery(
              'SELECT "$col", COUNT(*) as cnt FROM $txTable GROUP BY "$col" LIMIT 3'
            );
            buffer.writeln('  $col: $sample');
          } catch (e) {
            buffer.writeln('  $col: error $e');
          }
        }
        buffer.writeln('');

        // === PRODUCTS ROWID CHECK ===
        buffer.writeln('=== PRODUCTS ROWID CHECK ===');
        try {
          final prodSample = await db.rawQuery(
            'SELECT rowid, * FROM products LIMIT 3'
          );
          buffer.writeln('Products with rowid: $prodSample');
          buffer.writeln('');
        } catch (e) {
          buffer.writeln('Error querying products: $e');
          buffer.writeln('');
        }

        // === SAMPLE LOOKUP TEST ===
        buffer.writeln('=== SAMPLE LOOKUP TEST ===');
        try {
          // Get first product and try to find its transactions
          final firstProd = await db.rawQuery('SELECT rowid, id, od, thk FROM products LIMIT 1');
          if (firstProd.isNotEmpty) {
            final prod = firstProd.first;
            final rowid = prod['rowid'];
            final id = prod['id'];
            final od = prod['od'];
            final thk = prod['thk'];
            buffer.writeln('First product: rowid=$rowid, id=$id, od=$od, thk=$thk');

            // Try lookup by dimensions (as desktop app does)
            final byDim = await db.rawQuery(
              'SELECT rowid, * FROM $txTable WHERE id_size=? AND od_size=? AND th_size=? LIMIT 3',
              [id, od, thk],
            );
            buffer.writeln('Transactions matching dimensions: ${byDim.length} rows');
            for (final row in byDim) {
              buffer.writeln('  $row');
            }
          }
        } catch (e) {
          buffer.writeln('Lookup test error: $e');
        }
      } else {
        buffer.writeln('NO TRANSACTIONS TABLE FOUND');
      }
    } catch (e) {
      buffer.writeln('ERROR: $e');
    }

    setState(() => _output = buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DB Diagnostic')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          _output,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
