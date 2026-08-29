import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Session persistence at `.tiny-cli/sessions/<id>.json` — same format as
/// tiny-cli, so sessions created in either app open in the other.
class SessionStore {
  SessionStore(this.dir);

  final String dir;

  Future<void> _ensureDir() async {
    try {
      await Directory(dir).create(recursive: true);
    } catch (_) {}
  }

  Future<void> save(Session session) async {
    await _ensureDir();
    await File('$dir/${session.metadata.id}.json')
        .writeAsString(jsonEncode(session.toJson()));
  }

  Future<Session?> load(String id) async {
    try {
      final text = await File('$dir/$id.json').readAsString();
      return Session.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<List<SessionMetadata>> list() async {
    final results = <SessionMetadata>[];
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      return results;
    }
    for (final entry in entries) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final session =
            Session.fromJson(jsonDecode(await entry.readAsString()) as Map<String, dynamic>);
        results.add(session.metadata);
      } catch (_) {
        // Corrupt file — skip.
      }
    }
    results.sort((a, b) => b.lastUpdatedAt.compareTo(a.lastUpdatedAt));
    return results;
  }

  Future<void> delete(String id) async {
    try {
      await File('$dir/$id.json').delete();
    } catch (_) {}
  }
}
