import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_syntax_view/flutter_syntax_view.dart';
import 'package:budget_ai/app/theme/app_theme.dart';
import 'package:budget_ai/core/widgets/toast_helper.dart';
import 'package:budget_ai/features/mac_companion/data/mac_companion_service.dart';
import 'package:path/path.dart' as p;
import 'package:toastification/toastification.dart';

enum WorkspaceFileSource { remoteMac, localFile }

class WorkspaceFilePreviewScreen extends StatefulWidget {
  const WorkspaceFilePreviewScreen({
    super.key,
    required this.path,
    required this.workspaceRoot,
    required this.source,
    this.initialLine,
    this.filePath,
    this.isLocalFile,
    this.localPath,
    this.fullName,
    this.branch,
  });

  final String path;
  final String workspaceRoot;
  final WorkspaceFileSource source;
  final int? initialLine;
  final String? filePath;
  final bool? isLocalFile;
  final String? localPath;
  final String? fullName;
  final String? branch;

  @override
  State<WorkspaceFilePreviewScreen> createState() =>
      _WorkspaceFilePreviewScreenState();
}

class _WorkspaceFilePreviewScreenState
    extends State<WorkspaceFilePreviewScreen> {
  bool _loading = true;
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      String content;
      if (widget.source == WorkspaceFileSource.localFile) {
        final file = File(_absolutePath);
        content = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      } else {
        final result = await MacCompanionService.instance.readRemoteFile(
          widget.path,
          workspaceRoot: widget.workspaceRoot,
          updateState: false,
        );
        if (result['ok'] == false || result['error'] != null) {
          throw Exception(result['error']?.toString() ?? 'Could not read file');
        }
        final file = result['file'];
        if (file is! Map) {
          throw Exception('Could not read file content');
        }
        content = file['content']?.toString() ?? '';
      }

      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String get _absolutePath {
    if (p.isAbsolute(widget.path)) return widget.path;
    return p.normalize(p.join(widget.workspaceRoot, widget.path));
  }

  Syntax? _syntaxFor(String path) {
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart' => Syntax.DART,
      'js' || 'mjs' || 'cjs' || 'jsx' => Syntax.JAVASCRIPT,
      'ts' || 'tsx' => Syntax.JAVASCRIPT,
      'py' => Syntax.PYTHON,
      'java' => Syntax.JAVA,
      'kt' || 'kts' => Syntax.KOTLIN,
      'swift' => Syntax.SWIFT,
      'c' || 'h' => Syntax.C,
      'cpp' || 'cc' || 'cxx' || 'hpp' => Syntax.CPP,
      'yaml' || 'yml' => Syntax.YAML,
      'rs' => Syntax.RUST,
      'lua' => Syntax.LUA,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = p.basename(widget.path);
    final line = widget.initialLine;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(fileName, style: const TextStyle(fontSize: 15)),
            Text(
              [
                widget.path,
                if (line != null && line > 0) 'line $line',
              ].join(' - '),
              overflow: TextOverflow.ellipsis,
              style: AppTheme.bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          if ((_content ?? '').isNotEmpty)
            IconButton(
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _content!));
                showAppToast(
                  context,
                  message: 'Copied to clipboard',
                  type: ToastificationType.success,
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError(theme)
          : _buildCode(theme),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle,
              color: theme.colorScheme.error,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Could not open file',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCode(ThemeData theme) {
    final content = _content ?? '';
    final syntax = _syntaxFor(widget.path);
    if (syntax != null) {
      return SyntaxView(
        code: content,
        syntax: syntax,
        syntaxTheme: theme.brightness == Brightness.dark
            ? SyntaxTheme.vscodeDark()
            : SyntaxTheme.vscodeLight(),
        fontSize: 13,
        withLinesCount: true,
        expanded: true,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        content,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.colorScheme.onSurface,
          height: 1.55,
        ),
      ),
    );
  }
}
