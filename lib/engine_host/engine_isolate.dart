import 'dart:async';
import 'dart:isolate';

import 'package:uuid/uuid.dart';

import '../engine/agent.dart';
import '../engine/mcp/manager.dart';
import '../engine/models.dart';
import '../engine/protocol.dart';
import '../engine/session_store.dart';

export '../engine/protocol.dart';

/// Spawns and supervises one engine isolate per session. Bridges the typed
/// command/event protocol across the port pair; approval/ask-user requests
/// are correlated by id inside the engine isolate, and responses are
/// forwarded back as commands. Crashes surface as [EngineCrashedEvent].
class EngineHost {
  EngineHost._(this._isolate, this._cmdPort, this._events, this._errorPort);

  static Future<EngineHost> spawn({
    required AgentConfig config,
    required String sessionsDir,
    String? sessionId,
  }) async {
    final readyPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _engineMain,
      _Bootstrap(readyPort.sendPort, config, sessionId, sessionsDir),
      errorsAreFatal: true,
      debugName: 'engine-${sessionId ?? 'new'}',
    );

    // First message from the engine: its command ReceivePort SendPort.
    final cmdPort = await readyPort.first as SendPort;

    final eventPort = ReceivePort();
    final controller = StreamController<AgentEvent>.broadcast();
    // Post-dispose the ports can still deliver one last message (isolate
    // exit, unlistened error) — drop those instead of hitting a closed
    // broadcast controller.
    void emit(AgentEvent e) {
      if (!controller.isClosed) controller.add(e);
    }

    final errorPort = ReceivePort();
    errorPort.listen((error) {
      emit(EngineCrashedEvent('engine isolate error: $error'));
    });

    final host = EngineHost._(isolate, cmdPort, controller, errorPort);
    isolate.addErrorListener(errorPort.sendPort);
    cmdPort.send(eventPort.sendPort); // engine's event channel

    eventPort.listen(
      (msg) {
        if (msg is AgentEvent) emit(msg);
      },
      onError: (Object e) => emit(EngineCrashedEvent(e.toString())),
      onDone: () => emit(const EngineCrashedEvent('engine isolate exited')),
    );

    return host;
  }

  final Isolate _isolate;
  final SendPort _cmdPort;
  final StreamController<AgentEvent> _events;
  final ReceivePort _errorPort;
  bool _closed = false;

  Stream<AgentEvent> get events => _events.stream;

  void sendMessage(String text, {AgentMode? mode, bool continueSession = true}) =>
      _send(SendMessageCommand(text, mode: mode, continueSession: continueSession));

  void interrupt() => _send(const InterruptCommand());

  void approvalResponse(String id, {required bool approved, bool sessionAlways = false}) =>
      _send(ApprovalResponseCommand(id: id, approved: approved, sessionAlways: sessionAlways));

  void askUserResponse(String id, AskUserResponse response) =>
      _send(AskUserResponseCommand(id: id, response: response));

  void newSession(String sessionId) => _send(NewSessionCommand(sessionId));

  void resume(List<Message> messages) => _send(ResumeCommand(messages));

  void mcpToggle(String name, bool enabled) =>
      _send(McpToggleCommand(name: name, enabled: enabled));

  /// Hard-reconnect an MCP server (picker "Reconnect"): kills the child
  /// process and re-runs connect + tools/list.
  void mcpReconnect(String name) =>
      _send(McpReconnectCommand(name: name));

  /// Remove an MCP server: kill the connection, unregister tools, forget
  /// config/enabled state. Persistence of the config change is AppState's job.
  void mcpDelete(String name) => _send(McpDeleteCommand(name: name));

  void requestUsage() => _send(const UsageRequestCommand());

  /// Manual /compact: summarize the history now, bypassing the threshold.
  void requestCompact([String? instructions]) =>
      _send(CompactRequestCommand(instructions: instructions));

  /// Runtime permission-mode change (settings panel / `/mode <mode>`).
  void requestSetPermissionMode(PermissionMode mode) =>
      _send(SetPermissionModeCommand(mode));

  void _send(AgentCommand cmd) {
    if (!_closed) _cmdPort.send(cmd);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _isolate.kill(priority: Isolate.immediate);
    _errorPort.close();
    _events.close();
  }
}

class _Bootstrap {
  _Bootstrap(this.readyPort, this.config, this.sessionId, this.sessionsDir);

  final SendPort readyPort;
  final AgentConfig config;
  final String? sessionId;
  final String sessionsDir;
}

