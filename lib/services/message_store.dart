import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:bitchat/services/nostr_chat_service.dart';

/// SQLite-backed message store for chat history persistence.
///
/// Stores text and image messages per channel, with automatic
/// loading of recent history on app start.
class MessageStore {
  MessageStore._();
  static final MessageStore instance = MessageStore._();

  Database? _db;
  bool get isOpen => _db != null;

  static const String _tableName = 'messages';
  static const int _dbVersion = 1;

  /// Default number of messages to load per channel.
  static const int defaultPageSize = 100;

  /// Initialize the database.
  Future<void> initialize() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'bitchat_messages.db');

    _db = await openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        channel TEXT NOT NULL,
        sender_nickname TEXT NOT NULL,
        sender_pub_key TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_own_message INTEGER NOT NULL DEFAULT 0,
        message_type TEXT NOT NULL DEFAULT 'text',
        image_base64 TEXT,
        image_width INTEGER,
        image_height INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_channel_time ON $_tableName (channel, timestamp DESC)',
    );
  }

  /// Save a chat message to the store.
  Future<int> saveMessage(ChatMessage message) async {
    _ensureOpen();
    return _db!.insert(_tableName, {
      'channel': message.channel,
      'sender_nickname': message.senderNickname,
      'sender_pub_key': message.senderPubKey,
      'text': message.text,
      'timestamp': message.timestamp.millisecondsSinceEpoch,
      'is_own_message': message.isOwnMessage ? 1 : 0,
      'message_type': message.messageType.name,
      'image_base64': message.imageBase64,
      'image_width': message.imageWidth,
      'image_height': message.imageHeight,
    });
  }

  /// Load recent messages for a channel.
  Future<List<ChatMessage>> loadMessages(
    String channel, {
    int limit = defaultPageSize,
    int offset = 0,
  }) async {
    _ensureOpen();
    final rows = await _db!.query(
      _tableName,
      where: 'channel = ?',
      whereArgs: [channel],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    // Reverse to get chronological order (oldest first)
    return rows.reversed.map(_rowToMessage).toList();
  }

  /// Get message count for a channel.
  Future<int> messageCount(String channel) async {
    _ensureOpen();
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName WHERE channel = ?',
      [channel],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete all messages for a channel.
  Future<int> clearChannel(String channel) async {
    _ensureOpen();
    return _db!.delete(_tableName, where: 'channel = ?', whereArgs: [channel]);
  }

  /// Delete all messages (emergency wipe).
  Future<int> clearAll() async {
    _ensureOpen();
    return _db!.delete(_tableName);
  }

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  ChatMessage _rowToMessage(Map<String, dynamic> row) {
    return ChatMessage(
      text: row['text'] as String,
      senderNickname: row['sender_nickname'] as String,
      senderPubKey: row['sender_pub_key'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
      channel: row['channel'] as String,
      isOwnMessage: (row['is_own_message'] as int) == 1,
      messageType: MessageType.values.firstWhere(
        (e) => e.name == (row['message_type'] as String),
        orElse: () => MessageType.text,
      ),
      imageBase64: row['image_base64'] as String?,
      imageWidth: row['image_width'] as int?,
      imageHeight: row['image_height'] as int?,
    );
  }

  void _ensureOpen() {
    if (_db == null) {
      throw StateError(
        'MessageStore not initialized. Call initialize() first.',
      );
    }
  }
}
