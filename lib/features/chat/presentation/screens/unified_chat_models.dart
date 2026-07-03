part of 'unified_chat_screen.dart';

class _ConnectedWorkspace {
  final String path;
  final String label;
  final String source;
  final bool isConnecting;

  const _ConnectedWorkspace({
    required this.path,
    required this.label,
    required this.source,
    this.isConnecting = false,
  });

  Map<String, dynamic> toPrefs() {
    return {'path': path, 'label': label, 'source': source};
  }

  _ConnectedWorkspace copyWith({
    String? path,
    String? label,
    String? source,
    bool? isConnecting,
  }) {
    return _ConnectedWorkspace(
      path: path ?? this.path,
      label: label ?? this.label,
      source: source ?? this.source,
      isConnecting: isConnecting ?? this.isConnecting,
    );
  }

  String get key => '$source::$path';
}
