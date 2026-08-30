import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../tools/registry.dart';

/// Minimal MCP stdio client: newline-delimited JSON-RPC over the server's
/// stdin/stdout. One child process per configured server, owned by the
/// engine isolate (async I/O — no dedicated isolate needed, same
/// simplification as the bash tool). Tools surface as `mcp__<server>__<tool>`.
class McpManager {
  McpManager({this.cwd = '.'});

  /// Working directory for spawned stdio servers (the workspace).
  final String cwd;

  final Map<String, _ConnectedServer> _servers = {};

  /// All configured servers (by name) — includes ones that failed to
  /// connect, so the picker can show them as offline instead of dropping
  /// them silently.
  final Map<String, McpServerConfig> _configured = {};

  /// Last user-chosen enabled state per server name — survives disconnects
  /// so the picker's toggle reflects reality for offline servers too.
  final Map<String, bool> _enabled = {};

  /// Connect all configured stdio servers and register their tools.
  /// Connect all configured servers (stdio + http) and register their tools.
  Future<void> connectAll(
      List<McpServerConfig> configs, ToolRegistry registry) async {
    for (final c in configs) {
      _configured[c.name] = c;
      _enabled[c.name] = true;
      try {
        await _connect(c, registry);
      } catch (e) {
        // Unreachable server — kept in _configured so the picker shows it
        // as offline; enabling it retries the connection.
        debugPrint('[mcp] connect failed for "${c.name}" (${c.type.name}): $e');
      }
    }
  }

  /// Re-register existing connections into a fresh registry (new Agent) —
  /// no reconnection, processes stay alive.
  void registerInto(ToolRegistry registry) {
    for (final server in _servers.values) {
      if (!server.enabled) continue;
      for (final t in server.remoteTools) {
        registry.register(t.definition, (args, ctx) => _callTool(
            server.config.name, t.remoteName, args));
      }
    }
  }

  /// Snapshot for the /mcp picker. Configured servers that failed to
  /// connect appear with `connected: false` so the UI can label them.
  List<Map<String, dynamic>> describe() => [
        for (final s in _servers.values)
          {
            'name': s.config.name,
            'enabled': s.enabled,
            'toolCount': s.remoteTools.length,
            'connected': true,
            'tools': [
              for (final t in s.remoteTools)
                {
                  'name': t.remoteName,
                  'description':
                      t.definition.description.replaceFirst('[${s.config.name}] ', ''),
                }
            ],
          },
        for (final e in _configured.entries)
          if (!_servers.containsKey(e.key))
            {
              'name': e.key,
              'enabled': _enabled[e.key] ?? true,
              'toolCount': 0,
              'connected': false,
              'tools': const <Map<String, dynamic>>[],
            },
      ];

