import 'package:budget_ai/tools/core/tool_context.dart';
import 'package:budget_ai/tools/core/tool_models.dart';

ToolDefinition buildWebPageFetchTool({
  ToolDefinitionContext context = ToolDefinitionContext.standard,
  required ToolHandler handler,
}) => ToolDefinition(
  name: 'web_page_fetch',
  description:
      'Fetch and extract readable text from a web page. Returns the page title, meta description, and extracted body text (HTML stripped). Use this to read documentation pages, blog posts, or specific URLs found via web_search. Batch multiple URLs in a single call using urls[].',
  parameters: {
    'type': 'object',
    'properties': {
      'url': {'type': 'string', 'description': 'URL of the web page to fetch.'},
      'urls': {
        'type': 'array',
        'description':
            'Array of URLs to batch in one call. Use this instead of url when you need multiple pages.',
        'items': {'type': 'string'},
      },
      'max_chars': {
        'type': 'integer',
        'description':
            'Maximum characters of extracted text to return (default: 4000, max: 12000).',
        'default': 4000,
      },
    },
    'required': [],
  },
  handler: handler,
);
