import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Fixed-size pool of isolates doing CPU-bound file walks (grep/glob),
/// so large trees never block the engine or UI isolate.
class FileWorkerPool {
  FileWorkerPool({this.size = 2});

  final int size;
  final _workers = <_Worker>[];
  var _next = 0;

  Future<Map<String, dynamic>> run(Map<String, dynamic> request) async {
    if (_workers.isEmpty) {
      for (var i = 0; i < size; i++) {
        _workers.add(await _Worker.spawn());
      }
    }
    // Round-robin — cheap and adequate for this workload.
    return _workers[_next++ % _workers.length].run(request);
  }

  void dispose() {
    for (final w in _workers) {
      w.kill();
    }
    _workers.clear();
  }
}

class _Worker {
  _Worker._(this._isolate, this._sendPort, this._receivePort);

  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _seq = 0;

  static Future<_Worker> spawn() async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_workerMain, port.sendPort);
    final ready = Completer<SendPort>();
    late final _Worker worker;
    // All messages (handshake + replies) arrive on this one port.
    port.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
        return;
      }
      final m = msg as Map;
      final completer = worker._pending.remove(m['id']);
      if (m['error'] != null) {
        completer?.completeError(StateError(m['error'] as String));
      } else {
        completer?.complete(Map<String, dynamic>.from(m['result'] as Map));
      }
    });
    final sendPort = await ready.future;
    worker = _Worker._(isolate, sendPort, port);
    return worker;
  }

  Future<Map<String, dynamic>> run(Map<String, dynamic> request) {
    final id = _seq++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _sendPort.send({'id': id, ...request});
    return completer.future;
  }

  void kill() {
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
  }
}

void _workerMain(SendPort sendPort) {
  final port = ReceivePort();
  sendPort.send(port.sendPort);
  port.listen((msg) {
    final m = msg as Map;
    try {
      sendPort.send({'id': m['id'], 'result': _handle(m)});
    } catch (e) {
      sendPort.send({'id': m['id'], 'error': e.toString()});
    }
  });
}

Map<String, dynamic> _handle(Map m) {
  switch (m['op'] as String) {
    case 'grep':
      return {'matches': _grep(m['root'] as String, m['pattern'] as String,
          m['isRegex'] as bool? ?? false, m['maxResults'] as int? ?? 100)};
    case 'glob':
      return {'files': _glob(m['root'] as String, m['pattern'] as String,
          m['maxResults'] as int? ?? 200)};
    default:
      throw StateError('unknown op ${m['op']}');
  }
}

const _skipDirs = {'.git', 'node_modules', 'build', '.dart_tool', '.idea'};

List<String> _grep(String root, String pattern, bool isRegex, int maxResults) {
  final results = <String>[];
  final needle = pattern.toLowerCase();
  RegExp? regex;
  if (isRegex) regex = RegExp(pattern);
  _walk(root, (file) {
    if (results.length >= maxResults) return;
    try {
      final lines = File(file).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final hit = regex != null ? regex.hasMatch(line) : line.toLowerCase().contains(needle);
        if (hit) {
          results.add('$file:${i + 1}: $line'.trimRight());
          if (results.length >= maxResults) return;
        }
      }
    } catch (_) {
      // Binary/unreadable — skip.
    }
  });
  return results;
}

List<String> _glob(String root, String pattern, int maxResults) {
  final results = <String>[];
  final regex = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', '[^/]*').replaceAll(r'\?', '.')}\$');
  _walk(root, (file) {
    if (results.length >= maxResults) return;
    final rel = file.startsWith('$root/') ? file.substring(root.length + 1) : file;
    if (regex.hasMatch(rel)) results.add(rel);
  });
  return results;
}

void _walk(String root, void Function(String file) onFile) {
  final dir = Directory(root);
  if (!dir.existsSync()) return;
  final stack = <Directory>[dir];
  while (stack.isNotEmpty) {
    final d = stack.removeLast();
    for (final entity in d.listSync(followLinks: false)) {
      final name = entity.path.split(RegExp(r'[/\\]')).last;
      if (entity is Directory) {
        if (!_skipDirs.contains(name)) stack.add(entity);
      } else if (entity is File) {
        onFile(entity.path);
      }
    }
  }
}