  Future<void> _connect(McpServerConfig c, ToolRegistry registry) async {
    final _ConnectedServer server;
    if (c.type == McpTransport.http) {
      server = _ConnectedServer.http(c);
    } else {
      final process = await Process.start(
        c.command!,
        c.args ?? const [],
        environment: c.env,
        workingDirectory: cwd,
      );
      server = _ConnectedServer.stdio(c, process);
      server.listen(); // must be attached before the first request
    }
    _servers[c.name] = server;
    // Respect the user's last toggle: reconnecting a disabled server
    // must not silently re-enable its tools.
    server.enabled = _enabled[c.name] ?? true;

    final init = await server.request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'tiny-code', 'version': '1.0'},
    });
    if (init != null) server.notify('notifications/initialized');

    final toolsResult = await server.request('tools/list', {});
    if (toolsResult == null) return;
    for (final t in (toolsResult['tools'] as List<dynamic>? ?? [])) {
      final tool = t as Map<String, dynamic>;
      final remoteName = tool['name'] as String;
      final localName = 'mcp__${c.name}__$remoteName';
      final schema = (tool['inputSchema'] as Map<String, dynamic>?) ??
          {'type': 'object', 'properties': {}};
      final definition = ToolDefinition(
        name: localName,
        description:
            '[${c.name}] ${tool['description'] as String? ?? remoteName}',
        parametersSchema: schema,
      );
      server.remoteTools.add(_RemoteTool(remoteName, definition));
      if (server.enabled) {
        registry.register(
            definition, (args, ctx) => _callTool(c.name, remoteName, args));
      }
    }
  }

  Future<String> _callTool(
      String serverName, String remoteName, Map<String, dynamic> args) async {
    final server = _servers[serverName];
    if (server == null || !server.enabled) {
      return 'Tool Error: MCP server "$serverName" is not connected.';
    }
    final result = await server.request('tools/call', {
      'name': remoteName,
      'arguments': args,
    });
    if (result == null) return 'Tool Error: no response from $serverName.';
    if (result['isError'] == true) {
      return 'Tool Error: ${_textContent(result)}';
    }
    return _textContent(result);
  }

  static String _textContent(Map<String, dynamic> result) {
    final content = result['content'] as List<dynamic>? ?? [];
    return content
        .whereType<Map<String, dynamic>>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String? ?? '')
        .join('\n');
  }

  /// Enable/disable a server: disabled tools are removed from the registry so
  /// they vanish from the next turn's definitions. Enabling a configured
  /// server that isn't connected (failed at startup) retries the connect.
  /// Re-enabling a connected server re-fetches tools/list first, so tools
  /// added on the server while disabled are picked up.
  Future<void> setEnabled(
      String name, bool enabled, ToolRegistry registry) async {
    _enabled[name] = enabled; // remember the choice even if offline
    var server = _servers[name];
    if (server == null) {
      final c = _configured[name];
      if (!enabled || c == null) return;
      try {
        await _connect(c, registry);
        server = _servers[name];
      } catch (e) {
        debugPrint('[mcp] reconnect failed for "$name": $e');
        return; // still offline; picker keeps showing it as offline
      }
    }
    final s = server;
    if (s == null) return;
    s.enabled = enabled;
    if (!enabled) {
      for (final t in s.remoteTools) {
        registry.unregister(t.definition.name);
      }
    } else {
      await _refreshTools(s, registry);
      for (final t in s.remoteTools) {
        registry.register(
            t.definition,
            (args, ctx) =>
                _callTool(s.config.name, t.remoteName, args));
      }
    }
  }

  /// Hard reconnect (picker "Reconnect"): kill the child process and run a
  /// fresh connect + tools/list. Tools added/removed server-side show up
  /// here. Leaves the server offline if the reconnect fails.
  Future<void> reconnect(String name, ToolRegistry registry) async {
    final old = _servers.remove(name);
    old?.process?.kill();
    final c = _configured[name];
    if (c == null) return;
    try {
      await _connect(c, registry);
    } catch (e) {
      debugPrint('[mcp] reconnect failed for "$name": $e');
    }
  }

  /// Remove a server entirely: kill the connection, unregister its tools,
  /// forget config and enabled state.
  Future<void> delete(String name, ToolRegistry registry) async {
    final server = _servers.remove(name);
    if (server != null) {
      for (final t in server.remoteTools) {
        registry.unregister(t.definition.name);
      }
      server.process?.kill();
      if (server.url != null) server.disposeHttpClient();
    }
    _configured.remove(name);
    _enabled.remove(name);
  }

  /// Re-fetch tools/list and diff against the registered set: unregister
  /// tools that disappeared server-side, add new ones to [remoteTools].
  /// Registration itself is the caller's job.
  Future<void> _refreshTools(
      _ConnectedServer server, ToolRegistry registry) async {
    final toolsResult = await server.request('tools/list', {});
    if (toolsResult == null) return; // request failed — keep the old list
    final fresh = <_RemoteTool>[];
    for (final t in (toolsResult['tools'] as List<dynamic>? ?? [])) {
      final tool = t as Map<String, dynamic>;
      final remoteName = tool['name'] as String;
      final localName = 'mcp__${server.config.name}__$remoteName';
      final schema = (tool['inputSchema'] as Map<String, dynamic>?) ??
          {'type': 'object', 'properties': {}};
      fresh.add(_RemoteTool(
          remoteName,
          ToolDefinition(
            name: localName,
            description:
                '[${server.config.name}] ${tool['description'] as String? ?? remoteName}',
            parametersSchema: schema,
          )));
    }
    // Unregister tools that no longer exist server-side.
    for (final t in server.remoteTools) {
      if (!fresh.any((f) => f.remoteName == t.remoteName)) {
        registry.unregister(t.definition.name);
      }
    }
    server.remoteTools
      ..clear()
      ..addAll(fresh);
  }

  Future<void> dispose() async {
    for (final s in _servers.values) {
      s.process?.kill();
      if (s.url != null) s.disposeHttpClient();
    }
    _servers.clear();
  }
}

