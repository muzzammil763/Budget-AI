/// Context in which a tool definition is exposed to the model.
///
/// Individual files in `tools/modules/` can switch parameter schemas,
/// descriptions, or availability hints based on this value.
enum ToolDefinitionContext { standard, remoteWorkspace, githubModeLocal }
