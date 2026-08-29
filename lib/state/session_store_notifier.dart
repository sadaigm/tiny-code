import 'package:flutter/foundation.dart';

import '../engine/models.dart';
import '../engine/session_store.dart';

/// Sidebar session state: the persisted session list, search filter, active
/// id, and Today/Yesterday/This-week grouping.
class SessionStoreNotifier extends ChangeNotifier {
  SessionStoreNotifier(this._store) {
    refresh();
  }

  final SessionStore _store;

  final List<SessionMetadata> _all = [];
  String _query = '';
  String? activeId;

  String get query => _query;

  set query(String q) {
    _query = q;
    notifyListeners();
  }

  List<SessionMetadata> get filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all
        .where((s) => (s.title ?? 'untitled').toLowerCase().contains(q))
        .toList();
  }

  /// Group label → sessions, dropping empty groups. Oldest last.
  Map<String, List<SessionMetadata>> grouped(DateTime now) {
    final today = <SessionMetadata>[];
    final yesterday = <SessionMetadata>[];
    final thisWeek = <SessionMetadata>[];
    final older = <SessionMetadata>[];
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));
    for (final s in filtered) {
      final t = s.lastUpdatedAt;
      if (!t.isBefore(todayStart)) {
        today.add(s);
      } else if (!t.isBefore(yesterdayStart)) {
        yesterday.add(s);
      } else if (!t.isBefore(weekStart)) {
        thisWeek.add(s);
      } else {
        older.add(s);
      }
    }
    return {
      if (today.isNotEmpty) 'TODAY': today,
      if (yesterday.isNotEmpty) 'YESTERDAY': yesterday,
      if (thisWeek.isNotEmpty) 'THIS WEEK': thisWeek,
      if (older.isNotEmpty) 'OLDER': older,
    };
  }

  Future<void> refresh() async {
    _all
      ..clear()
      ..addAll(await _store.list());
    notifyListeners();
  }

  Future<Session?> open(String id) => _store.load(id);

  void setActive(String? id) {
    activeId = id;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    if (activeId == id) activeId = null;
    await refresh();
  }
}