class _RemoteTool {
  _RemoteTool(this.remoteName, this.definition);

  final String remoteName;
  final ToolDefinition definition;
}

class _ConnectedServer {
  _ConnectedServer.stdio(this.config, this.process) : url = null;
  _ConnectedServer.http(McpServerConfig c)
      : config = c,
        process = null,
        url = Uri.parse(c.url!) {
    _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  }

  final McpServerConfig config;
  final Process? process; // null for http transport
  final Uri? url; // null for stdio transport
  final remoteTools = <_RemoteTool>[];
  bool enabled = true;
  int _nextId = 1;
  final _pending = <int, Completer<Map<String, dynamic>?>>{};
  late final HttpClient _httpClient;
  String? _sessionId; // Mcp-Session-Id from the initialize response

  bool get _isHttp => url != null;

  Future<Map<String, dynamic>?> request(
      String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    if (_isHttp) {
      return _httpRequest({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }).timeout(const Duration(seconds: 30), onTimeout: () => null);
    }
    final completer = Completer<Map<String, dynamic>?>();
    _pending[id] = completer;
    process!.stdin.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }));
    // A hung server must not block the engine forever.
    return await completer.future
        .timeout(const Duration(seconds: 30), onTimeout: () {
      _pending.remove(id);
      return null;
    });
  }

  /// Streamable HTTP: POST one JSON-RPC message, parse a JSON or SSE body.
  Future<Map<String, dynamic>?> _httpRequest(Map<String, dynamic> msg) async {
    final request = await _httpClient.postUrl(url!)
      ..headers.contentType = ContentType.json
      ..headers.set('Accept', 'application/json, text/event-stream');
    if (_sessionId != null) {
      request.headers.set('Mcp-Session-Id', _sessionId!);
    }
    request.write(jsonEncode(msg));
    final response = await request.close();
    final sessionId = response.headers.value('mcp-session-id');
    if (sessionId != null) _sessionId = sessionId;
    final contentType = response.headers.contentType?.mimeType ?? '';
    if (response.statusCode >= 400) {
      await response.drain();
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    if (contentType.contains('text/event-stream')) {
      Map<String, dynamic>? result;
      for (final line in body.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        try {
          final decoded = jsonDecode(data) as Map<String, dynamic>;
          if (decoded.containsKey('id')) result = decoded;
        } catch (_) {}
      }
      return result?['result'] as Map<String, dynamic>?;
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic> && decoded.containsKey('result')) {
      return decoded['result'] as Map<String, dynamic>?;
    }
    return null;
  }

  void disposeHttpClient() {
    _httpClient.close();
  }

  void notify(String method) {
    if (_isHttp) {
      // Fire-and-forget; the response (202/200) carries no result.
      _httpRequest({'jsonrpc': '2.0', 'method': method}).catchError((_) => null);
      return;
    }
    process!.stdin.writeln(jsonEncode({'jsonrpc': '2.0', 'method': method}));
  }

  /// Wire stdout into pending request completers. Call once after connect.
  void listen() {
    if (process == null) return; // http transport has no stream to listen to
    process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.isEmpty) return;
          try {
            final msg = jsonDecode(line) as Map<String, dynamic>;
            final id = msg['id'] as int?;
            if (id == null) return; // notification from server — ignored
            final completer = _pending.remove(id);
            if (completer == null || completer.isCompleted) return;
            completer.complete(msg['result'] as Map<String, dynamic>? ?? {});
          } catch (_) {}
        }, onDone: () {
          for (final c in _pending.values) {
            if (!c.isCompleted) c.complete(null);
          }
          _pending.clear();
        });
    process!.stderr.drain();
  }
}
