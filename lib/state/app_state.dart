import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../engine/config_loader.dart';
import '../engine/instructions.dart';
import '../platform_env_io.dart' show homeDir;
import '../engine/memory.dart';
import '../engine/models.dart'
    show AgentConfig, AgentMode, AskUserResponse, Message, MessageRole,
    PermissionMode;
import '../engine/skills.dart';
import 'command_registry.dart';
import '../engine/session_store.dart';
import 'log_store.dart';
import 'session_store_notifier.dart';
import '../engine_host/engine_isolate.dart';

/// App-level state: owns the engine host, translates events into stores.
class AppState extends ChangeNotifier {
  AppState._(this.host, this.configLoader, this.config, this.sessions);

  static Future<AppState> create({String? projectDir}) async {
    final loader = ConfigLoader(projectDir: projectDir);
    final config = await loader.load();
    final host = await EngineHost.spawn(
      config: config,
      sessionsDir: loader.sessionsDir,
    );
    final state = AppState._(
      host,
      loader,
      config,
      SessionStoreNotifier(SessionStore(loader.sessionsDir)),
    );
    state._listen();
    return state;
  }

  EngineHost host; // replaced wholesale on crash recovery
  final ConfigLoader configLoader;
  AgentConfig config;
  final SessionStoreNotifier sessions;

  final LogStore log = LogStore();
  final StreamingTextNotifier streaming = StreamingTextNotifier();

  bool running = false;
  bool _reportUsage = false; // /usage asks for the printed report
  String? activeSessionId;
  ApprovalRequestEvent? pendingApproval;
  AskUserEvent? pendingAskUser;

  // Phase 7 state.
  bool planMode = false; // sends go to the engine in plan mode until the plan is confirmed
  bool chatMode = false; // next send goes to the engine in chat mode (no tools)
  String? pendingPlan; // plan markdown awaiting confirm
  String? _lastPlanRequest;
  String? pendingCrash; // engine crash message awaiting recovery choice
  String _lastUserMessage = '';

  // Phase 8 state (context panel).
  final List<PlanStep> planSteps = [];
  final Set<String> workingFiles = {};

  /// UI state: expanded directory paths in the workspace file tree.
  final Set<String> expandedTreeDirs = {};

  void toggleTreeDir(String path) {
    expandedTreeDirs.contains(path)
        ? expandedTreeDirs.remove(path)
        : expandedTreeDirs.add(path);
    notifyListeners();
  }

  /// Context size in tokens, measured engine-side (chars/4 estimate) and
  /// refreshed with each UsageEvent. 0 until the first turn completes.
  int contextTokens = 0;

  void send(String text, {bool? forcePlan}) {
    if (text.startsWith('/')) {
      handleCommand(text);
      return;
    }
    final plan = forcePlan ?? planMode;
    // A boot-fresh chat has no session yet — mint one before the first
    // turn so the engine persists it and plan tools write into
    // `.tiny-cli/<id>/plan/` instead of the `default` folder.
    if (activeSessionId == null) {
      final id = const Uuid().v4();
      host.newSession(id);
      activeSessionId = id;
    }
    log.add(LogEntry(type: LogEntryType.user, text: text));
    // Only clear the streaming buffer when idle — wiping it mid-turn
    // would erase the in-flight response before it can be committed.
    // StatusEvent(running:true) resets it when the turn actually starts.
    if (!running) streaming.begin();
    if (plan) _lastPlanRequest = text;
    _lastUserMessage = text;
    host.sendMessage(text,
        mode: plan
            ? AgentMode.plan
            : chatMode
                ? AgentMode.chat
                : AgentMode.agent);
    // Plan mode is sticky: follow-up corrections stay in plan mode until
    // the plan is confirmed (confirmPlan) — only chat is one-shot.
    chatMode = false;
    notifyListeners();
  }

  // ── Slash commands (T10.1) ─────────────────────────────────────────

  List<Map<String, dynamic>> mcpServers = const [];

