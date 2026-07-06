import 'dart:async';


import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:budget_ai/features/settings/data/api_key_storage_service.dart';
import 'package:budget_ai/tools/catalog/tool_catalog.dart';
import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';
import 'package:budget_ai/tools/modules/tool_modules.dart';
import 'package:budget_ai/tools/settings/tool_settings.dart';

class ToolRegistry
    with
        WorkspaceHandlerBase,
        ReadToolHandler,
        WriteToolHandler,
        EditToolHandler,
        MemoryWriteToolHandler,
        MemoryEditToolHandler,
        MemoryDeleteToolHandler,
        MemoryListToolHandler,
        MemorySearchToolHandler,
        FinanceAddToolHandler,
        FinanceListToolHandler,
        FinanceSummaryToolHandler,
        FinanceUpdateToolHandler,
        FinanceDeleteToolHandler {
  final Dio _dio;
  CancelToken? _cancelToken;
  List<ToolDefinition>? _toolsCache;
  final Map<String, Map<String, dynamic>> _webSearchCache = {};

  @override
  bool get githubModeActive => false;

  ToolRegistry({Dio? dio}) : _dio = dio ?? Dio();

  void setActiveProviderInfo({
    required String modelId,
    required String apiKey,
    required String baseUrl,
  }) {
  }

  void setActiveMessageImagePaths(List<String>? imagePaths) {
    // No-op for Budget AI (no image attachments)
  }

  void cancelActiveRequests() {
    _cancelToken?.cancel('User cancelled tool execution');
  }

  List<ToolDefinition> getAvailableTools({
    bool includeWorkspaceTools = true,
    bool includeGithubModeTools = false,
  }) {
    _toolsCache ??= _buildTools();
    return _filterEnabledTools(_toolsCache!);
  }

  List<ToolDefinition> _filterEnabledTools(List<ToolDefinition> tools) {
    return tools
        .where((tool) => ToolSettings.isToolEnabled(tool.name))
        .toList(growable: false);
  }

  List<ToolDefinition> _buildTools() {
    return List.unmodifiable([
      ...ToolCatalog.build(
        readHandler: handleReadRequest,
        writeHandler: handleWriteRequest,
        editHandler: handleEditRequest,
        webSearchHandler: _handleWebSearchRequest,
        webPageFetchHandler: _handleWebPageFetchRequest,
      ),
      buildMemoryWriteTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryWriteRequest,
      ),
      buildMemoryEditTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryEditRequest,
      ),
      buildMemoryDeleteTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryDeleteRequest,
      ),
      buildMemoryListTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemoryListRequest,
      ),
      buildMemorySearchTool(
        context: ToolDefinitionContext.standard,
        handler: handleMemorySearchRequest,
      ),
      buildFinanceAddTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceAddRequest,
      ),
      buildFinanceListTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceListRequest,
      ),
      buildFinanceSummaryTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceSummaryRequest,
      ),
      buildFinanceUpdateTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceUpdateRequest,
      ),
      buildFinanceDeleteTool(
        context: ToolDefinitionContext.standard,
        handler: handleFinanceDeleteRequest,
      ),
    ]);
  }

  Future<dynamic> executeTool(
    String name,
    Map<String, dynamic> arguments, {
    bool bypassToolManagerApproval = false,
  }) async {
    debugPrint('[ToolRegistry] Executing tool: $name with args: $arguments');

    final disabledResult = _disabledToolResult(name);
    if (disabledResult != null) {
      return disabledResult;
    }

    final tool = _filterEnabledTools(_toolsCache ?? _buildTools()).firstWhere(
      (t) => t.name == name,
      orElse: () => throw Exception('Tool not found: $name'),
    );

    if (tool.handler == null) {
      throw Exception('Tool $name has no handler');
    }

    _cancelToken = CancelToken();

    try {
      final result = await tool.handler!(arguments);
      debugPrint('[ToolRegistry] Tool $name result: $result');
      return result;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        rethrow;
      }
      return {'error': e.toString(), 'tool': name};
    } catch (e) {
      return {'error': e.toString(), 'tool': name};
    } finally {
      _cancelToken = null;
    }
  }

  Stream<ToolExecutionEvent> executeToolStream(
    String name,
    Map<String, dynamic> arguments, {
    bool bypassToolManagerApproval = false,
  }) async* {
    final result = await executeTool(
      name,
      arguments,
      bypassToolManagerApproval: bypassToolManagerApproval,
    );
    yield ToolExecutionEvent(
      result: result,
      isComplete: true,
      isError: result is Map && result['error'] != null,
    );
  }

  Map<String, dynamic>? _disabledToolResult(String name) {
    final tool = ToolSettings.toolForName(name);
    if (tool == null || ToolSettings.isToolEnabled(name)) return null;

    return {
      'tool': name,
      'disabled': true,
      'error': '${tool.title} is disabled in Settings.',
    };
  }
}

