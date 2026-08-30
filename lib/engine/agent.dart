import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'compact.dart';
import '../platform_env_io.dart' show homeDir;
import 'concurrency.dart';
import 'file_worker.dart';
import 'instructions.dart';
import 'memory.dart';
import 'model_client.dart';
import 'models.dart';
import 'prompts/prompts.dart';
import 'skills.dart';
import 'tools/bash_tool.dart';
import 'tools/edit_tools.dart';
import 'tools/fs_tools.dart';
import 'tools/memory_tools.dart';
import 'tools/plan_tools.dart';
import 'tools/registry.dart';
import 'tools/search_tools.dart';
import 'tools/bash_redirect.dart';

/// Callbacks the UI subscribes to. The isolate host turns these into events.
class AgentCallbacks {
  const AgentCallbacks({
    this.onStep,
    this.onText,
    this.onReasoning,
    this.onModelError,
    this.onApproval,
    this.onAskUser,
    this.onCompaction,
  });

  final void Function(AgentStep step)? onStep;
  final void Function(String delta)? onText;
  final void Function(String delta)? onReasoning;
  final void Function(Object error)? onModelError;
  final void Function(int beforeTokens, int afterTokens)? onCompaction;
  /// Return false to deny. May flip permission mode via [ApprovalDecision].
  final Future<ApprovalDecision?> Function(ToolCall call)? onApproval;
  final Future<AskUserResponse> Function(AskUserPayload payload)? onAskUser;
}

class ApprovalDecision {
  const ApprovalDecision({required this.approved, this.sessionAlways = false});

  final bool approved;
  final bool sessionAlways;
}

class AgentRunResult {
  AgentRunResult({required this.content, required this.steps, this.streamedFinal = false, this.maxConcurrency = 1});

  final String content;
  final List<AgentStep> steps;
  final bool streamedFinal;
  final int maxConcurrency;
}

/// The agent loop: message → model → gated concurrent tool batch → repeat.
class Agent {
  Agent(this.config, {IModelClient? modelClient, FileWorkerPool? filePool})
      : model = modelClient ?? ModelClient(config),
        filePool = filePool ?? FileWorkerPool(),
        registry = ToolRegistry() {
    _registerAllTools();
  }

  final AgentConfig config;
  final IModelClient model;
  final FileWorkerPool filePool;
  final ToolRegistry registry;
  final RedirectTracker redirects = RedirectTracker();

  List<Message> messages = [];
  PermissionMode _permissionMode = PermissionMode.notify;

  /// Runtime permission-mode change (`/mode <mode>`).
  void setPermissionMode(PermissionMode mode) => _permissionMode = mode;

  PermissionMode get permissionMode => _permissionMode;
  bool _aborted = false;

  void setHistory(List<Message> history) => messages = [...history];
  List<Message> getHistory() => messages;

  /// Exec windows across the whole session — `/usage` stats source.
  final List<ExecWindow> execWindows = [];

  Map<String, dynamic> usageStats() {
    final counts = <String, int>{};
    for (final w in execWindows) {
      counts[w.name] = (counts[w.name] ?? 0) + 1;
    }
    return {
      'contextTokens': estimateTokens(messages),
      'toolCounts': counts,
      'redirects': redirects.counts,
      'maxConcurrency': computeMaxConcurrency(execWindows),
    };
  }

  /// Request-response interrupt: flips on the next loop check and cancels
  /// the in-flight model request via its abort hook.
  Completer<void>? _abortCompleter;

  void interrupt() {
    _aborted = true;
    _abortCompleter?.complete();
  }

  void _registerAllTools() {
    registerFsTools(registry);
    registerBashTool(registry);
    registerEditTools(registry);
    registerPlanTools(registry);
    registerMemoryTools(registry);
    registerSearchTools(registry, filePool);
    registerAskUser(registry, _askUserHandler);
  }

