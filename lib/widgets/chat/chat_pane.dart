import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart' show PermissionMode;
import '../../engine/skills.dart' show discoverSkills;
import '../../platform_env_io.dart' show homeDir;
import '../../state/app_state.dart';
import '../../state/command_registry.dart';
import '../../state/log_store.dart';
import '../../state/session_store_notifier.dart';
import '../dashboard/session_dashboard.dart';
import '../../state/workspace.dart';
import '../../theme/app_theme.dart';
import '../markview/markdown.dart';
import '../modals/approval_dialog.dart';
import '../modals/option_picker.dart';
import '../modals/plan_confirm_dialog.dart';
import '../modals/recovery_dialog.dart';
import '../modals/settings_dialog.dart';
import 'statusline.dart';

/// Middle pane: topbar, message stream, input bar, statusline.
class ChatPane extends StatelessWidget {
  const ChatPane(
      {super.key, this.showCtxToggle = false, this.onToggleCtx});

  /// Whether the right context panel is visible (topbar toggle hint).
  final bool showCtxToggle;
  final VoidCallback? onToggleCtx;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();

    return Stack(
      children: [
        Container(
          color: theme.stream,
          child: Column(
            children: [
              _Topbar(onToggleCtx: onToggleCtx),
              Expanded(
                  child: app.dashboardView
                      ? const SessionDashboard()
                      : _TurnList()),
              Divider(height: 1, thickness: 1, color: theme.line),
              const _InputBar(),
            ],
          ),
        ),
        if (app.pendingApproval != null)
          ApprovalDialog(request: app.pendingApproval!),
        if (app.pendingAskUser != null)
          QuestionnaireDialog(request: app.pendingAskUser!),
        if (app.pendingPlan != null) PlanConfirmDialog(plan: app.pendingPlan!),
        if (app.pendingCrash != null)
          RecoveryDialog(message: app.pendingCrash!),
        if (app.showModePicker) const ModePickerDialog(),
        if (app.showSkillPicker) const SkillPickerDialog(),
        if (app.showSettings) SettingsDialog(initialTab: app.settingsTab),
      ],
    );
  }
}

/// Canvas header: editable session title (double-tap), centered status pill
/// (idle / thinking / running tool), and row actions on the right.
class _Topbar extends StatefulWidget {
  const _Topbar({this.onToggleCtx});

  final VoidCallback? onToggleCtx;

  @override
  State<_Topbar> createState() => _TopbarState();
}

class _TopbarState extends State<_Topbar> {
  bool _editing = false;
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    // Eager init: a lazy `late final` would fire _currentTitle()'s
    // context.read during dispose if the title was never shown.
    _title = TextEditingController(text: _currentTitle());
  }

  String _currentTitle() {
    final app = context.read<AppState>();
    final sessions = context.read<SessionStoreNotifier>();
    final id = app.activeSessionId;
    for (final s in sessions.grouped(DateTime.now()).values.expand((l) => l)) {
      if (s.id == id) return s.title ?? 'New chat';
    }
    return 'New chat';
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _commitRename() {
    final app = context.read<AppState>();
    final id = app.activeSessionId;
    if (id != null && _title.text.trim().isNotEmpty) {
      context.read<SessionStoreNotifier>().rename(id, _title.text);
    }
    setState(() => _editing = false);
  }

  Future<void> _exportMarkdown() async {
    final app = context.read<AppState>();
    final buf = StringBuffer();
    for (final g in app.log.groups) {
      if (g.userText != null) {
        buf.writeln('## User\n\n${g.userText}\n');
      }
      for (final e in g.entries) {
        switch (e.type) {
          case LogEntryType.assistant:
            buf.writeln('$e.text\n');
          case LogEntryType.toolCall:
            buf.writeln('> tool `${e.toolName}` ${e.text}');
          case LogEntryType.toolResult:
            buf.writeln('> ↳ ${e.text}');
          default:
            break;
        }
      }
    }
    final path = await FilePicker.platform.saveFile(
        fileName: 'chat-${DateTime.now().toIso8601String().split('T').first}.md',
        type: FileType.custom,
        allowedExtensions: ['md']);
    if (path != null) File(path).writeAsStringSync(buf.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: theme.line))),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Editable title: double-tap (or double-click) to rename inline.
          GestureDetector(
            onDoubleTap: () {
              _title.text = _currentTitle();
              setState(() => _editing = true);
            },
            child: _editing
                ? SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _title,
                      autofocus: true,
                      style: TextStyle(color: theme.ink, fontSize: 13.5),
                      onSubmitted: (_) => _commitRename(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: theme.focusBorder(),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                  )
                : Text(_currentTitle(),
                    style: TextStyle(
                        color: theme.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          _ViewToggle(view: app.dashboardView),
          const Spacer(),
          StatusPill(running: app.running, log: app.log),
          const Spacer(),
          _TopbarAction(
              label: 'Clear', onTap: () => context.read<AppState>().log.clear()),
          const SizedBox(width: 14),
          _TopbarAction(label: 'Export .md', onTap: _exportMarkdown),
          if (widget.onToggleCtx != null) ...[
            const SizedBox(width: 14),
            _TopbarIcon(
                icon: Icons.view_sidebar_outlined,
                tooltip: 'Toggle context panel (Ctrl+Shift+B)',
                onTap: widget.onToggleCtx!),
          ],
        ],
      ),
    );
  }
}

