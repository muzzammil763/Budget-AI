import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:budget_ai/src/chat/chat_provider.dart';
import 'package:budget_ai/src/helpers/app_data_directory_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

enum ChatSessionLifecycleState { idle }

enum ChatTimelineEntryType { userMessage, assistantMessage, statusCard }

class ChatSessionRecord {
  final String id;
  final String title;
  final String titleSource;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String firstProviderKey;
  final String lastProviderKey;
  final String lastModelId;
  final int activeGeneration;
  final ChatSessionLifecycleState lifecycleState;

  const ChatSessionRecord({
    required this.id,
    required this.title,
    required this.titleSource,
    required this.createdAt,
    required this.updatedAt,
    required this.firstProviderKey,
    required this.lastProviderKey,
    required this.lastModelId,
    required this.activeGeneration,
    required this.lifecycleState,
  });

  ChatSessionRecord copyWith({
    String? title,
    String? titleSource,
    DateTime? updatedAt,
    String? lastProviderKey,
    String? lastModelId,
    int? activeGeneration,
    ChatSessionLifecycleState? lifecycleState,
  }) {
    return ChatSessionRecord(
      id: id,
      title: title ?? this.title,
      titleSource: titleSource ?? this.titleSource,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firstProviderKey: firstProviderKey,
      lastProviderKey: lastProviderKey ?? this.lastProviderKey,
      lastModelId: lastModelId ?? this.lastModelId,
      activeGeneration: activeGeneration ?? this.activeGeneration,
      lifecycleState: lifecycleState ?? this.lifecycleState,
    );
  }

  Map<String, dynamic> toDatabaseMap() => {
    'id': id,
    'title': title,
    'title_source': titleSource,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'first_provider_key': firstProviderKey,
    'last_provider_key': lastProviderKey,
    'last_model_id': lastModelId,
    'active_generation': activeGeneration,
    'session_state': lifecycleState.name,
    'flags_json': '{}',
  };

  factory ChatSessionRecord.fromDatabaseMap(Map<String, dynamic> map) {
    return ChatSessionRecord(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      titleSource: map['title_source']?.toString() ?? 'fallback',
      createdAt: _parseDateTime(map['created_at']?.toString()),
      updatedAt: _parseDateTime(map['updated_at']?.toString()),
      firstProviderKey: map['first_provider_key']?.toString() ?? '',
      lastProviderKey: map['last_provider_key']?.toString() ?? '',
      lastModelId: map['last_model_id']?.toString() ?? '',
      activeGeneration: map['active_generation'] as int? ?? 0,
      lifecycleState: ChatSessionLifecycleState.values.firstWhere(
        (value) => value.name == map['session_state']?.toString(),
        orElse: () => ChatSessionLifecycleState.idle,
      ),
    );
  }
}

class ChatSessionSummary {
  final String id;
  final String title;
  final DateTime updatedAt;
  final String lastProviderKey;
  final String lastModelId;
  final ChatSessionLifecycleState lifecycleState;

  const ChatSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.lastProviderKey,
    required this.lastModelId,
    required this.lifecycleState,
  });

  factory ChatSessionSummary.fromSession(ChatSessionRecord record) {
    return ChatSessionSummary(
      id: record.id,
      title: record.title,
      updatedAt: record.updatedAt,
      lastProviderKey: record.lastProviderKey,
      lastModelId: record.lastModelId,
      lifecycleState: record.lifecycleState,
    );
  }
}

