import 'package:flutter/foundation.dart';

import '../engine/models.dart';

/// Operation intent of a tool call — drives Zone 3 badges and Zone 2
/// read/write aggregation.
enum OperationClass { read, write, execute }

/// One executed tool call, classified for the session dashboard.
/// Derived UI-side from [AgentStep] (which already carries call, result,
/// and duration), so no engine changes are needed to capture telemetry.
class ToolExecutionEvent {
  ToolExecutionEvent({
    required this.id,
    required this.timestamp,
    required this.toolName,
    required this.source,
    required this.operation,
    required this.ok,
    required this.requestJson,
    required this.response,
    required this.durationMs,
  });

  factory ToolExecutionEvent.fromStep(AgentStep step, {String? id}) {
    final call = step.toolCall!;
    final result = step.toolResult ?? '';
    return ToolExecutionEvent(
      id: id ?? call.id,
      timestamp: DateTime.now(),
      toolName: call.name,
      source: _sourceOf(call.name),
      operation: _classify(call.name),
      ok: _isOkResult(result),
      requestJson: call.argumentsJson,
      response: result,
      durationMs: step.toolCallMs ?? 0,
    );
  }

  final String id;
  final DateTime timestamp;
  final String toolName;

  /// `mcp:<server>` for MCP tools (engine names them `mcp__<server>__<tool>`),
  /// otherwise `system` for built-in CLI/file tools.
  final String source;
  final OperationClass operation;
  final bool ok;
  final String requestJson;
  final String response;
  final int durationMs;

  /// True when the tool went to an MCP server rather than a local handler.
  bool get isMcp => source.startsWith('mcp:');

  static String _sourceOf(String toolName) {
    if (toolName.startsWith('mcp__')) {
      final parts = toolName.split('__');
      return parts.length >= 3 ? 'mcp:${parts[1]}' : 'mcp:unknown';
    }
    return 'system';
  }

  static OperationClass _classify(String toolName) {
    final name = toolName.startsWith('mcp__') ? toolName.split('__').last : toolName;
    if (name == 'bash') return OperationClass.execute;
    const reads = [
      'read', 'list', 'get', 'search', 'find', 'grep', 'glob', 'fetch',
      'show', 'query', 'analyze', 'scan',
    ];
    const writes = [
      'write', 'create', 'update', 'edit', 'delete', 'publish', 'sync',
      'approve', 'spam', 'upload', 'insert', 'modify', 'rename', 'move',
    ];
    final lower = name.toLowerCase();
    for (final w in writes) {
      if (lower == w || lower.startsWith(w) || lower.contains(w)) {
        return OperationClass.write;
      }
    }
    for (final r in reads) {
      if (lower == r || lower.startsWith(r) || lower.contains(r)) {
        return OperationClass.read;
      }
    }
    return OperationClass.execute;
  }

  /// One-line human summary shown in the table row: tool name plus the
  /// most relevant argument (path / command / headline of the result).
  String get summary {
    if (!ok) {
      final first = response.split('\n').first;
      return first.length > 90 ? '${first.substring(0, 87)}…' : first;
    }
    final args = ToolCall(id: id, name: toolName, argumentsJson: requestJson).args;
    for (final key in ['command', 'path', 'file_path', 'pattern', 'query', 'url']) {
      final v = args[key];
      if (v is String && v.isNotEmpty) {
        final short = v.length > 70 ? '${v.substring(0, 67)}…' : v;
        return short;
      }
    }
    final first = response.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return first.length > 90 ? '${first.substring(0, 87)}…' : first;
  }
}

/// Result strings the engine prefixes onto failed tool calls.
bool _isOkResult(String result) =>
    !result.startsWith('Tool Error:') && !result.startsWith('Denied by user.');

/// Per-source rollup for Zone 2 cards.
class SourceStats {
  SourceStats(this.source);
  final String source;
  int reads = 0;
  int writes = 0;
  int executes = 0;
  int errors = 0;
}

/// Append-only execution telemetry for the session dashboard.
/// Fed from [AppState]'s StepEvent handler; notifies once per event.
class TelemetryStore extends ChangeNotifier {
  final List<ToolExecutionEvent> events = [];
  DateTime? _firstAt;

  /// Context window usage (tokens), mirrored from AppState.contextTokens.
  int contextTokens = 0;
  static const contextCapacity = 200_000;

  void record(AgentStep step) {
    if (step.toolCall == null) return;
    _firstAt ??= DateTime.now();
    events.add(ToolExecutionEvent.fromStep(step));
    notifyListeners();
  }

  /// Rebuild events from a resumed session's message history: assistant
  /// tool_calls paired with tool-role results by call id. Durations and
  /// real timestamps aren't persisted, so both fall back to 0 / restore
  /// time — the table still shows call, class, status, and payloads.
  void restoreFromMessages(List<Message> messages) {
    clear();
    final results = <String, String>{
      for (final m in messages.where((m) => m.role == MessageRole.tool))
        if (m.toolCallId != null) m.toolCallId!: m.content,
    };
    for (final m in messages) {
      if (m.role != MessageRole.assistant) continue;
      for (final c in m.toolCalls ?? const <ToolCall>[]) {
        _firstAt ??= DateTime.now();
        events.add(ToolExecutionEvent(
          id: c.id,
          timestamp: DateTime.now(),
          toolName: c.name,
          source: ToolExecutionEvent._sourceOf(c.name),
          operation: ToolExecutionEvent._classify(c.name),
          ok: _isOkResult(results[c.id] ?? ''),
          requestJson: c.argumentsJson,
          response: results[c.id] ?? '',
          durationMs: 0,
        ));
      }
    }
    notifyListeners();
  }

  void setContextTokens(int value) {
    contextTokens = value;
    notifyListeners();
  }

  void clear() {
    events.clear();
    _firstAt = null;
    contextTokens = 0;
    notifyListeners();
  }

  // ── Zone 1 KPIs ───────────────────────────────────────────────────

  int get totalCalls => events.length;
  int get failedCalls => events.where((e) => !e.ok).length;
  int get succeededCalls => totalCalls - failedCalls;

  double get contextFill =>
      contextCapacity == 0 ? 0 : (contextTokens / contextCapacity).clamp(0.0, 1.0);

  /// Distinct MCP servers + `system` (only if it has any calls).
  List<String> get connectedSystems {
    final set = events.map((e) => e.source).toSet().toList()..sort();
    return set;
  }

  int get mcpServerCount =>
      connectedSystems.where((s) => s.startsWith('mcp:')).length;

  Duration? get elapsed {
    if (events.isEmpty || _firstAt == null) return null;
    return DateTime.now().difference(_firstAt!);
  }

  int? get avgDurationMs {
    if (events.isEmpty) return null;
    return (events.fold<int>(0, (a, e) => a + e.durationMs) / events.length).round();
  }

  // ── Zone 2 per-source rollup ──────────────────────────────────────

  Map<String, SourceStats> get sourceStats {
    final map = <String, SourceStats>{};
    for (final e in events) {
      final s = map.putIfAbsent(e.source, () => SourceStats(e.source));
      switch (e.operation) {
        case OperationClass.read:
          s.reads++;
        case OperationClass.write:
          s.writes++;
        case OperationClass.execute:
          s.executes++;
      }
      if (!e.ok) s.errors++;
    }
    return map;
  }
}