/// Canvas view switch: 💬 Chat Stream | 📊 Session Dashboard.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view});

  final bool view; // false = chat stream, true = dashboard

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    Widget seg(String label, IconData icon, bool active, VoidCallback onTap) =>
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: active ? theme.accentDim : Colors.transparent,
                borderRadius: BorderRadius.circular(AppColors.radius),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: active ? theme.accent : theme.dim),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          color: active ? theme.ink : theme.dim, fontSize: 12)),
                ],
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: theme.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Chat Stream', Icons.chat_bubble_outline, !view,
              () {
            final app = context.read<AppState>();
            if (app.dashboardView) app.toggleDashboard();
          }),
          seg('Dashboard', Icons.insights_outlined, view, () {
            final app = context.read<AppState>();
            if (!app.dashboardView) app.toggleDashboard();
          }),
        ],
      ),
    );
  }
}

class _TopbarAction extends StatefulWidget {
  const _TopbarAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_TopbarAction> createState() => _TopbarActionState();
}

class _TopbarActionState extends State<_TopbarAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hover ? theme.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radius),
          ),
          child: Text(widget.label,
              style: TextStyle(color: theme.dim, fontSize: 12)),
        ),
      ),
    );
  }
}

class _TopbarIcon extends StatelessWidget {
  const _TopbarIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: theme.dim),
        hoverColor: theme.hover,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Centered execution-state pill: Idle (gray) · Agent thinking… (teal
/// pulse) · Running tool… (gold pulse). Thinking vs tool is inferred from
/// the tail of the log while a turn is running.
class StatusPill extends StatefulWidget {
  const StatusPill({super.key, required this.running, required this.log});

  final bool running;
  final LogStore log;

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    context.watch<LogStore>();

    String label = 'Idle';
    Color color = theme.dimmer;
    if (widget.running) {
      // Last entry being a toolCall (no result yet) means a tool is active.
      final entries = widget.log.entries;
      final inTool = entries.isNotEmpty &&
          entries.last.type == LogEntryType.toolCall;
      label = inTool ? 'Running tool…' : 'Agent thinking…';
      color = inTool ? theme.accent : theme.secondary;
    }

    return FadeTransition(
      opacity:
          Tween(begin: 1.0, end: 0.45).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.surface2,
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            Text(label, style: TextStyle(color: theme.dim, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

/// Message stream with auto-follow: sticks to the bottom while streaming,
/// wheel-up exits follow into browse, pill jumps back.
/// Empty-canvas welcome screen: brand mark, heading, and clickable
/// suggestions that prefill the input bar via AppState.setInput.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  static const _suggestions = [
    'Explain the structure of this workspace',
    'Summarize the changes in @file',
    'Write tests for the selected code',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppColors.radius),
                color: theme.accentDim,
              ),
              alignment: Alignment.center,
              child:
                  Text('▲', style: TextStyle(color: theme.accent, fontSize: 20)),
            ),
            const SizedBox(height: 14),
            Text('Start a new chat',
                style: TextStyle(
                    color: theme.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Ask anything about your workspace — type below to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.dim, fontSize: 13)),
            const SizedBox(height: 22),
            for (final s in _suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => app.setInput(s),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: theme.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.line),
                    ),
                    child: Text(s,
                        style:
                            TextStyle(color: theme.dim, fontSize: 13)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TurnList extends StatefulWidget {
  @override
  State<_TurnList> createState() => _TurnListState();
}

class _TurnListState extends State<_TurnList> {
  final _scroll = ScrollController();
  bool _following = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 80;
      if (!atBottom && _following) setState(() => _following = false);
      if (atBottom && !_following) setState(() => _following = true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() => _scroll.jumpTo(_scroll.position.maxScrollExtent);

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    context.watch<LogStore>(); // fold toggles rebuild the list
    final groups = app.log.groups;

    // Follow new content after it lays out.
    if (_following) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && _following) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }

    return Stack(
      children: [
        if (groups.isEmpty)
          const _EmptyChat()
        else
          // Selectable message stream: drag-select across the conversation
          // without hijacking the rest of the UI's mouse cursors.
          SelectionArea(
            child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: groups.length + (app.running ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == groups.length) return const _LiveTurn();
              return _groupWidget(context, groups[i], i);
            },
            ),
          ),
        // Jump-to-bottom pill when unfollowed.
        if (!_following)
          Positioned(
            right: 24,
            bottom: 12,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _jumpToBottom,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.panel,
                    border: Border.all(color: theme.line),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('↓ jump to bottom',
                      style: TextStyle(color: theme.dim, fontSize: 12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _groupWidget(BuildContext context, TurnGroup group, int index) {
    final theme = context.watch<AppTheme>();
    if (group.userText != null) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: theme.userBubble,
            border: Border.all(color: theme.userBubbleBorder),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(3),
            ),
          ),
          child: Text(group.userText!,
              style: TextStyle(color: theme.user, fontSize: 13.5)),
        ),
      );
    }

    final entries = group.entries;
    if (entries.length == 1 &&
        (entries.first.type == LogEntryType.system ||
            entries.first.type == LogEntryType.info ||
            entries.first.type == LogEntryType.error)) {
      final e = entries.first;
      final color = e.type == LogEntryType.error ? theme.err : theme.dimmer;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Divider(color: theme.line, height: 1)),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(e.text,
                    style: TextStyle(color: color, fontSize: 11.5, height: 1.4)),
              ),
            ),
            Expanded(child: Divider(color: theme.line, height: 1)),
          ],
        ),
      );
    }

    // Agent group: 2px rail, foldable header, receipts.
    final gist = _gist(entries);
    final toolCount =
        entries.where((e) => e.type == LogEntryType.toolCall).length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.line, width: 2))),
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AgentHeader(
              gist: gist, toolCount: toolCount, expanded: group.expanded, index: index),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: group.expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in entries) _receipt(theme, e),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  String? _gist(List<LogEntry> entries) {
    for (final e in entries) {
      if (e.type == LogEntryType.assistant && e.text.trim().isNotEmpty) {
        return e.text.trim().replaceAll('\n', ' ');
      }
    }
    return null;
  }

  Widget _receipt(AppTheme theme, LogEntry e) {
    switch (e.type) {
      case LogEntryType.toolCall:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '⎿ ', style: TextStyle(color: theme.tool)),
            TextSpan(
                text: e.toolName ?? '',
                style: TextStyle(color: theme.tool, fontSize: 12.5)),
            const TextSpan(text: '  '),
            TextSpan(
                text: _truncate(e.text, 120),
                style: TextStyle(color: theme.dim, fontSize: 12.5)),
          ])),
        );
      case LogEntryType.toolResult:
        return Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 4),
          child: Text('└ ${_truncate(e.text, 160)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: e.text.startsWith('Tool Error') ||
                          e.text.startsWith('Denied')
                      ? theme.err
                      : theme.dimmer,
                  fontSize: 12)),
        );
      case LogEntryType.reasoning:
        return _ThinkingRow(text: e.text);
      case LogEntryType.assistant:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MiniMarkdown(e.text),
        );
      default:
        return Text(e.text, style: TextStyle(color: theme.dim, fontSize: 12.5));
    }
  }
}