class ChatTimelineEntryRecord {
  final int id;
  final String sessionId;
  final ChatTimelineEntryType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const ChatTimelineEntryRecord({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  ChatMessage? get message {
    if (type == ChatTimelineEntryType.statusCard) return null;
    return ChatMessage.fromJson(payload);
  }

  String? get statusKind => payload['kind']?.toString();

  factory ChatTimelineEntryRecord.fromDatabaseMap(Map<String, dynamic> map) {
    return ChatTimelineEntryRecord(
      id: map['id'] as int? ?? 0,
      sessionId: map['session_id']?.toString() ?? '',
      type: ChatTimelineEntryType.values.firstWhere(
        (value) => value.name == map['type']?.toString(),
        orElse: () => ChatTimelineEntryType.statusCard,
      ),
      payload: _decodeJsonMap(map['payload_json']?.toString()) ?? const {},
      createdAt: _parseDateTime(map['created_at']?.toString()),
    );
  }
}

class ChatContextItemRecord {
  final int id;
  final String sessionId;
  final int generation;
  final int itemOrder;
  final String role;
  final Map<String, dynamic> payload;
  final int estimatedTokens;
  final bool isActive;

  const ChatContextItemRecord({
    required this.id,
    required this.sessionId,
    required this.generation,
    required this.itemOrder,
    required this.role,
    required this.payload,
    required this.estimatedTokens,
    required this.isActive,
  });

  factory ChatContextItemRecord.fromDatabaseMap(Map<String, dynamic> map) {
    return ChatContextItemRecord(
      id: map['id'] as int? ?? 0,
      sessionId: map['session_id']?.toString() ?? '',
      generation: map['generation'] as int? ?? 0,
      itemOrder: map['item_order'] as int? ?? 0,
      role: map['role']?.toString() ?? '',
      payload: _decodeJsonMap(map['payload_json']?.toString()) ?? const {},
      estimatedTokens: map['estimated_tokens'] as int? ?? 0,
      isActive: (map['is_active'] as int? ?? 0) == 1,
    );
  }
}

class ChatAttachmentCopy {
  final String storedPath;
  final String originalPath;
  final String mimeType;
  final int sizeBytes;

  const ChatAttachmentCopy({
    required this.storedPath,
    required this.originalPath,
    required this.mimeType,
    required this.sizeBytes,
  });
}

class LoadedChatSession {
  final ChatSessionRecord session;
  final List<ChatTimelineEntryRecord> timelineEntries;
  final List<ChatContextItemRecord> activeContextItems;

  const LoadedChatSession({
    required this.session,
    required this.timelineEntries,
    required this.activeContextItems,
  });
}

class ChatHistoryDatabase {
  ChatHistoryDatabase._();

  static final ChatHistoryDatabase instance = ChatHistoryDatabase._();
  static const _databaseName = 'budget_ai_chat_history.db';
  static const _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null) return current;
    final dbPath = await AppDataDirectoryService.filePath(_databaseName);
    final next = await openDatabase(
      dbPath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            title_source TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            first_provider_key TEXT NOT NULL,
            last_provider_key TEXT NOT NULL,
            last_model_id TEXT NOT NULL,
            active_generation INTEGER NOT NULL DEFAULT 0,
            session_state TEXT NOT NULL,
            flags_json TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_timeline_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_timeline_session_id ON chat_timeline_entries(session_id, id)',
        );
        await db.execute('''
          CREATE TABLE chat_context_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            generation INTEGER NOT NULL,
            item_order INTEGER NOT NULL,
            role TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            estimated_tokens INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_context_session_active ON chat_context_items(session_id, is_active, generation, item_order)',
        );
        await db.execute('''
          CREATE TABLE chat_attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timeline_entry_id INTEGER NOT NULL,
            stored_path TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL DEFAULT 0,
            original_path TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE,
            FOREIGN KEY(timeline_entry_id) REFERENCES chat_timeline_entries(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_attachments_session_id ON chat_attachments(session_id, timeline_entry_id)',
        );
      },
    );
    await next.execute('PRAGMA foreign_keys = ON');
    _database = next;
    return next;
  }
}

class ChatSessionRepository {
  ChatSessionRepository._();

  static final ChatSessionRepository instance = ChatSessionRepository._();

  Future<ChatSessionRecord> createSession({
    required String id,
    required String title,
    required String titleSource,
    required String providerKey,
    required String modelId,
  }) async {
    final db = await ChatHistoryDatabase.instance.database;
    final now = DateTime.now();
    final record = ChatSessionRecord(
      id: id,
      title: title,
      titleSource: titleSource,
      createdAt: now,
      updatedAt: now,
      firstProviderKey: providerKey,
      lastProviderKey: providerKey,
      lastModelId: modelId,
      activeGeneration: 0,
      lifecycleState: ChatSessionLifecycleState.idle,
    );
    await db.insert('chat_sessions', record.toDatabaseMap());
    return record;
  }