  Future<String> _askUserHandler(Map<String, dynamic> args, ToolContext ctx) async {
    final questions = (args['questions'] as List<dynamic>? ?? [])
        .map((q) => AskUserQuestion(
              question: (q as Map<String, dynamic>)['question'] as String,
              options: ((q['options'] as List<dynamic>?) ?? const []).cast<String>(),
            ))
        .toList();
    if (ctx.askUser == null) return 'No user available to ask.';
    final response = await ctx.askUser!(AskUserPayload(
      context: args['context'] as String?,
      questions: questions,
    ));
    if (response.skipped || response.answers == null) return 'User skipped the questions.';
    return response.answers!
        .map((a) => '${a.question} → ${a.selected}')
        .join('\n');
  }

  Future<AgentRunResult> run(
    String userInput, {
    AgentMode mode = AgentMode.agent,
    bool continueSession = false,
    AgentCallbacks? cbs,
  }) async {
    if (!continueSession) messages = [];
    _aborted = false;
    _permissionMode = config.permissionMode;

    // Turn-start compaction check.
    await _maybeCompact(cbs);

    messages = messages
        .where((m) =>
            m.role != MessageRole.system ||
            m.content.startsWith('[PREVIOUS CONTEXT SUMMARY]'))
        .toList();
    messages.insert(0, Message(role: MessageRole.system, content: _systemPrompt(mode)));
    messages.add(Message(role: MessageRole.user, content: userInput));

    final steps = <AgentStep>[];
    var iteration = 0;
    final cbsDesc = cbs == null
        ? 'null'
        : 'step=${cbs.onStep != null} text=${cbs.onText != null}';
    debugPrint('[agent] run start: mode=$mode continue=$continueSession '
        'history=${messages.length} cbs=$cbsDesc');

    while (iteration < config.maxIterations) {
      iteration++;
      debugPrint('[agent] iteration $iteration start');
      if (_aborted) return _cancelled(steps);

      ModelResponse? response;
      try {
        _abortCompleter = Completer<void>();
        response = await _callModelWithRetry(cbs);
      } on ModelException catch (e) {
        if (_aborted) return _cancelled(steps);
        return AgentRunResult(content: 'Model request failed: $e', steps: steps);
      } finally {
        _abortCompleter = null;
      }
      if (response == null) {
        if (_aborted) return _cancelled(steps);
        return AgentRunResult(content: 'Model request failed after retries.', steps: steps);
      }
      if (_aborted) return _cancelled(steps);

      messages.add(Message(
        role: MessageRole.assistant,
        content: response.content,
        toolCalls: response.toolCalls.isEmpty ? null : response.toolCalls,
      ));

      debugPrint('[agent] iteration $iteration: model responded, '
          'content=${response.content.length} chars, '
          'toolCalls=${response.toolCalls.length}');
      if (response.toolCalls.isEmpty) {
        debugPrint('[agent] no tool calls — final answer, returning');
        final streamed = cbs?.onText != null && response.content.isNotEmpty;
        return AgentRunResult(
            content: response.content, steps: steps, streamedFinal: streamed);
      }

      final batch = await _executeBatch(response.toolCalls, mode, steps, cbs);
      debugPrint('[agent] batch done: steps=${batch.steps.length} '
          'cancelled=${batch.cancelled}');
      if (batch.cancelled) return _cancelled(steps);
      messages.addAll(batch.toolMessages);
      steps.addAll(batch.steps);
      // Every 10 tool calls, re-check compaction.
      if (steps.length % 10 == 0) await _maybeCompact(cbs);
    }
    return AgentRunResult(
      content: 'Reached max iterations (${config.maxIterations}) without a final answer.',
      steps: steps,
    );
  }

  AgentRunResult _cancelled(List<AgentStep> steps) =>
      AgentRunResult(content: 'Execution cancelled by user.', steps: steps);

  Future<void> _maybeCompact(AgentCallbacks? cbs) async {
    final result = await maybeCompact(
      messages,
      model: model,
      thresholdTokens: config.compactionThresholdTokens,
      retainTokens: config.compactionRetainTokens,
    );
    if (result == null) return;
    messages
      ..clear()
      ..addAll(result.messages);
    cbs?.onCompaction?.call(result.beforeTokens, result.afterTokens);
  }

  /// Manual compaction (/compact): summarize now regardless of threshold.
  /// Returns null if there is nothing to compact.
  Future<CompactionResult?> compactNow({String? instructions}) async {
    final result = await maybeCompact(
      messages,
      model: model,
      thresholdTokens: config.compactionThresholdTokens,
      retainTokens: config.compactionRetainTokens,
      force: true,
      instructions: instructions,
    );
    if (result == null) return null;
    messages
      ..clear()
      ..addAll(result.messages);
    return result;
  }