/// Foldable agent-group header: gist, tool count, animated caret,
/// hover highlight.
class _AgentHeader extends StatefulWidget {
  const _AgentHeader(
      {required this.gist,
      required this.toolCount,
      required this.expanded,
      required this.index});

  final String? gist;
  final int toolCount;
  final bool expanded;
  final int index;

  @override
  State<_AgentHeader> createState() => _AgentHeaderState();
}

class _AgentHeaderState extends State<_AgentHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    // Inside the selectable stream — disabled selection keeps the fold
    // toggle's click cursor and drag behavior intact.
    return SelectionContainer.disabled(
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => context.read<AppState>().log.toggleFold(widget.index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          // Negative margin would assert in AnimatedContainer's margin
          // lerp; transform achieves the same 6px left overhang safely.
          transform: Matrix4.translationValues(-6, 0, 0),
          decoration: BoxDecoration(
            color: _hover ? theme.panel : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: 'Agent ',
                style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
            if (widget.gist != null)
              TextSpan(
                  text: _truncate(widget.gist!, 60),
                  style: TextStyle(color: theme.dim, fontSize: 11.5)),
            TextSpan(
                text: '  · ${widget.toolCount} tools  ',
                style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
            WidgetSpan(
              child: AnimatedRotation(
                turns: widget.expanded ? 0 : -0.25,
                duration: const Duration(milliseconds: 150),
                child: Text('▾',
                    style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
              ),
            ),
          ])),
        ),
      ),
      ),
    );
  }
}

