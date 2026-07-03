import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';

ToolDefinition buildWebSearchTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'web_search',
  description:
      'Search the web using the configured provider. DuckDuckGo is the default; SearchAPI can be selected in Settings and falls back to DuckDuckGo if its keys, quota, or API request fail. Returns search results with title, URL, and snippet. Use this to look up documentation, API references, error messages, or current information. Batch multiple related queries in one call using queries[].',
  parameters: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'description': 'Search query string.'},
      'queries': {
        'type': 'array',
        'description':
            'Array of search queries to batch in one call. Use this instead of query when you need multiple searches.',
        'items': {'type': 'string'},
      },
      'max_results': {
        'type': 'integer',
        'description': 'Maximum results per query (default: 5, max: 10).',
        'default': 5,
      },
      'domain_hint': {
        'type': 'string',
        'description':
            'Optional domain to restrict results to, e.g. "docs.flutter.dev" or "github.com".',
      },
    },
    'required': [],
  },
  handler: handler,
);