extension _ToolWebHandlers on ToolRegistry {
  Future<dynamic> _handleWebSearchRequest(Map<String, dynamic> args) async {
    final maxResults = ((args['max_results'] as num?) ?? 5).toInt().clamp(1, 10);
    final domainHint = (args['domain_hint'] as String? ?? '').trim();

    final queriesList = args['queries'];
    if (queriesList is List && queriesList.isNotEmpty) {
      final results = <Map<String, dynamic>>[];
      var failedCount = 0;
      for (final q in queriesList) {
        final qStr = q?.toString().trim() ?? '';
        if (qStr.isEmpty) continue;
        try {
          final data = await _executeSmartSearch(
            query: qStr,
            maxResults: maxResults,
            domainHint: domainHint.isEmpty ? null : domainHint,
          );
          results.add(data);
        } catch (e) {
          failedCount++;
          results.add({'query': qStr, 'error': e.toString()});
        }
      }
      return {
        'tool': 'web_search',
        'count': results.length,
        'failed_count': failedCount,
        'results': results,
      };
    }

    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return {
        'error': 'Provide query (single search) or queries[] (array).',
        'tool': 'web_search',
      };
    }
    try {
      return await _executeSmartSearch(
        query: query,
        maxResults: maxResults,
        domainHint: domainHint.isEmpty ? null : domainHint,
      );
    } catch (e) {
      return {'error': 'Failed to search: $e', 'tool': 'web_search'};
    }
  }

  Future<Map<String, dynamic>> _executeSmartSearch({
    required String query,
    required int maxResults,
    String? domainHint,
  }) async {
    final cacheKey = '$query|$maxResults|$domainHint';
    if (_webSearchCache.containsKey(cacheKey)) {
      return _webSearchCache[cacheKey]!;
    }

    final searchApiKey = await ApiKeyStorageService.getSearchApiKey();
    if (searchApiKey != null && searchApiKey.trim().isNotEmpty) {
      try {
        final result = await _searchWithSearchApi(
          query: query,
          maxResults: maxResults,
          apiKey: searchApiKey.trim(),
          domainHint: domainHint,
        );
        _webSearchCache[cacheKey] = result;
        return result;
      } catch (e) {
        debugPrint('[ToolRegistry] SearchAPI failed, falling back to DDG: $e');
      }
    }

    final result = await _searchWithDuckDuckGo(
      query: query,
      maxResults: maxResults,
      domainHint: domainHint,
    );
    _webSearchCache[cacheKey] = result;
    return result;
  }

  Future<Map<String, dynamic>> _searchWithSearchApi({
    required String query,
    required int maxResults,
    required String apiKey,
    String? domainHint,
  }) async {
    final params = {
      'engine': 'google',
      'q': domainHint != null ? '$query site:$domainHint' : query,
      'api_key': apiKey,
      'num': maxResults.toString(),
    };

    final response = await _dio.get(
      'https://www.searchapi.io/api/v1/search',
      queryParameters: params,
      options: Options(
        headers: {'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
      cancelToken: _cancelToken,
    );

    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};

    final organicResults = data['organic_results'];
    final results = <Map<String, dynamic>>[];

    if (organicResults is List) {
      for (final item in organicResults.take(maxResults)) {
        if (item is Map) {
          results.add({
            'title': item['title']?.toString() ?? '',
            'url': item['link']?.toString() ?? '',
            'snippet': item['snippet']?.toString() ?? '',
          });
        }
      }
    }

    return {
      'tool': 'web_search',
      'provider': 'searchapi',
      'query': query,
      'result_count': results.length,
      'results': results,
    };
  }

  Future<Map<String, dynamic>> _searchWithDuckDuckGo({
    required String query,
    required int maxResults,
    String? domainHint,
  }) async {
    final searchQuery = domainHint != null ? '$query site:$domainHint' : query;
    final encodedQuery = Uri.encodeComponent(searchQuery);

    final response = await _dio.get(
      'https://html.duckduckgo.com/html/?q=$encodedQuery',
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept': 'text/html',
        },
        responseType: ResponseType.plain,
      ),
      cancelToken: _cancelToken,
    );

    final html = response.data?.toString() ?? '';
    final results = <Map<String, dynamic>>[];

    final resultPattern = RegExp(
      r'<a[^>]+class="result__a"[^>]+href="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetPattern = RegExp(
      r'<a[^>]+class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    final resultMatches = resultPattern.allMatches(html).take(maxResults);
    final snippetMatches = snippetPattern.allMatches(html).toList();

    var i = 0;
    for (final match in resultMatches) {
      final url = match.group(1) ?? '';
      final title = match.group(2)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
      final snippet = i < snippetMatches.length
          ? snippetMatches[i]
                  .group(1)
                  ?.replaceAll(RegExp(r'<[^>]+>'), '')
                  .trim() ??
              ''
          : '';

      if (url.isNotEmpty && !url.contains('duckduckgo.com')) {
        final decodedUrl = Uri.decodeComponent(
          url.replaceAll(RegExp(r'^//duckduckgo\.com/l/\?uddg='), ''),
        );
        results.add({
          'title': title,
          'url': decodedUrl,
          'snippet': snippet,
        });
      }
      i++;
    }

    return {
      'tool': 'web_search',
      'provider': 'duckduckgo',
      'query': query,
      'result_count': results.length,
      'results': results,
    };
  }

  Future<dynamic> _handleWebPageFetchRequest(Map<String, dynamic> args) async {
    final maxChars = ((args['max_chars'] as num?) ?? 4000).toInt().clamp(300, 12000);

    final urlsList = args['urls'];
    if (urlsList is List && urlsList.isNotEmpty) {
      final results = <Map<String, dynamic>>[];
      var failedCount = 0;
      for (final u in urlsList) {
        final uStr = u?.toString().trim() ?? '';
        if (uStr.isEmpty) continue;
        try {
          final data = await _fetchWebPage(url: uStr, maxChars: maxChars);
          results.add(data);
        } catch (e) {
          failedCount++;
          results.add({'url': uStr, 'error': e.toString()});
        }
      }
      return {
        'tool': 'web_page_fetch',
        'count': results.length,
        'failed_count': failedCount,
        'results': results,
      };
    }

    final url = (args['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      return {
        'error': 'Provide url (single page) or urls[] (array).',
        'tool': 'web_page_fetch',
      };
    }
    try {
      return await _fetchWebPage(url: url, maxChars: maxChars);
    } catch (e) {
      return {'error': 'Failed to fetch page: $e', 'tool': 'web_page_fetch'};
    }
  }

  Future<Map<String, dynamic>> _fetchWebPage({
    required String url,
    required int maxChars,
  }) async {
    final response = await _dio.get(
      url,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 5,
      ),
      cancelToken: _cancelToken,
    );

    var content = response.data?.toString() ?? '';

    content = content
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', dotAll: true), '')
        .replaceAll(RegExp(r'<footer[^>]*>.*?</footer>', dotAll: true), '')
        .replaceAll(RegExp(r'<header[^>]*>.*?</header>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (content.length > maxChars) {
      content = '${content.substring(0, maxChars)}...';
    }

    return {
      'tool': 'web_page_fetch',
      'url': url,
      'content': content,
      'content_length': content.length,
    };
  }
}