  /// Delete an MCP server: runtime removal in the engine (McpServersEvent
  /// refreshes [mcpServers]) + persist the config change to agents.json.
  Future<void> mcpDelete(String name) async {
    host.mcpDelete(name);
    config = config.copyWith(
        mcpServers: config.mcpServers.where((s) => s.name != name).toList());
    await configLoader.saveMcpServers(config.mcpServers);
    notifyListeners();
  }

  /// /mode picker state.
  bool _showModePicker = false;
  bool get showModePicker => _showModePicker;
  set showModePicker(bool v) {
    _showModePicker = v;
    notifyListeners();
  }

  /// /skills picker state.
  bool _showSkillPicker = false;
  bool get showSkillPicker => _showSkillPicker;
  set showSkillPicker(bool v) {
    _showSkillPicker = v;
    notifyListeners();
  }

  /// Activate/deactivate a skill for the next turn's system prompt.
  /// In-memory only (persisted config doesn't carry activeSkills yet).
  void toggleSkill(String name) {
    final active = {...config.activeSkills};
    active.contains(name) ? active.remove(name) : active.add(name);
    config = config.copyWith(activeSkills: active.toList());
    notifyListeners();
  }

  /// Settings panel state (⚙ in the input bar).
  bool _showSettings = false;
  bool get showSettings => _showSettings;
  set showSettings(bool v) {
    _showSettings = v;
    notifyListeners();
  }

  /// Tab the settings panel opens on (2 = MCP servers, set by /mcp).
  int settingsTab = 0;

  /// Apply settings-panel choices for the rest of the session.
  void applySettings(
      {PermissionMode? permissionMode, bool? planMode, bool? chatMode}) {
    if (permissionMode != null) {
      config = config.copyWith(permissionMode: permissionMode);
      host.requestSetPermissionMode(permissionMode);
    }
    if (planMode != null) this.planMode = planMode;
    if (chatMode != null) this.chatMode = chatMode;
    notifyListeners();
  }

  /// Persist mode settings into agents.json `settings` object.
  Future<void> saveSettings() async {
    await configLoader.saveSettings(
      permissionMode: config.permissionMode.name,
    );
  }

  void _info(String text) => log.add(LogEntry(type: LogEntryType.info, text: text));

  void handleCommand(String input) {
    final parts = input.split(RegExp(r'\s+'));
    final name = parts.first;
    final args = input.substring(name.length).trim();
    switch (name) {
      case '/help':
        _info('Commands:\n${kCommands.map((c) => '  ${c.name} ${c.argsHint}'.padRight(22) + c.description).join('\n')}');
      case '/clear':
        log.clear();
      case '/stop':
        interrupt();
      case '/usage':
        _reportUsage = true;
        host.requestUsage(); // result lands via UsageEvent below
      case '/find':
        _find(args);
      case '/mcp':
        settingsTab = 2;
        showSettings = true;
      case '/mode':
        // Direct switch: /mode <notify|auto-edit|auto>
        final requested = args.toLowerCase().replaceAll('_', '-');
        final match = PermissionMode.values
            .where((m) => m.name.toLowerCase() == requested ||
                (m == PermissionMode.autoEdit && requested == 'auto-edit'))
            .toList();
        if (match.isNotEmpty) {
          applySettings(permissionMode: match.first);
          saveSettings();
          _info('permission mode set to: ${match.first.name}');
        } else {
          showModePicker = true;
        }
      case '/session':
        _info('session: ${activeSessionId ?? '(unsaved — persists after first turn)'}');
      case '/plan':
        if (args.isEmpty) {
          _info('usage: /plan <goal> — or use the ◇ plan toggle');
        } else {
          send(args, forcePlan: true);
        }
      case '/skills':
        _listSkills();
        showSkillPicker = true;
      case '/context':
        _describeContext();
      case '/compact':
        host.requestCompact(args.isEmpty ? null : args);
      default:
        _info('Unknown command: $name — try /help');
    }
  }