  // ── 3-phase tool batch ────────────────────────────────────────────

  final _batchCancelled = _BatchOutcome(cancelled: true);

  Future<_BatchOutcome> _executeBatch(
    List<ToolCall> calls,
    AgentMode mode,
    List<AgentStep> priorSteps,
    AgentCallbacks? cbs,
  ) async {
    // Phase 0 — dedupe baseline: prior steps + within-batch set.
    final preBatchKeys = priorSteps
        .where((s) => s.toolCall != null)
        .map((s) => '${s.toolCall!.name}:${s.toolCall!.argumentsJson}')
        .toSet();
    final seenInBatch = <String>{};

    debugPrint('[agent] batch: ${calls.length} call(s): '
        '${calls.map((c) => c.name).join(', ')}');

    // Phase 1 — sequential gating pass.
    final plan = <_PlanEntry>[];
    for (final call in calls) {
      if (_aborted) return _batchCancelled;
      final key = '${call.name}:${call.argumentsJson}';
      if (preBatchKeys.contains(key) || !seenInBatch.add(key)) {
        plan.add(_PlanEntry(call, _Kind.redundant));
        continue;
      }
      if (!_modeAllows(call.name, mode)) {
        plan.add(_PlanEntry(call, _Kind.blocked));
        continue;
      }
      // Permission — re-read mode each call so "always this session"
      // flips the rest of the batch.
      if (_needsApproval(call) && cbs?.onApproval != null) {
        final decision = await cbs!.onApproval!(call);
        if (decision != null && decision.sessionAlways) {
          _permissionMode = PermissionMode.autoEdit;
        }
        if (decision == null || !decision.approved) {
          plan.add(_PlanEntry(call, _Kind.denied));
          continue;
        }
      }
      plan.add(_PlanEntry(call, _Kind.exec, lockKey: classifyLockKey(call.name, call.args)));
    }

    // Phase 2 — concurrent execution with gate + per-key mutexes.
    final gate = MutationGate();
    final mutexes = MutexMap();
    final windows = <ExecWindow>[];

    Future<_ExecResult> runEntry(_PlanEntry entry) async {
      // Read-only bypasses all coordination.
      if (entry.lockKey != null) {
        await gate.acquire();
        try {
          await mutexes.acquire(entry.lockKey!);
        } finally {
          gate.release();
        }
      }
      final t0 = DateTime.now();
      String result;
      try {
        result = await registry.call(
          entry.call.name,
          entry.call.args,
          ToolContext(
            sessionId: config.sessionId,
            cwd: config.cwd,
            askUser: cbs?.onAskUser,
          ),
        );
        if (entry.call.name == 'bash') {
          redirects.record(entry.call.args['command'] as String? ?? '',
              outputBytes: result.length);
        }
      } catch (e) {
        result = 'Tool Error: $e';
      } finally {
        if (entry.lockKey != null) mutexes.release(entry.lockKey!);
      }
      final ms = DateTime.now().difference(t0).inMilliseconds;
      debugPrint('[agent] tool ${entry.call.name} finished in ${ms}ms, '
          'result=${result.length} chars');
      windows.add(ExecWindow(entry.call.name, t0.millisecondsSinceEpoch,
          t0.millisecondsSinceEpoch + ms));
      return _ExecResult(entry, result, ms);
    }

    final futures = plan.map((e) async {
      switch (e.kind) {
        case _Kind.exec:
          return runEntry(e);
        case _Kind.redundant:
          return _ExecResult(e, 'Skipped: duplicate of an earlier call in this turn.', 0);
        case _Kind.denied:
          return _ExecResult(e, 'Denied by user.', 0);
        case _Kind.blocked:
          return _ExecResult(e, 'Tool ${e.call.name} is not available in this mode.', 0);
      }
    });

    final results = await Future.wait(futures);
    execWindows.addAll(windows);

    // Emit steps and tool messages in the model's original order.
    final toolMessages = <Message>[];
    final steps = <AgentStep>[];
    for (final r in results) {
      steps.add(AgentStep(
        thought: '',
        toolCall: r.entry.call,
        toolResult: r.result,
        toolCallMs: r.ms,
      ));
      toolMessages.add(ToolResult(toolCallId: r.entry.call.id, content: r.result).toMessage());
      debugPrint('[agent] emitting onStep for ${r.entry.call.name} '
          '(handler=${cbs?.onStep != null ? "set" : "MISSING"})');
      cbs?.onStep?.call(steps.last);
    }
    return _BatchOutcome(toolMessages: toolMessages, steps: steps);
  }