String _truncate(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

/// 32×32 icon button with hover fill + tooltip — the input bar's quiet
/// actions (mention, commands, settings).
class _IconAction extends StatefulWidget {
  const _IconAction(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? theme.accentDim : Colors.transparent,
              border: Border.all(
                  color: _hover ? theme.accent : theme.line,
                  width: _hover ? 1.5 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 18, color: theme.dim),
          ),
        ),
      ),
    );
  }
}

/// Segmented 3-position mode switch: agent · plan · chat.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});
  final String mode; // 'agent' | 'plan' | 'chat'
  final void Function(String) onChanged;

  static const _segments = ['agent', 'plan', 'chat'];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.bg,
        border: Border.all(color: theme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final s in _segments)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: s == mode ? theme.accentDim : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(
                        color: s == mode ? theme.accent : theme.dim,
                        fontSize: 12.5,
                        fontWeight:
                            s == mode ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Context-token badge, e.g. `1.2k tok`, from the engine usage events.
class _TokenBadge extends StatelessWidget {
  const _TokenBadge({required this.tokens});

  final int tokens;

  static String _format(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${_format(tokens)} tok',
          style: TextStyle(
              color: theme.dimmer,
              fontSize: 10.5,
              fontFamily: 'JetBrains Mono')),
    );
  }
}

/// Primary send button — gold fill when enabled, the only filled control
/// in the bar.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? theme.accentStrong : theme.bg,
            border: Border.all(
                color: enabled ? theme.accentStrong : theme.line, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.arrow_upward,
                  size: 16, color: enabled ? theme.bg : theme.dimmer),
              const SizedBox(width: 7),
              Text('Send',
                  style: TextStyle(
                      color: enabled ? theme.bg : theme.dimmer,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined danger stop button while a turn is running.
class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.err, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.stop, size: 16, color: theme.err),
              const SizedBox(width: 7),
              Text('Stop',
                  style: TextStyle(
                      color: theme.err,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed `⋯ thinking · N chars` row; click to expand the raw text.
class _ThinkingRow extends StatefulWidget {
  const _ThinkingRow({required this.text});

  final String text;

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final lines = '· ${widget.text.split('\n').length} lines';
    // Inside the selectable stream — disable selection on the toggle row.
    return SelectionContainer.disabled(
      child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  _expanded ? '⋯ thinking $lines ▾' : '⋯ thinking $lines ▸',
                  style: TextStyle(color: theme.dimmer, fontSize: 12.5)),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 14, top: 2),
                  child: Text(widget.text,
                      style:
                          TextStyle(color: theme.dim, fontSize: 12, height: 1.4)),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// The streaming tail: deltas + blinking amber cursor.
class _LiveTurn extends StatefulWidget {
  const _LiveTurn();

  @override
  State<_LiveTurn> createState() => _LiveTurnState();
}

class _LiveTurnState extends State<_LiveTurn> {
  bool _visible = true;
  late final StreamSubscription<void>? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream<void>.periodic(const Duration(milliseconds: 550))
        .listen((_) => setState(() => _visible = !_visible));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final streaming = context.watch<StreamingTextNotifier>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.accent, width: 2))),
      padding: const EdgeInsets.only(left: 16),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: streaming.text,
            style: TextStyle(color: theme.ink, fontSize: 13.5, height: 1.5)),
        if (streaming.live)
          WidgetSpan(
            child: Container(
              width: 8,
              height: 15,
              margin: const EdgeInsets.only(left: 2),
              color: _visible ? theme.accent : Colors.transparent,
            ),
          ),
      ])),
    );
  }
}