  Future<void> saveSession(ChatSessionRecord record) async {
    final db = await ChatHistoryDatabase.instance.database;
    await db.update(
      'chat_sessions',
      record.toDatabaseMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> updateSessionTitle({
    required String sessionId,
    required String title,
  }) async {
    final sanitizedTitle = title.trim();
    if (sanitizedTitle.isEmpty) return;
    final db = await ChatHistoryDatabase.instance.database;
    await db.update(
      'chat_sessions',
      {'title': sanitizedTitle, 'title_source': 'manual'},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await ChatHistoryDatabase.instance.database;
    await db.delete('chat_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// Deletes ALL chat sessions, timeline entries, context items,
  /// attachments (rows + stored files), and resets the database.
  Future<void> deleteAllSessions() async {
    final db = await ChatHistoryDatabase.instance.database;

    // Delete stored attachment files on disk
    try {
      final attachmentsDir = await _attachmentsRootDirectory();
      if (await attachmentsDir.exists()) {
        await attachmentsDir.delete(recursive: true);
        await attachmentsDir.create(recursive: true);
      }
    } catch (_) {
      // Non-critical; continue even if file cleanup fails
    }

    // Delete all session rows (cascades to timeline_entries,
    // context_items, and attachment records)
    await db.delete('chat_sessions');
  }

  Future<ChatSessionRecord?> getSessionRecord(String sessionId) async {
    final db = await ChatHistoryDatabase.instance.database;
    final rows = await db.query(
      'chat_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatSessionRecord.fromDatabaseMap(rows.first);
  }

  Future<List<ChatSessionSummary>> listRecentSessions({
    String query = '',
  }) async {
    final db = await ChatHistoryDatabase.instance.database;
    final trimmedQuery = query.trim();
    final rows = await db.query(
      'chat_sessions',
      where: trimmedQuery.isEmpty ? null : 'LOWER(title) LIKE ?',
      whereArgs: trimmedQuery.isEmpty
          ? null
          : ['%${trimmedQuery.toLowerCase()}%'],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map(ChatSessionRecord.fromDatabaseMap)
        .map(ChatSessionSummary.fromSession)
        .toList();
  }

  Future<LoadedChatSession?> loadSession(String sessionId) async {
    final db = await ChatHistoryDatabase.instance.database;
    final session = await getSessionRecord(sessionId);
    if (session == null) return null;
    final timelineRows = await db.query(
      'chat_timeline_entries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    final contextRows = await db.query(
      'chat_context_items',
      where: 'session_id = ? AND is_active = 1',
      whereArgs: [sessionId],
      orderBy: 'item_order ASC',
    );
    return LoadedChatSession(
      session: session,
      timelineEntries: timelineRows
          .map(ChatTimelineEntryRecord.fromDatabaseMap)
          .toList(),
      activeContextItems: contextRows
          .map(ChatContextItemRecord.fromDatabaseMap)
          .toList(),
    );
  }

  Future<ChatAttachmentCopy> copyAttachmentToSession({
    required String sessionId,
    required String originalPath,
  }) async {
    final sourceFile = File(originalPath);
    if (!await sourceFile.exists()) {
      return ChatAttachmentCopy(
        storedPath: originalPath,
        originalPath: originalPath,
        mimeType: _guessMimeType(originalPath),
        sizeBytes: 0,
      );
    }
    final root = await _attachmentsRootDirectory();
    final sessionDirectory = Directory(path.join(root.path, sessionId));
    if (!await sessionDirectory.exists()) {
      await sessionDirectory.create(recursive: true);
    }
    final fileName = path.basename(originalPath);
    final destinationName =
        '${DateTime.now().microsecondsSinceEpoch}_$fileName';
    final destination = File(path.join(sessionDirectory.path, destinationName));
    await sourceFile.copy(destination.path);
    final stat = await destination.stat();
    return ChatAttachmentCopy(
      storedPath: destination.path,
      originalPath: originalPath,
      mimeType: _guessMimeType(originalPath),
      sizeBytes: stat.size,
    );
  }

  Future<List<ChatAttachmentCopy>> copyAttachmentsToSession({
    required String sessionId,
    required List<String> originalPaths,
  }) async {
    final results = <ChatAttachmentCopy>[];
    for (final item in originalPaths) {
      results.add(
        await copyAttachmentToSession(sessionId: sessionId, originalPath: item),
      );
    }
    return results;
  }

  Future<int> appendMessageEntry({
    required String sessionId,
    required ChatTimelineEntryType type,
    required ChatMessage message,
    required List<ChatAttachmentCopy> attachments,
  }) async {
    final db = await ChatHistoryDatabase.instance.database;
    final entryId = await db.insert('chat_timeline_entries', {
      'session_id': sessionId,
      'type': type.name,
      'payload_json': jsonEncode(message.toJson()),
      'created_at': message.timestamp.toIso8601String(),
    });
    for (final attachment in attachments) {
      await db.insert('chat_attachments', {
        'session_id': sessionId,
        'timeline_entry_id': entryId,
        'stored_path': attachment.storedPath,
        'mime_type': attachment.mimeType,
        'size_bytes': attachment.sizeBytes,
        'original_path': attachment.originalPath,
      });
    }
    return entryId;
  }

  Future<void> deleteTimelineEntry({required int entryId}) async {
    final db = await ChatHistoryDatabase.instance.database;
    await db.delete(
      'chat_timeline_entries',
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  Future<void> updateMessageEntry({
    required int entryId,
    required ChatMessage message,
  }) async {
    final db = await ChatHistoryDatabase.instance.database;
    await db.update(
      'chat_timeline_entries',
      {'payload_json': jsonEncode(message.toJson())},
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  Future<void> replaceActiveContextItems({
    required String sessionId,
    required int generation,
    required List<Map<String, dynamic>> items,
    required String providerKey,
    required String modelId,
    required ChatSessionLifecycleState lifecycleState,
  }) async {
    final db = await ChatHistoryDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'chat_context_items',
        where: 'session_id = ? AND generation = ?',
        whereArgs: [sessionId, generation],
      );
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        await txn.insert('chat_context_items', {
          'session_id': sessionId,
          'generation': generation,
          'item_order': index,
          'role': item['role']?.toString() ?? '',
          'payload_json': jsonEncode(item),
          'estimated_tokens': 0,
          'is_active': 1,
        });
      }
      await txn.update(
        'chat_sessions',
        {
          'updated_at': DateTime.now().toIso8601String(),
          'last_provider_key': providerKey,
          'last_model_id': modelId,
          'active_generation': generation,
          'session_state': lifecycleState.name,
          'flags_json': '{}',
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Future<Directory> _attachmentsRootDirectory() async {
    return AppDataDirectoryService.childDirectory('chat_attachments');
  }
}

DateTime _parseDateTime(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return DateTime.now();
  }
  try {
    return DateTime.parse(rawValue);
  } catch (_) {
    return DateTime.now();
  }
}

Map<String, dynamic>? _decodeJsonMap(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(rawValue);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (error) {
    debugPrint('[ChatSessionRepository] Could not decode JSON map: $error');
  }
  return null;
}

String _guessMimeType(String filePath) {
  final extension = path.extension(filePath).toLowerCase();
  switch (extension) {
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.svg':
      return 'image/svg+xml';
    case '.jpg':
    case '.jpeg':
    default:
      return 'image/jpeg';
  }
}

String renderConversationStateForSummary(List<Map<String, dynamic>> items) {
  final buffer = StringBuffer();
  for (final item in items) {
    final role = item['role']?.toString() ?? 'unknown';
    buffer.writeln('${role.toUpperCase()}:');
    buffer.writeln(_stringifyConversationContent(item));
    final toolCalls = item['tool_calls'];
    if (toolCalls is List && toolCalls.isNotEmpty) {
      buffer.writeln('Tool calls: ${jsonEncode(toolCalls)}');
    }
    if (item['tool_call_id'] != null) {
      buffer.writeln('Tool call id: ${item['tool_call_id']}');
    }
    buffer.writeln();
  }
  return buffer.toString().trim();
}

String _stringifyConversationContent(Map<String, dynamic> item) {
  final content = item['content'];
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final sections = <String>[];
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type']?.toString();
      if (type == 'text') {
        sections.add(part['text']?.toString() ?? '');
      } else if (type == 'image_url') {
        sections.add('[image attachment]');
      } else {
        sections.add(jsonEncode(part));
      }
    }
    return sections.where((value) => value.trim().isNotEmpty).join('\n');
  }
  return jsonEncode(content);
}
