/// Engine data model — pure Dart, no Flutter imports.
/// Mirrors the behavioral spec (packages/core types.ts) but written fresh.
library;

import 'dart:convert' show jsonDecode;

enum MessageRole { system, user, assistant, tool }

class ToolCall {
  ToolCall({required this.id, required this.name, required this.argumentsJson});

  final String id;
  final String name;
  final String argumentsJson;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'arguments': argumentsJson};

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String,
        argumentsJson: json['arguments'] as String,
      );

  /// Parsed arguments; malformed JSON yields an empty map (never throws —
  /// matches the gating pass behavior in the spec).
  Map<String, dynamic> get args {
    if (_argsCache == null) {
      final decoded = tryParseJson(argumentsJson);
      _argsCache = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    }
    return _argsCache!;
  }

  Map<String, dynamic>? _argsCache;
}

dynamic tryParseJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

class Message {
  Message({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
  });

  final MessageRole role;
  final String content;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final String? name;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        if (toolCalls != null)
          'tool_calls': toolCalls!
              .map((c) => {
                    'id': c.id,
                    'type': 'function',
                    'function': {'name': c.name, 'arguments': c.argumentsJson},
                  })
              .toList(),
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null) 'name': name,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        role: MessageRole.values.byName(json['role'] as String),
        content: json['content'] as String,
        toolCalls: (json['tool_calls'] as List<dynamic>?)
            ?.map((c) => ToolCall.fromJson({
                  'id': c['id'],
                  'name': c['function']['name'],
                  'arguments': c['function']['arguments'],
                }))
            .toList(),
        toolCallId: json['tool_call_id'] as String?,
        name: json['name'] as String?,
      );

  Map<String, dynamic> toWire() => toJson();
}

class ToolDefinition {
  ToolDefinition({
    required this.name,
    required this.description,
    required this.parametersSchema,
    this.isModifying = false,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;
  final bool isModifying;

  Map<String, dynamic> toWire() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parametersSchema,
        },
      };
}

class ToolResult {
  ToolResult({required this.toolCallId, required this.content});

  final String toolCallId;
  final String content;

  Message toMessage() => Message(
        role: MessageRole.tool,
        content: content,
        toolCallId: toolCallId,
      );
}

enum PermissionMode { notify, autoEdit, auto }

enum AgentMode { agent, chat, plan }

class McpServerConfig {
  McpServerConfig({
    required this.name,
    required this.type,
    this.command,
    this.args,
    this.env,
    this.url,
  });

  final String name;
  final McpTransport type; // stdio | http
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? url;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        if (command != null) 'command': command,
        if (args != null) 'args': args,
        if (env != null) 'env': env,
        if (url != null) 'url': url,
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        name: json['name'] as String,
        type: McpTransport.values.byName(json['type'] as String),
        command: json['command'] as String?,
        args: (json['args'] as List<dynamic>?)?.cast<String>(),
        env: (json['env'] as Map<String, dynamic>?)?.cast<String, String>(),
        url: json['url'] as String?,
      );
}

enum McpTransport { stdio, http }

class AgentConfig {
  AgentConfig({
    required this.endpoint,
    required this.model,
    this.apiKey,
    this.temperature,
    this.prompts = const {},
    this.mcpServers = const [],
    this.permissionMode = PermissionMode.notify,
    this.requestTimeoutMs = 120000,
    this.maxIterations = 25,
    this.compactionThresholdTokens = 35000,
    this.compactionRetainTokens = 8000,
    this.activeSkills = const [],
    this.sessionId,
    this.cwd = '.',
  });

  final String endpoint;
  final String? apiKey;
  final String model;
  final double? temperature;
  final Map<String, String> prompts; // per-mode overrides: agent/chat/plan
  final List<McpServerConfig> mcpServers;
  final PermissionMode permissionMode;
  final int requestTimeoutMs;
  final int maxIterations;
  final int compactionThresholdTokens;
  final int compactionRetainTokens;
  final List<String> activeSkills;
  final String? sessionId;
  final String cwd;

  AgentConfig copyWith({
    String? endpoint,
    String? apiKey,
    String? model,
    double? temperature,
    List<McpServerConfig>? mcpServers,
    PermissionMode? permissionMode,
    String? sessionId,
    List<String>? activeSkills,
  }) =>
      AgentConfig(
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        prompts: prompts,
        mcpServers: mcpServers ?? this.mcpServers,
        permissionMode: permissionMode ?? this.permissionMode,
        requestTimeoutMs: requestTimeoutMs,
        maxIterations: maxIterations,
        compactionThresholdTokens: compactionThresholdTokens,
        compactionRetainTokens: compactionRetainTokens,
        activeSkills: activeSkills ?? this.activeSkills,
        sessionId: sessionId ?? this.sessionId,
        cwd: cwd,
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'model': model,
        'mcpServers': mcpServers.map((s) => s.toJson()).toList(),
        'permissionMode': permissionMode.name,
      };
}

class AgentStep {
  AgentStep({
    required this.thought,
    this.toolCall,
    this.toolResult,
    this.modelChatMs,
    this.toolCallMs,
  });

  final String thought;
  final ToolCall? toolCall;
  final String? toolResult;
  final int? modelChatMs;
  final int? toolCallMs;
}

class AskUserQuestion {
  AskUserQuestion({required this.question, required this.options});

  final String question;
  final List<String> options;
}

class AskUserPayload {
  AskUserPayload({this.context, required this.questions});

  final String? context;
  final List<AskUserQuestion> questions;
}

class AskUserAnswer {
  AskUserAnswer({required this.question, required this.selected});

  final String question;
  final String selected;
}

class AskUserResponse {
  AskUserResponse.answered(this.answers) : skipped = false;
  AskUserResponse.skipped() : answers = null, skipped = true;

  final List<AskUserAnswer>? answers;
  final bool skipped;
}

class ModelResponse {
  ModelResponse({required this.content, this.toolCalls = const []});

  final String content;
  final List<ToolCall> toolCalls;
}

class SessionMetadata {
  SessionMetadata({
    required this.id,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.title,
    this.permissionMode,
  });

  final String id;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final String? title;
  final PermissionMode? permissionMode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
        if (title != null) 'title': title,
        if (permissionMode != null) 'permissionMode': permissionMode!.name,
      };

  factory SessionMetadata.fromJson(Map<String, dynamic> json) =>
      SessionMetadata(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastUpdatedAt: DateTime.parse(json['lastUpdatedAt'] as String),
        title: json['title'] as String?,
        permissionMode: json['permissionMode'] == null
            ? null
            : PermissionMode.values.byName(json['permissionMode'] as String),
      );
}

class Session {
  Session({required this.metadata, required this.messages});

  SessionMetadata metadata;
  List<Message> messages;

  Map<String, dynamic> toJson() =>
      {'metadata': metadata.toJson(), 'messages': messages.map((m) => m.toJson()).toList()};

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        metadata: SessionMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
        messages: (json['messages'] as List<dynamic>)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}
