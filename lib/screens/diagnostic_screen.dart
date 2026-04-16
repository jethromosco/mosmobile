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
