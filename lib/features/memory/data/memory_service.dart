import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class MemoryItem {
  final String id;
  final String key;
  final String title;
  final String content;
  final String type;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MemoryItem({
    required this.id,
    required this.key,
    required this.title,
    required this.content,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
    id: json['id'] as String? ?? _generateId(),
    key: json['key'] as String? ?? json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    type: json['type'] as String? ?? 'fact',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'key': key,
    'title': title,
    'content': content,
    'type': type,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  MemoryItem copyWith({
    String? title,
    String? content,
    String? type,
    DateTime? updatedAt,
  }) => MemoryItem(
    id: id,
    key: key,
    title: title ?? this.title,
    content: content ?? this.content,
    type: type ?? this.type,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static String _generateId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'mem_$ts';
  }
}

class MemoryService {
  MemoryService._();

  static final MemoryService instance = MemoryService._();

  static const _storageFileName = 'memories.json';

  List<MemoryItem>? _cache;

  Future<File> _storageFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_storageFileName');
  }

  Future<List<MemoryItem>> getAll() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        _cache = [];
        return const [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = [];
        return const [];
      }
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .map((e) => MemoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      return List.unmodifiable(_cache!);
    } catch (e) {
      debugPrint('[MemoryService] Failed to read memories: $e');
      _cache = [];
      return const [];
    }
  }

  Future<({MemoryItem item, bool wasUpdated})> write({
    required String key,
    required String title,
    required String content,
    String type = 'fact',
  }) async {
    final memories = List<MemoryItem>.from(await getAll());
    final now = DateTime.now();
    final normalizedKey = key.trim().toLowerCase();

    final existingIndex = memories.indexWhere(
      (m) => m.key.toLowerCase() == normalizedKey,
    );

    MemoryItem item;
    bool wasUpdated;

    if (existingIndex >= 0) {
      item = memories[existingIndex].copyWith(
        title: title.trim().isEmpty ? null : title.trim(),
        content: content.trim(),
        type: type.trim().isEmpty ? null : type.trim(),
        updatedAt: now,
      );
      memories[existingIndex] = item;
      wasUpdated = true;
    } else {
      item = MemoryItem(
        id: _generateId(),
        key: key.trim(),
        title: title.trim().isEmpty ? key.trim() : title.trim(),
        content: content.trim(),
        type: type.trim().isEmpty ? 'fact' : type.trim(),
        createdAt: now,
        updatedAt: now,
      );
      memories.add(item);
      wasUpdated = false;
    }

    _cache = memories;
    await _persist();
    return (item: item, wasUpdated: wasUpdated);
  }

  Future<bool> delete(String id) async {
    final memories = List<MemoryItem>.from(await getAll());
    final before = memories.length;
    memories.removeWhere((m) => m.id == id);
    if (memories.length == before) return false;
    _cache = memories;
    await _persist();
    return true;
  }

  void invalidateCache() => _cache = null;

  Future<void> _persist() async {
    try {
      final file = await _storageFile();
      final json = jsonEncode(_cache!.map((m) => m.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('[MemoryService] Failed to persist memories: $e');
    }
  }

  String buildContextText(List<MemoryItem> memories) {
    if (memories.isEmpty) return '';
    return memories
        .map((m) => '- [${m.type}] ${m.title}: ${m.content}')
        .join('\n');
  }

  String buildExportJson(List<MemoryItem> memories) {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'memories': memories.map((m) => m.toJson()).toList(),
    });
  }

  Future<int> importFromJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    final List<dynamic> rawList;
    if (decoded is Map && decoded['memories'] is List) {
      rawList = decoded['memories'] as List<dynamic>;
    } else if (decoded is List) {
      rawList = decoded;
    } else {
      throw const FormatException('Invalid memory bundle format');
    }

    final incoming = rawList
        .map((e) => MemoryItem.fromJson(e as Map<String, dynamic>))
        .toList();

    final existing = List<MemoryItem>.from(await getAll());
    final now = DateTime.now();
    var affectedCount = 0;

    for (final item in incoming) {
      final existingIndex = existing.indexWhere(
        (m) => m.key.toLowerCase() == item.key.toLowerCase(),
      );
      if (existingIndex >= 0) {
        // Overwrite existing item with new data
        existing[existingIndex] = existing[existingIndex].copyWith(
          title: item.title,
          content: item.content,
          type: item.type,
          updatedAt: now,
        );
        affectedCount++;
      } else {
        existing.add(item);
        affectedCount++;
      }
    }

    if (affectedCount > 0) {
      _cache = existing;
      await _persist();
    }
    return affectedCount;
  }

  Future<void> shareExportFile(List<MemoryItem> memories) async {
    final json = buildExportJson(memories);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/OpenGate_Memories_Export.json');
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'OpenGate Memories Export',
      ),
    );
  }
}

String _generateId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return 'mem_$ts';
}