/// Runs inside the engine isolate.
Future<void> _engineMain(_Bootstrap bootstrap) async {
  final cmdPort = ReceivePort();
  bootstrap.readyPort.send(cmdPort.sendPort);

  var sessionId = bootstrap.sessionId;
  var agent = Agent(
    sessionId == null ? bootstrap.config : bootstrap.config.copyWith(sessionId: sessionId),
  );
  var store = SessionStore(bootstrap.sessionsDir);
  final mcp = McpManager(cwd: bootstrap.config.cwd);
  await mcp.connectAll(bootstrap.config.mcpServers, agent.registry);
  var busy = false;

  /// Messages sent while a turn is running, delivered when it ends.
  final pendingMessages = <SendMessageCommand>[];

  SendPort? eventPort;
  void emit(AgentEvent e) => eventPort?.send(e);

  // Report real MCP tool counts once the event port is attached below —
  // the /mcp picker otherwise falls back to config names with 0 tools.

  final approvalBridge = <String, Completer<ApprovalDecision>>{};
  final askUserBridge = <String, Completer<AskUserResponse>>{};

  /// One agent turn: run to completion, then persist the session.
  /// Caller owns the busy flag and the running/turnDone status events.
  Future<void> runTurn(SendMessageCommand msg) async {
    await agent.run(
      msg.text,
      mode: msg.mode ?? AgentMode.agent,
      continueSession: msg.continueSession,
      cbs: AgentCallbacks(
        onStep: (s) => emit(StepEvent(s)),
        onText: (d) => emit(TextDeltaEvent(d)),
        onReasoning: (d) => emit(ThinkingDeltaEvent(d)),
        onModelError: (e) => emit(ModelErrorEvent(e.toString())),
        onCompaction: (before, after) => emit(CompactionEvent(before, after)),
        onApproval: (call) {
          final id = const Uuid().v4();
          final completer = Completer<ApprovalDecision>();
          approvalBridge[id] = completer;
          emit(ApprovalRequestEvent(id: id, call: call));
          return completer.future;
        },
        onAskUser: (payload) {
          final id = const Uuid().v4();
          final completer = Completer<AskUserResponse>();
          askUserBridge[id] = completer;
          emit(AskUserEvent(id: id, payload: payload));
          return completer.future;
        },
      ),
    );
    // Persist the turn (debounce-free for now; single write per turn).
    if (sessionId != null && agent.getHistory().isNotEmpty) {
      final existing = await store.load(sessionId!);
      await store.save(Session(
        metadata: SessionMetadata(
          id: sessionId!,
          createdAt: existing?.metadata.createdAt ?? DateTime.now(),
          lastUpdatedAt: DateTime.now(),
          title: existing?.metadata.title ??
              (msg.text.length > 60 ? msg.text.substring(0, 60) : msg.text),
          permissionMode: bootstrap.config.permissionMode,
        ),
        messages: agent.getHistory(),
      ));
    }
  }

  cmdPort.listen((msg) async {
    // The host's event channel arrives as the first raw SendPort.
    if (msg is SendPort) {
      eventPort = msg;
      // Initial MCP state — real tool counts after connectAll().
      emit(McpServersEvent(mcp.describe()));
      return;
    }
    if (msg is! AgentCommand) return;

    switch (msg) {
      case SendMessageCommand():
        // A turn is running — queue instead of dropping; flushed when the
        // turn ends (finish or interrupt) so the agent picks it up next.
        if (busy) {
          pendingMessages.add(msg);
          return;
        }
        busy = true;
        emit(const StatusEvent(running: true));
        try {
          await runTurn(msg);
        } finally {
          busy = false;
          emit(const StatusEvent(running: false, turnDone: true));
          if (pendingMessages.isNotEmpty) {
            final next = pendingMessages.removeAt(0);
            cmdPort.sendPort.send(next); // re-dispatch through the same path
          }
        }
      case InterruptCommand():
        agent.interrupt();
      case ApprovalResponseCommand():
        approvalBridge
            .remove(msg.id)
            ?.complete(ApprovalDecision(
                approved: msg.approved, sessionAlways: msg.sessionAlways));
      case AskUserResponseCommand():
        askUserBridge.remove(msg.id)?.complete(msg.response);
      case NewSessionCommand():
        sessionId = msg.sessionId;
        agent.close();
        // Carry the live permission mode across the new session instead of
        // reverting to the boot-time config value.
        agent = Agent(bootstrap.config
            .copyWith(sessionId: sessionId, permissionMode: agent.permissionMode));
        mcp.registerInto(agent.registry); // keep processes, re-register tools
        store = SessionStore(bootstrap.sessionsDir);
      case ResumeCommand():
        agent.setHistory(msg.messages);
        sessionId = agent.config.sessionId;
      case McpToggleCommand():
        await mcp.setEnabled(msg.name, msg.enabled, agent.registry);
        emit(McpServersEvent(mcp.describe()));
      case McpReconnectCommand():
        await mcp.reconnect(msg.name, agent.registry);
        emit(McpServersEvent(mcp.describe()));
      case McpDeleteCommand():
        await mcp.delete(msg.name, agent.registry);
        emit(McpServersEvent(mcp.describe()));
      case UsageRequestCommand():
        emit(UsageEvent(agent.usageStats()));
      case CompactRequestCommand():
        final result = await agent.compactNow(instructions: msg.instructions);
        if (result != null) {
          emit(CompactionEvent(result.beforeTokens, result.afterTokens));
        }
      case SetPermissionModeCommand():
        agent.setPermissionMode(msg.mode);
    }
  });
}