  void _find(String query) {
    if (query.isEmpty) return _info('usage: /find <text>');
    final hits = <String>[];
    for (var i = 0; i < log.groups.length; i++) {
      final g = log.groups[i];
      final texts = [if (g.userText != null) g.userText!, ...g.entries.map((e) => e.text)];
      for (final t in texts) {
        if (t.toLowerCase().contains(query.toLowerCase())) {
          final at = t.indexOf(query);
          final start = at > 30 ? at - 30 : 0;
          hits.add('group $i: …${t.substring(start, (at + query.length + 40).clamp(0, t.length))}…');
          break;
        }
      }
    }
    _info(hits.isEmpty
        ? 'No matches for "$query"'
        : 'Found ${hits.length} matches for "$query":\n${hits.take(20).join('\n')}');
  }

  void _listSkills() {
    final skills = discoverSkills(configLoader.projectDir,
        homeDir);
    if (skills.isEmpty) return _info('No skills discovered (.agents/skills/*/SKILL.md)');
    _info('Skills:\n${skills.map((s) => '  ${config.activeSkills.contains(s.name) ? '●' : '○'} ${s.name} — ${s.description}').join('\n')}');
  }

  void _describeContext() {
    final home = homeDir;
    _info('instructions: ${collectInstructions(configLoader.projectDir).isEmpty ? 'none' : 'CLAUDE/AGENTS found'}\n'
        'memory: ${collectMemory(configLoader.projectDir, home, _lastUserMessage).isEmpty ? 'none relevant' : 'injected (<10k)'}\n'
        'skills: ${discoverSkills(configLoader.projectDir, home).length} discovered, '
        '${config.activeSkills.length} active');
  }

  /// Rough context estimate for the statusline: chars/4 over the log.
  int get estimatedTokens => log.groups.fold(
      0,
      (n, g) =>
          n +
          ((g.userText ?? '').length +
                  g.entries.fold(0, (m, e) => m + e.text.length))
              ~/
              4);


  /// PlanConfirmDialog actions.
  void confirmPlan() {
    final text = 'Proceed with the confirmed plan. Execute it step by step.';
    pendingPlan = null;
    planMode = false; // plan approved → hand off to agent mode
    send(text);
  }

  void regeneratePlan() {
    final request = _lastPlanRequest;
    pendingPlan = null;
    if (request != null) send(request, forcePlan: true);
  }

  void dismissPlan() {
    pendingPlan = null;
    notifyListeners();
  }

  void interrupt() => host.interrupt();

  /// ＋ New chat: fresh session id, empty log, engine reset for the next turn.
  void newChat() {
    if (running) host.interrupt();
    final id = const Uuid().v4();
    host.newSession(id);
    activeSessionId = id;
    running = false;
    streaming.end();
    log.clear();
    planSteps.clear();
    workingFiles.clear();
    pendingPlan = null;
    sessions.setActive(id);
    notifyListeners();
  }

  /// Click a session tile: resume its history in the engine + log.
  Future<void> openSession(String id) async {
    if (running) host.interrupt();
    final session = await sessions.open(id);
    if (session == null) return;
    host.newSession(id);
    host.resume(session.messages);
    activeSessionId = id;
    running = false;
    streaming.end();
    log.replaceAll(_entriesFromHistory(session.messages));
    sessions.setActive(id);
    // Resume context panel state from this session's plan file on disk.
    planSteps.clear();
    workingFiles.clear();
    _reloadPlan();
    notifyListeners();
  }

  /// Rebuild display entries from persisted history: user/assistant text plus
  /// tool-call/result pairs. Tool details lost in persistence stay collapsed.
  // ── Context panel (T8.4) ───────────────────────────────────────────

  String get _planFilePath =>
      '${configLoader.projectDir}/.tiny-cli/${activeSessionId ?? 'default'}/plan/current_task.md';