  bool _needsApproval(ToolCall call) {
    debugPrint('[agent] approval check: tool=${call.name} '
        'mode=$_permissionMode args=${call.argumentsJson}');
    // Risky bash (installs/downloads/network) always needs approval,
    // even in auto mode.
    if (call.name == 'bash') {
      try {
        final args = jsonDecode(call.argumentsJson) as Map<String, dynamic>;
        final cmd = args['command'];
        if (cmd is String && isRiskyBashCommand(cmd)) return true;
      } catch (_) {}
    }
    if (_permissionMode == PermissionMode.auto) return false;
    final def = registry.definition(call.name);
    if (_permissionMode == PermissionMode.notify) return true;
    // auto-edit: only modifying bash asks.
    return def?.isModifying == true && call.name == 'bash';
  }

  Future<ModelResponse?> _callModelWithRetry(AgentCallbacks? cbs) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      debugPrint('[agent] model.chat attempt $attempt '
          '(messages=${messages.length}, tools=${_availableTools().length})');
      try {
        return await model.chat(
          messages,
          _availableTools(),
          onText: cbs?.onText,
          onReasoning: cbs?.onReasoning,
          abortSignal: _abortCompleter == null ? null : () => _abortCompleter!.future,
        );
      } on ModelException catch (e) {
        debugPrint('[agent] model error (attempt $attempt): $e');
        cbs?.onModelError?.call(e);
        if (e.isTimeout) return null;
        if (attempt == 3) rethrow;
      }
    }
    return null; // unreachable
  }

  List<ToolDefinition> _availableTools() => registry.getDefinitions();

  bool _modeAllows(String name, AgentMode mode) {
    switch (mode) {
      case AgentMode.plan:
        return const {'read', 'list', 'grep', 'glob', 'plan_write'}.contains(name);
      case AgentMode.chat:
        return const {'read', 'list', 'grep'}.contains(name);
      case AgentMode.agent:
        return true;
    }
  }

  String _systemPrompt(AgentMode mode) {
    final override = switch (mode) {
      AgentMode.agent => config.prompts['agent'],
      AgentMode.chat => config.prompts['chat'],
      AgentMode.plan => config.prompts['plan'],
    };
    final base = override ??
        switch (mode) {
          AgentMode.agent => agentSystemPrompt,
          AgentMode.chat => chatSystemPrompt,
          AgentMode.plan => planningSystemPrompt,
        };
    final home = homeDir;
    final lastUser = messages
        .lastWhere((m) => m.role == MessageRole.user,
            orElse: () => Message(role: MessageRole.user, content: ''))
        .content;
    return base
        .replaceAll('\${cwd}', config.cwd)
        .replaceAll('\${platform}', Platform.operatingSystem) +
        collectInstructions(config.cwd) +
        collectMemory(config.cwd, home, lastUser) +
        skillsPromptFragment(
            discoverSkills(config.cwd, home), config.activeSkills);
  }

  void close() {
    if (model is ModelClient) (model as ModelClient).close();
    filePool.dispose();
  }
}

enum _Kind { exec, redundant, denied, blocked }

class _PlanEntry {
  _PlanEntry(this.call, this.kind, {this.lockKey});

  final ToolCall call;
  final _Kind kind;
  final String? lockKey;
}

class _ExecResult {
  _ExecResult(this.entry, this.result, this.ms);

  final _PlanEntry entry;
  final String result;
  final int ms;
}

class _BatchOutcome {
  _BatchOutcome({this.cancelled = false, this.toolMessages = const [], this.steps = const []});

  final bool cancelled;
  final List<Message> toolMessages;
  final List<AgentStep> steps;
}
