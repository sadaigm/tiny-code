import 'package:flutter/foundation.dart';

/// Entry types rendered in the stream — same grammar as the TUI.
enum LogEntryType { user, assistant, reasoning, toolCall, toolResult, system, info, error }

class LogEntry {
  LogEntry({required this.type, required this.text, this.toolName, this.meta});

  final LogEntryType type;
  final String text;
  final String? toolName;
  final String? meta;
}

/// A user row, or a group of consecutive non-user entries after one.
class TurnGroup {
  TurnGroup.user(this.userText) : entries = const [];

  TurnGroup.agent(this.entries) : userText = null;

  final String? userText; // non-null → user row
  final List<LogEntry> entries; // agent group body
  bool expanded = true;
}

/// Pure grouping rule (unit-testable, memoizable):
/// system/info/error → loose divider rows; user → own group;
/// consecutive non-user entries → one agent group.
List<TurnGroup> groupEntries(List<LogEntry> entries) {
  final groups = <TurnGroup>[];
  var current = <LogEntry>[];

  void flush() {
    if (current.isNotEmpty) {
      groups.add(TurnGroup.agent(current));
      current = <LogEntry>[];
    }
  }

  for (final e in entries) {
    switch (e.type) {
      case LogEntryType.user:
        flush();
        groups.add(TurnGroup.user(e.text));
      case LogEntryType.system:
      case LogEntryType.info:
      case LogEntryType.error:
        flush();
        current.add(e); // dividers render as their own loose entry group
        flush();
      case LogEntryType.assistant:
      case LogEntryType.reasoning:
      case LogEntryType.toolCall:
      case LogEntryType.toolResult:
        current.add(e);
    }
  }
  flush();
  return groups;
}

/// Structural log state — notifies only on entry add/remove/fold, never on
/// streaming deltas (those live in [StreamingTextNotifier]).
class LogStore extends ChangeNotifier {
  final _entries = <LogEntry>[];

  /// Snapshots: callers may iterate during build while engine events
  /// mutate the underlying lists in the same frame — never expose live
  /// internals (concurrent-modification crashes).
  List<LogEntry> get entries => List.unmodifiable(_entries);

  List<TurnGroup> _groups = [];
  List<TurnGroup> get groups => _groups;

  void add(LogEntry entry) {
    _entries.add(entry);
    _regroup();
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    _folded.clear();
    _regroup();
    notifyListeners();
  }

  /// Replace the entry at [index] — used to merge streaming reasoning
  /// deltas into the tail entry instead of one entry per delta.
  void replaceAt(int index, LogEntry entry) {
    _entries[index] = entry;
    _regroup();
    notifyListeners();
  }

  /// Swap the whole log (session resume).
  void replaceAll(List<LogEntry> entries) {
    _entries
      ..clear()
      ..addAll(entries);
    _regroup();
    notifyListeners();
  }

  void toggleFold(int groupIndex) {
    final g = _groups[groupIndex];
    g.expanded = !g.expanded;
    // Fold state keyed by the group's first entry so _regroup() (which
    // recreates group objects) preserves it.
    if (g.entries.isEmpty) return;
    if (g.expanded) {
      _folded.remove(g.entries.first);
    } else {
      _folded.add(g.entries.first);
    }
    notifyListeners();
  }

  final _folded = <LogEntry>{};

  void _regroup() {
    _groups = groupEntries(_entries);
    for (final g in _groups) {
      if (g.entries.isNotEmpty && _folded.contains(g.entries.first)) {
        g.expanded = false;
      }
    }
  }
}

/// Live streaming text — watched only by the active AgentTurn widget so
/// token deltas never rebuild the list.
class StreamingTextNotifier extends ChangeNotifier {
  StringBuffer _buffer = StringBuffer();
  bool _live = false;

  String get text => _buffer.toString();
  bool get live => _live;

  void begin() {
    _buffer = StringBuffer();
    _live = true;
    notifyListeners();
  }

  void append(String delta) {
    _buffer.write(delta);
    notifyListeners();
  }

  void end() {
    _live = false;
    notifyListeners();
  }
}