  /// Track working files + plan state from tool calls.
  void _trackContext(String tool, String argumentsJson) {
    var touched = false;
    if (const {'write', 'search_replace', 'insert_lines'}.contains(tool)) {
      try {
        final path = jsonDecode(argumentsJson)['path'] as String?;
        if (path != null) {
          workingFiles.add(path);
          touched = true;
        }
      } catch (_) {}
    }
    if (const {'plan_write', 'manage_tasks', 'mark_task_complete'}.contains(tool)) {
      _reloadPlan();
      if (tool == 'plan_write' && pendingPlan == null) {
        // Plan-mode turn produced a plan → confirm dialog.
        final text = _readPlanFile();
        if (text != null) {
          pendingPlan = text;
          touched = true;
        }
      }
    }
    if (touched) notifyListeners();
  }

  String? _readPlanFile() {
    try {
      final text = File(_planFilePath).readAsStringSync();
      return text.trim().isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  void _reloadPlan() {
    final text = _readPlanFile();
    planSteps.clear();
    if (text == null) return;
    for (final line in text.split('\n')) {
      final m = RegExp(r'^\s*[-*]\s+\[( |x|X)\]\s+(.+)$').firstMatch(line);
      if (m != null) {
        planSteps.add(PlanStep(text: m.group(2)!, done: m.group(1) != ' '));
      }
    }
  }

  // ── Crash recovery (T7.2) ──────────────────────────────────────────

  Future<void> _respawnHost() async {
    await _eventsSub?.cancel();
    host.dispose();
    host = await EngineHost.spawn(
      config: config,
      sessionsDir: configLoader.sessionsDir,
      sessionId: activeSessionId,
    );
    _listen();
  }

  /// RecoveryDialog actions.
  Future<void> resumeFromCrash() async {
    pendingCrash = null;
    notifyListeners();
    await _respawnHost();
    if (activeSessionId != null) await openSession(activeSessionId!);
  }

  Future<void> retryFromCrash() async {
    pendingCrash = null;
    notifyListeners();
    await _respawnHost();
    if (_lastUserMessage.isEmpty) return;
    if (activeSessionId != null) {
      final session = await sessions.open(activeSessionId!);
      if (session != null) {
        host.newSession(activeSessionId!);
        host.resume(session.messages);
      }
    }
    log.add(LogEntry(type: LogEntryType.user, text: _lastUserMessage));
    streaming.begin();
    host.sendMessage(_lastUserMessage);
  }

  void discardCrash() {
    pendingCrash = null;
    notifyListeners();
    newChat();
  }

  List<LogEntry> _entriesFromHistory(List<Message> messages) {
    final entries = <LogEntry>[];
    for (final m in messages) {
      switch (m.role) {
        case MessageRole.user:
          entries.add(LogEntry(type: LogEntryType.user, text: m.content));
        case MessageRole.assistant:
          for (final c in m.toolCalls ?? const []) {
            entries.add(LogEntry(
              type: LogEntryType.toolCall,
              text: c.argumentsJson,
              toolName: c.name,
            ));
          }
          if (m.content.trim().isNotEmpty) {
            entries.add(LogEntry(type: LogEntryType.assistant, text: m.content));
          }
        case MessageRole.tool:
          entries.add(
              LogEntry(type: LogEntryType.toolResult, text: m.content));
        case MessageRole.system:
          entries.add(LogEntry(type: LogEntryType.system, text: m.content));
      }
    }
    return entries;
  }

  void respondApproval(String id, {required bool approved, bool sessionAlways = false}) {
    host.approvalResponse(id, approved: approved, sessionAlways: sessionAlways);
    pendingApproval = null;
    notifyListeners();
  }

  void respondAskUser(String id, AskUserResponse response) {
    host.askUserResponse(id, response);
    pendingAskUser = null;
    notifyListeners();
  }

  StreamSubscription<AgentEvent>? _eventsSub;

  void _listen() {
    _eventsSub = host.events.listen((e) {
      switch (e) {
        case StepEvent(:final step):
          if (step.toolCall != null) {
            // Text preceding a tool call is a complete assistant message —
            // commit it now so the canvas shows discrete messages
            // interleaved with tool receipts instead of one blob.
            if (streaming.text.trim().isNotEmpty) {
              log.add(
                  LogEntry(type: LogEntryType.assistant, text: streaming.text));
              streaming.begin(); // reset buffer, still live for more text
            }
            log.add(LogEntry(
              type: LogEntryType.toolCall,
              text: step.toolCall!.argumentsJson,
              toolName: step.toolCall!.name,
            ));
            log.add(LogEntry(type: LogEntryType.toolResult, text: step.toolResult ?? ''));
            _trackContext(step.toolCall!.name, step.toolCall!.argumentsJson);
          }
        case TextDeltaEvent(:final delta):
          streaming.append(delta);
        case ThinkingDeltaEvent(:final delta):
          // Merge into a single thinking block: replace the previous
          // reasoning entry (if it's the tail) with the accumulated text.
          final lastIdx = log.entries.isEmpty ? -1 : log.entries.length - 1;
          final last = lastIdx >= 0 ? log.entries[lastIdx] : null;
          if (last != null && last.type == LogEntryType.reasoning) {
            log.replaceAt(lastIdx,
                LogEntry(type: LogEntryType.reasoning, text: last.text + delta));
          } else {
            log.add(LogEntry(type: LogEntryType.reasoning, text: delta));
          }
        case ApprovalRequestEvent():
          pendingApproval = e;
          notifyListeners();
        case AskUserEvent():
          pendingAskUser = e;
          notifyListeners();
        case StatusEvent():
          if (e.running) {
            running = true;
            // Fresh turn (including one flushed from the engine's queue):
            // start with an empty streaming buffer.
            streaming.begin();
          } else {
            running = false;
            host.requestUsage(); // refreshes contextTokens for the statusline
            streaming.end();
            // The streamed blob becomes a normal entry in the log.
            if (streaming.text.isNotEmpty) {
              log.add(LogEntry(type: LogEntryType.assistant, text: streaming.text));
              streaming.begin(); // reset buffer, still ready for next turn
              streaming.end();
            }
          }
          sessions.refresh(); // sidebar timestamps/title may have changed
          notifyListeners();
        case ModelErrorEvent(:final message):
          log.add(LogEntry(type: LogEntryType.error, text: message));
        case EngineCrashedEvent(:final message):
          log.add(LogEntry(type: LogEntryType.error, text: message));
          if (pendingCrash == null) {
            running = false;
            pendingCrash = message;
            notifyListeners();
          }
        case CompactionEvent():
          log.add(LogEntry(
              type: LogEntryType.system,
              text: 'memory compacted · ${e.beforeTokens} → ${e.afterTokens} tokens'));
        case UsageEvent(:final usage):
          contextTokens =
              (usage['contextTokens'] as num?)?.toInt() ?? contextTokens;
          if (!_reportUsage) {
            notifyListeners(); // silent refresh (statusline meter)
            return;
          }
          _reportUsage = false;
          final counts = (usage['toolCounts'] as Map<String, dynamic>)
              .entries
              .map((e) => '  ${e.key}: ${e.value}')
              .join('\n');
          final redirects = (usage['redirects'] as Map<String, dynamic>)
              .entries
              .map((e) => '  ${e.key}: ${e.value} bytes')
              .join('\n');
          _info('Usage:\ntool calls:\n${counts.isEmpty ? '  (none)' : counts}\n'
              'observed concurrency: ${usage['maxConcurrency']}\n'
              'redirects:\n${redirects.isEmpty ? '  (none)' : redirects}');
        case McpServersEvent(:final servers):
          mcpServers = servers;
          notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    host.dispose();
    super.dispose();
  }
}

/// One checklist step parsed from the plan file (CtxPanel).
class PlanStep {
  PlanStep({required this.text, required this.done});

  final String text;
  final bool done;
}