/// Input bar: multi-line, Enter send / Shift+Enter newline, ↑/↓ history
/// recall, `/` and `@` autocomplete popovers.
class _InputBar extends StatefulWidget {
  const _InputBar();

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _history = <String>[];
  int _historyIndex = -1; // -1 = live text
  String _liveDraft = '';

  List<String> _suggestions = [];
  int _suggestionIndex = 0;
  int _mentionSeq = 0; // token to drop stale/out-of-order file scans

  // Active selector command (/skills, /mcp, /mode): popover shows its
  // sub-options instead of the command list.
  CommandSpec? _selectorCmd;
  int _selectorIndex = 0;

  AppState? _listenedApp;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshSuggestions);
    // Rebuild on keystrokes so the Send button's enabled state tracks input.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen once (the provider above the shell never changes identity).
    final app = context.read<AppState>();
    if (_listenedApp != app) {
      _listenedApp?.removeListener(_onAppNotification);
      _listenedApp = app;
      app.addListener(_onAppNotification);
    }
  }

  @override
  void dispose() {
    _listenedApp?.removeListener(_onAppNotification);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// File-tab actions ("Add to Context" / "Ask AI") and the empty-chat
  /// suggestion chips drop a prefilled text on AppState. Consume it here —
  /// in a listener, never in build/post-frame — so the text mutation doesn't
  /// race SelectionArea's paragraph measurements (debugNeedsLayout assert).
  void _onAppNotification() {
    final pending = _listenedApp?.pendingInput;
    if (pending == null) return;
    _listenedApp!.pendingInput = null;
    _controller.value = TextEditingValue(
      text: pending,
      selection: TextSelection.collapsed(offset: pending.length),
    );
    _focus.requestFocus();
  }

  void _refreshSuggestions() {
    final text = _controller.text;
    List<String> next = const [];
    if (text.startsWith('/') && !text.contains(' ')) {
      next = filterCommands(text).map((c) => c.name).toList();
    } else {
      // @file-mention is workspace-only: at the default home "workspace"
      // (/home/user — huge tree) the recursive scan lags/freezes the UI.
      final isHome = context.read<WorkspaceState>().isHome;
      final m = isHome ? null : RegExp(r'@([\w./-]*)$').firstMatch(text);
      debugPrint('[file-mention] text="$text" match=${m?.group(1)}');
      if (m != null) {
        _loadFileSuggestions(m.group(1)!);
        // Mention scan is in flight — the async completion owns _suggestions.
        // Clearing here (e.g. on a selection-only notify) would wipe results.
        if (!mounted) return;
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _suggestions = next;
      _suggestionIndex = 0;
    });
  }

  Future<void> _loadFileSuggestions(String prefix) async {
    final seq = ++_mentionSeq;
    final cwd = context.read<AppState>().configLoader.projectDir;
    debugPrint('[file-mention] searching root=$cwd prefix="$prefix"');
    final needle = prefix.toLowerCase();
    final matches = <String>[];
    try {
      final stack = <Directory>[Directory(cwd)];
      while (stack.isNotEmpty && matches.length < 20) {
        final d = stack.removeLast();
        for (final entity in d.listSync(followLinks: false)) {
          final name = entity.path.split('/').last;
          if (name.startsWith('.') && name != '.tiny-cli') continue;
          if (entity is Directory) {
            stack.add(entity);
          } else if (name.toLowerCase().contains(needle)) {
            matches.add(entity.path.substring(cwd.length + 1));
            if (matches.length >= 20) break;
          }
        }
      }
    } catch (e) {
      debugPrint('[file-mention] scan failed: $e');
    }
    debugPrint('[file-mention] found ${matches.length} match(es): ${matches.join(", ")}');
    if (!mounted || seq != _mentionSeq) {
      debugPrint('[file-mention] dropped: mounted=$mounted stale=${seq != _mentionSeq}');
      return;
    }
    if (!_controller.text.contains('@')) {
      debugPrint('[file-mention] dropped: mounted=$mounted textHasAt=${_controller.text.contains('@')}');
      return;
    }
    setState(() {
      _suggestions = matches;
      _suggestionIndex = 0;
    });
  }

  // ── Selector commands (plan step 3) ───────────────────────────────

  void _openSelector(CommandSpec spec) {
    _controller.clear();
    setState(() {
      _suggestions = const [];
      _selectorCmd = spec;
      _selectorIndex = 0;
    });
    _focus.requestFocus();
  }

  void _closeSelector() => setState(() => _selectorCmd = null);

  /// One selectable row in the selector popover.
  /// [onPick] toggles/applies; return true to keep the popover open
  /// (multi-select), false to close it (single-select).
  List<_SelectorOption> _selectorOptions(BuildContext context) {
    final app = context.read<AppState>();
    switch (_selectorCmd!.name) {
      case '/skills':
        final skills = discoverSkills(app.configLoader.projectDir, homeDir);
        if (skills.isEmpty) {
          return [
            _SelectorOption(
                label: 'No skills discovered',
                sublabel: '.agents/skills/*/SKILL.md',
                selected: false,
                onPick: (_) => false)
          ];
        }
        return [
          for (final s in skills)
            _SelectorOption(
              label: s.name,
              sublabel: s.description.split('\n').first,
              selected: app.config.activeSkills.contains(s.name),
              onPick: (_) {
                app.toggleSkill(s.name);
                return true; // multi-toggle stays open
              },
            )
        ];
      case '/mcp':
        final servers = app.mcpServers;
        if (servers.isEmpty) {
          return [
            _SelectorOption(
                label: 'No MCP servers configured',
                sublabel: 'Add one in Settings → MCP',
                selected: false,
                onPick: (_) => false)
          ];
        }
        return [
          for (final s in servers)
            _SelectorOption(
              label: s['name'] as String,
              sublabel: '${s['toolCount'] as int? ?? 0} tools wired',
              selected: s['enabled'] as bool? ?? true,
              onPick: (_) {
                app.host.mcpToggle(s['name'] as String,
                    !(s['enabled'] as bool? ?? true));
                return true; // toggle stays open
              },
            )
        ];
      case '/mode':
        return [
          for (final m in PermissionMode.values)
            _SelectorOption(
              label: m.name,
              sublabel: switch (m) {
                PermissionMode.notify => 'Ask before every tool call',
                PermissionMode.autoEdit => 'Auto-approve edits, ask for risky bash',
                PermissionMode.auto => 'No approval prompts',
              },
              selected: app.config.permissionMode == m,
              onPick: (_) {
                app.handleCommand('/mode ${m.name}');
                return false; // single-select closes
              },
            )
        ];
      default:
        return const [];
    }
  }

  void _pickSelectorOption(int i) {
    final opts = _selectorOptions(context);
    if (i >= opts.length) return;
    final keepOpen = opts[i].onPick(i);
    if (!keepOpen) {
      _closeSelector();
    } else {
      setState(() {}); // refresh checkmarks
    }
  }

  void _applySuggestion(String s) {
    final spec = commandByName(s);
    if (spec != null) {
      switch (spec.type) {
        case CommandType.selector:
          _openSelector(spec);
          return;
        case CommandType.input:
          _controller.text = '$s ';
          _controller.selection =
              TextSelection.collapsed(offset: _controller.text.length);
          setState(() => _suggestions = const []);
          return;
        case CommandType.direct:
          _controller.clear();
          setState(() => _suggestions = const []);
          context.read<AppState>().handleCommand(s);
          return;
      }
    }
    final text = _controller.text;
    if (text.startsWith('/') && !text.contains(' ')) {
      _controller.text = '$s ';
    } else {
      _controller.text = text.replaceFirst(RegExp(r'@[\w./-]*$'), '@$s');
    }
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    setState(() => _suggestions = const []);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // Typing a selector command in full gets the same inline picker.
    final spec = commandByName(text);
    if (spec?.type == CommandType.selector) {
      _controller.clear();
      setState(() => _suggestions = const []);
      _openSelector(spec!);
      return;
    }
    if (_history.isEmpty || _history.last != text) _history.add(text);
    _historyIndex = -1;
    _controller.clear();
    context.read<AppState>().send(text);
    _focus.requestFocus();
  }

  void _recall(int delta) {
    if (_history.isEmpty) return;
    if (_historyIndex == -1) {
      _liveDraft = _controller.text;
      _historyIndex = _history.length;
    }
    _historyIndex = (_historyIndex + delta).clamp(0, _history.length);
    _controller.text = _historyIndex == _history.length
        ? _liveDraft
        : _history[_historyIndex];
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final key = e.logicalKey;

    // Selector popover navigation (plan step 5).
    if (_selectorCmd != null) {
      final count = _selectorOptions(context).length;
      if (key == LogicalKeyboardKey.arrowDown && count > 0) {
        setState(() => _selectorIndex = (_selectorIndex + 1) % count);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && count > 0) {
        setState(
            () => _selectorIndex = (_selectorIndex - 1) % count);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter && count > 0) {
        _pickSelectorOption(_selectorIndex.clamp(0, count - 1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _closeSelector();
        return KeyEventResult.handled;
      }
    }

    // Autocomplete navigation takes priority while the popover is open.
    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _suggestionIndex =
            (_suggestionIndex + 1) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _suggestionIndex =
            (_suggestionIndex - 1) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter) {
        _applySuggestion(_suggestions[_suggestionIndex]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _suggestions = const []);
        return KeyEventResult.handled;
      }
    }

    // Esc interrupts the running turn (any queued message is sent right
    // after, when the turn ends).
    if (key == LogicalKeyboardKey.escape &&
        context.read<AppState>().running) {
      context.read<AppState>().interrupt();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp &&
        _controller.text.isEmpty &&
        _history.isNotEmpty) {
      _recall(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && _historyIndex != -1) {
      _recall(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    return Container(
      color: theme.panel,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (_selectorCmd != null)
                  _SelectorPopover(
                    command: _selectorCmd!,
                    options: _selectorOptions(context),
                    selectedIndex: _selectorIndex,
                    onPick: _pickSelectorOption,
                    onClose: _closeSelector,
                  )
                else if (_suggestions.isNotEmpty)
                  _AutocompletePopover(
                    items: _suggestions,
                    selectedIndex: _suggestionIndex,
                    onTap: _applySuggestion,
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.surface3,
                    borderRadius: BorderRadius.circular(AppColors.radiusModal),
                    border: Border.all(color: theme.line),
                    boxShadow: [
                      BoxShadow(
                        color: theme.bg.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Focus(
                        onKeyEvent: _onKey,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 6,
                          style: TextStyle(color: theme.ink, fontSize: 13.5),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Message tiny-code…',
                            hintStyle:
                                TextStyle(color: theme.dimmer, fontSize: 13.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _IconAction(
                            icon: Icons.alternate_email,
                            tooltip: 'Mention a file (@)',
                            onTap: () {
                              _controller.text = '${_controller.text}@';
                              _focus.requestFocus();
                            },
                          ),
                          const SizedBox(width: 4),
                          _IconAction(
                            icon: Icons.bolt_outlined,
                            tooltip: 'Slash commands (/)',
                            onTap: () {
                              _controller.text = '/';
                              _focus.requestFocus();
                            },
                          ),
                          const SizedBox(width: 4),
                          _IconAction(
                            icon: Icons.settings_outlined,
                            tooltip: 'Settings',
                            onTap: () {
                              final app = context.read<AppState>();
                              app.settingsTab = 0;
                              app.showSettings = true;
                            },
                          ),
                          const SizedBox(width: 12),
                          // Segmented mode switch: agent (tools) · plan · chat.
                          // Plan next-send opens the written plan in the
                          // modal; chat sends without tools.
                          _ModeSwitch(
                            mode: app.planMode
                                ? 'plan'
                                : app.chatMode
                                    ? 'chat'
                                    : 'agent',
                            onChanged: (m) {
                              final a = context.read<AppState>();
                              a.planMode = m == 'plan';
                              a.chatMode = m == 'chat';
                              setState(() {});
                            },
                          ),
                          const Spacer(),
                          _TokenBadge(tokens: app.contextTokens),
                          const SizedBox(width: 10),
                          if (app.running)
                            _StopButton(onTap: app.interrupt)
                          else
                            _SendButton(onTap: _send, enabled: _controller
                                    .text.trim()
                                    .isNotEmpty),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Row(
              children: [
                if (app.running)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text('running…',
                        style: TextStyle(color: theme.accent, fontSize: 11.5)),
                  ),
                const Expanded(child: Statusline()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of a selector popover. [onPick] receives the row index and
/// returns whether to keep the popover open (multi-toggle).
class _SelectorOption {
  const _SelectorOption({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onPick,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final bool Function(int index) onPick;
}

/// Sub-options of a selector command (/skills, /mcp, /mode) shown in the
/// same popover slot as the command list — breadcrumb header, clickable
/// rows with a check state, keyboard hint footer.
class _SelectorPopover extends StatelessWidget {
  const _SelectorPopover({
    required this.command,
    required this.options,
    required this.selectedIndex,
    required this.onPick,
    required this.onClose,
  });

  final CommandSpec command;
  final List<_SelectorOption> options;
  final int selectedIndex;
  final void Function(int index) onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final title = command.name.substring(1); // '/skills' → 'Skills'
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: theme.surface3,
        borderRadius: BorderRadius.circular(AppColors.radiusModal),
        border: Border.all(color: theme.line),
        boxShadow: [
          BoxShadow(
            color: theme.bg.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb header: Commands › Skills + close.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
            child: Row(
              children: [
                Text('COMMANDS',
                    style: TextStyle(
                        color: theme.dimmer,
                        fontSize: 10,
                        letterSpacing: 0.8)),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 13, color: theme.dimmer),
                const SizedBox(width: 6),
                Text(title.toUpperCase(),
                    style: TextStyle(
                        color: theme.accent,
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 15, color: theme.dimmer),
                  tooltip: 'Close (Esc)',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.line),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final opt = options[i];
                final highlighted = i == selectedIndex;
                return InkWell(
                  onTap: () => onPick(i),
                  onHover: (_) {},
                  child: Container(
                    color: highlighted ? theme.hover : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          child: Icon(
                            opt.selected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 16,
                            color: opt.selected
                                ? theme.tool
                                : theme.dimmer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opt.label,
                                  style: TextStyle(
                                      color: theme.ink, fontSize: 13)),
                              if (opt.sublabel.isNotEmpty)
                                Text(opt.sublabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: theme.dim, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text('↑↓ navigate · ⏎ select · Esc close',
                style: TextStyle(color: theme.dimmer, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }
}

/// Overlay list of suggestions above the input. Fixed-height rows with a
/// ScrollController that keeps the highlighted item in view (keyboard
/// navigation scrolls the list; the wheel works via AlwaysScrollableScrollPhysics).
class _AutocompletePopover extends StatefulWidget {
  const _AutocompletePopover(
      {required this.items, required this.selectedIndex, required this.onTap});

  final List<String> items;
  final int selectedIndex;
  final void Function(String) onTap;

  @override
  State<_AutocompletePopover> createState() => _AutocompletePopoverState();
}

class _AutocompletePopoverState extends State<_AutocompletePopover> {
  static const double _rowExtent = 34;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_AutocompletePopover old) {
    super.didUpdateWidget(old);
    if (widget.selectedIndex != old.selectedIndex) _ensureSelectedVisible();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
  }

  void _ensureSelectedVisible() {
    if (!_scroll.hasClients) return;
    final top = widget.selectedIndex * _rowExtent;
    final bottom = top + _rowExtent;
    var offset = _scroll.offset;
    if (top < offset) {
      offset = top;
    } else if (bottom > offset + _scroll.position.viewportDimension) {
      offset = bottom - _scroll.position.viewportDimension;
    }
    if (offset != _scroll.offset) _scroll.jumpTo(offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: theme.panel,
        border: Border.all(color: theme.line),
        borderRadius: BorderRadius.circular(10),
      ),
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _rowExtent,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: widget.items.length,
        itemBuilder: (context, i) {
          final selected = i == widget.selectedIndex;
          final spec = commandHint(widget.items[i]);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.onTap(widget.items[i]),
              child: Container(
                alignment: Alignment.centerLeft,
                color: selected ? theme.accentDim : Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(widget.items[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: selected ? theme.accent : theme.tool,
                              fontSize: 12.5,
                              fontFamily: widget.items[i].startsWith('/')
                                  ? null
                                  : 'monospace')),
                    ),
                    if (spec != null) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(spec,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: theme.dimmer, fontSize: 11.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? commandHint(String name) {
    for (final c in kCommands) {
      if (c.name == name) return '${c.argsHint}  — ${c.description}'.trim();
    }
    return null;
  }
}
