import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../state/chat_controller.dart';

/// Persists chat messages and farm context to SQLite (desktop via sqflite_ffi).
class ChatStorageService {
  static const _dbName = 'maathai_chat.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<void> initialize({String? databasePath}) async {
    if (_db != null) return;

    final path = databasePath ?? await _defaultDatabasePath();
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<String> _defaultDatabasePath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, _dbName);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        rag_passages TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    await db.execute('''
      CREATE TABLE farm_context (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        region TEXT,
        crop TEXT,
        season TEXT,
        language TEXT NOT NULL DEFAULT 'en'
      )
    ''');
    await db.insert('farm_context', {'id': 1, 'language': 'en'});
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('ChatStorageService.initialize() must be called first');
    }
    return db;
  }

  Future<List<ChatMessage>> loadMessages() async {
    final rows = await _database.query(
      'messages',
      orderBy: 'timestamp ASC',
    );

    return rows.map((row) {
      final passagesJson = row['rag_passages'] as String? ?? '[]';
      final passages = (jsonDecode(passagesJson) as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      return ChatMessage(
        id: row['id'] as String,
        role: _roleFromString(row['role'] as String),
        content: row['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        ragPassages: passages,
      );
    }).toList();
  }

  Future<FarmContext> loadFarmContext() async {
    final rows = await _database.query('farm_context', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) {
      return const FarmContext();
    }
    final row = rows.first;
    return FarmContext(
      region: row['region'] as String?,
      crop: row['crop'] as String?,
      season: row['season'] as String?,
      language: row['language'] as String? ?? 'en',
    );
  }

  Future<void> saveMessage(ChatMessage message) async {
    if (message.isStreaming || message.content.isEmpty && message.role == MessageRole.assistant) {
      return;
    }

    await _database.insert(
      'messages',
      _messageToRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMessage(String id) async {
    await _database.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearMessages() async {
    await _database.delete('messages');
  }

  Future<void> saveFarmContext(FarmContext context) async {
    await _database.update(
      'farm_context',
      {
        'region': context.region,
        'crop': context.crop,
        'season': context.season,
        'language': context.language ?? 'en',
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Map<String, Object?> _messageToRow(ChatMessage message) {
    return {
      'id': message.id,
      'role': message.role.name,
      'content': message.content,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'rag_passages': jsonEncode(message.ragPassages),
    };
  }

  MessageRole _roleFromString(String value) {
    return MessageRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => MessageRole.user,
    );
  }
}
