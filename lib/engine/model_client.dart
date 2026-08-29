import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Interface the agent loop depends on — lets tests inject a fake model.
abstract class IModelClient {
  Future<ModelResponse> chat(
    List<Message> messages,
    List<ToolDefinition> tools, {
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
    Future<void> Function()? abortSignal,
  });

  Future<ModelResponse> chatSync(List<Message> messages);
}

/// OpenAI-compatible streaming chat-completions client.
/// Pure Dart — no Flutter imports.
class ModelClient implements IModelClient {
  ModelClient(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final AgentConfig config;
  final http.Client _client;

  @override
  Future<ModelResponse> chat(
    List<Message> messages,
    List<ToolDefinition> tools, {
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
    Future<void> Function()? abortSignal,
  }) {
    return _chat(
      messages,
      tools,
      stream: true,
      onText: onText,
      onReasoning: onReasoning,
      abortSignal: abortSignal,
    );
  }

  /// Non-streaming variant (used for compaction summaries).
  @override
  Future<ModelResponse> chatSync(List<Message> messages) {
    return _chat(messages, const [], stream: false);
  }

  Future<ModelResponse> _chat(
    List<Message> messages,
    List<ToolDefinition> tools, {
    required bool stream,
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
    Future<void> Function()? abortSignal,
  }) async {
    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages.map((m) => m.toWire()).toList(),
      'stream': stream,
    };
    if (config.temperature != null) body['temperature'] = config.temperature;
    if (tools.isNotEmpty) body['tools'] = tools.map((t) => t.toWire()).toList();

    final uri = _chatUri();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (config.apiKey != null) 'Authorization': 'Bearer ${config.apiKey}',
    };

    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    debugPrint('[model] POST $uri');
    debugPrint('[model] headers: ${headers.keys.toList()}');
    debugPrint('[model] payload: ${request.body}');

    final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(Duration(milliseconds: config.requestTimeoutMs));
    } on TimeoutException catch (e) {
      throw ModelException.timeout(e.toString());
    } catch (e) {
      // Connection refused / network errors — surface as ModelException so
      // the retry/abort paths in Agent handle them.
      throw ModelException.http(0, '$e');
    }

    if (response.statusCode != 200) {
      final text = await response.stream.bytesToString();
      throw ModelException.http(response.statusCode, text);
    }

    if (!stream) {
      final json =
          jsonDecode(await response.stream.bytesToString()) as Map<String, dynamic>;
      return _decodeComplete(json);
    }

    return _readSse(response, onText, onReasoning, abortSignal);
  }

  Uri _chatUri() {
    final base = config.endpoint.replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/chat/completions')) return Uri.parse(base);
    return Uri.parse('$base/chat/completions');
  }

  Future<ModelResponse> _readSse(
    http.StreamedResponse response,
    void Function(String)? onText,
    void Function(String)? onReasoning,
    Future<void> Function()? abortSignal,
  ) async {
    final content = StringBuffer();
    // Tool-call fragments: index → {id, name, args buffer}.
    final fragments = <int, _ToolFragment>{};

    StreamSubscription<String>? sub;
    final done = Completer<void>();

    if (abortSignal != null) {
      // Caller-driven abort: cancel the subscription; the future below
      // completes with whatever was accumulated.
      unawaited(abortSignal().then((_) {
        sub?.cancel();
        if (!done.isCompleted) done.complete();
      }));
    }

    sub = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (!line.startsWith('data:')) return;
      // Strip "data:" plus any optional space(s) — servers emit both
      // "data: {...}" and "data:{...}".
      final data = line.replaceFirst(RegExp(r'^data:\s*'), '').trim();
      if (data.isEmpty || data == '[DONE]') {
        if (data == '[DONE]' && !done.isCompleted) done.complete();
        return;
      }
      final json = tryJsonMap(data);
      if (json == null) return;
      final delta =
          (json['choices'] as List<dynamic>?)?[0]?['delta'] as Map<String, dynamic>?;
      if (delta == null) return;

      final reasoning = delta['reasoning_content'] as String? ?? '';
      if (reasoning.isNotEmpty && onReasoning != null) onReasoning(reasoning);

      final text = delta['content'] as String? ?? '';
      if (text.isNotEmpty) {
        content.write(text);
        onText?.call(text);
      }

      final calls = delta['tool_calls'] as List<dynamic>?;
      if (calls != null) {
        for (final raw in calls) {
          final c = raw as Map<String, dynamic>;
          final index = c['index'] as int? ?? 0;
          final frag = fragments.putIfAbsent(index, _ToolFragment.new);
          final fn = c['function'] as Map<String, dynamic>?;
          if (c['id'] != null) frag.id = c['id'] as String;
          if (fn?['name'] != null) frag.name = fn!['name'] as String;
          if (fn?['arguments'] != null) {
            frag.args.write(fn!['arguments'] as String);
          }
        }
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    });

    await done.future;

    final calls = fragments.values
        .where((f) => f.name != null)
        .map((f) => ToolCall(
              id: f.id ?? '',
              name: f.name!,
              argumentsJson: f.args.toString(),
            ))
        .toList();

    return ModelResponse(content: content.toString(), toolCalls: calls);
  }

  ModelResponse _decodeComplete(Map<String, dynamic> json) {
    final choice = (json['choices'] as List<dynamic>)[0] as Map<String, dynamic>;
    final msg = choice['message'] as Map<String, dynamic>;
    final calls = (msg['tool_calls'] as List<dynamic>? ?? [])
        .map((raw) {
          final c = raw as Map<String, dynamic>;
          final fn = c['function'] as Map<String, dynamic>;
          return ToolCall(
            id: c['id'] as String,
            name: fn['name'] as String,
            argumentsJson: fn['arguments'] as String,
          );
        })
        .toList();
    return ModelResponse(content: msg['content'] as String? ?? '', toolCalls: calls);
  }

  void close() => _client.close();
}

class _ToolFragment {
  String? id;
  String? name;
  final StringBuffer args = StringBuffer();
}

Map<String, dynamic>? tryJsonMap(String s) {
  try {
    final v = jsonDecode(s);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

class ModelException implements Exception {
  ModelException.http(this.status, this.body);
  ModelException.timeout(this.body) : status = 0;

  final int status;
  final String body;

  bool get isTimeout => status == 0;

  @override
  String toString() =>
      isTimeout ? 'Request timed out: $body' : 'HTTP $status: $body';
}
