import 'dart:async';

import 'models.dart';

/// Global gate: one mutating tool call runs at a time.
class MutationGate {
  bool _locked = false;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (!_locked) {
      _locked = true;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // hand off to the next waiter
    } else {
      _locked = false;
    }
  }
}

/// Per-key serialization. Same key waits; different keys run in parallel.
class MutexMap {
  final _held = <String>{};
  final _waiters = <String, List<Completer<void>>>{};

  Future<void> acquire(String key) {
    if (_held.add(key)) return Future.value(); // false = already held
    final c = Completer<void>();
    _waiters.putIfAbsent(key, () => []).add(c);
    return c.future;
  }

  /// Hands the lock to the next waiter (if any) — the key stays held.
  void release(String key) {
    final q = _waiters[key];
    if (q == null || q.isEmpty) {
      _held.remove(key);
      return;
    }
    q.removeAt(0).complete();
  }
}

const bashLock = '__bash__';
const askUserLock = '__ask_user__';
const planLock = '__plan__';
const memoryLock = '__memory__';

/// All MCP tool calls serialize against each other.
const mcpLock = '__mcp__';

const _readOnlyTools = {'read', 'list', 'grep', 'glob'};

/// null → read-only, bypass all coordination. A lock key otherwise.
String? classifyLockKey(String name, Map<String, dynamic> args) {
  if (_readOnlyTools.contains(name)) return null;
  if (name.startsWith('mcp__')) return mcpLock;
  switch (name) {
    case 'bash':
      return bashLock;
    case 'ask_user':
      return askUserLock;
    case 'plan_write':
    case 'manage_tasks':
    case 'mark_task_complete':
      return planLock;
    case 'memory':
    case 'create_skill':
      return memoryLock;
    case 'write':
    case 'search_replace':
    case 'insert_lines':
      final p = args['path'] as String?;
      return p == null ? name : 'path:$p';
    default:
      return name;
  }
}

/// [startMs, endMs] window of one execution; for concurrency stats.
class ExecWindow {
  ExecWindow(this.name, this.startMs, this.endMs);

  final String name;
  final int startMs;
  final int endMs;
}

/// Max number of windows overlapping at any instant.
int computeMaxConcurrency(List<ExecWindow> windows) {
  if (windows.isEmpty) return 0;
  final events = <(int, int)>[
    for (final w in windows) (w.startMs, 1),
    for (final w in windows) (w.endMs, -1),
  ]..sort((a, b) {
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      return a.$2.compareTo(b.$2); // ends before starts at the same ms
    });
  var cur = 0;
  var max = 0;
  for (final e in events) {
    cur += e.$2;
    if (cur > max) max = cur;
  }
  return max;
}

String toolLabel(ToolCall call) => '${call.name} ${call.argumentsJson}';
