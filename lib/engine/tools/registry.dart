import 'dart:async';

import '../models.dart';

/// Context handed to every tool execution.
class ToolContext {
  ToolContext({this.sessionId, required this.cwd, this.askUser});

  final String? sessionId;
  final String cwd;
  final Future<AskUserResponse> Function(AskUserPayload payload)? askUser;
}

typedef ToolHandler = Future<String> Function(
    Map<String, dynamic> args, ToolContext ctx);

class ToolRegistry {
  final _tools = <String, _RegisteredTool>{};

  void register(ToolDefinition definition, ToolHandler handler) {
    _tools[definition.name] = _RegisteredTool(definition, handler);
  }

  void unregister(String name) => _tools.remove(name);

  List<ToolDefinition> getDefinitions() =>
      _tools.values.map((t) => t.definition).toList();

  bool has(String name) => _tools.containsKey(name);

  ToolDefinition? definition(String name) => _tools[name]?.definition;

  Future<String> call(String name, Map<String, dynamic> args, ToolContext ctx) {
    final tool = _tools[name];
    if (tool == null) {
      throw StateError('Unknown tool: $name');
    }
    return tool.handler(args, ctx);
  }
}

class _RegisteredTool {
  _RegisteredTool(this.definition, this.handler);

  final ToolDefinition definition;
  final ToolHandler handler;
}
