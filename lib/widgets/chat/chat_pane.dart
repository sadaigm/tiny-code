import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/command_registry.dart';
import '../../state/workspace.dart';
import '../../theme/app_theme.dart';
import '../../state/log_store.dart';
import '../markview/markdown.dart';
import '../modals/approval_dialog.dart';
import '../modals/mcp_picker.dart';
import '../modals/option_picker.dart';
import '../modals/plan_confirm_dialog.dart';
import '../modals/recovery_dialog.dart';
import '../modals/settings_dialog.dart';
import 'statusline.dart';

/// Middle pane: topbar, message stream, input bar, statusline.
class ChatPane extends StatelessWidget {
  const ChatPane({super.key});

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
              _Topbar(),
              Expanded(child: _TurnList()),
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
        if (app.showMcpPicker) const McpPickerDialog(),
        if (app.showModePicker) const ModePickerDialog(),
        if (app.showSkillPicker) const SkillPickerDialog(),
        if (app.showSettings) const SettingsDialog(),
      ],
    );
  }
}

class _Topbar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: theme.line))),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Text('New chat',
              style: TextStyle(
                  color: theme.ink, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            context.watch<AppState>().running ? 'running…' : 'idle',
            style: TextStyle(color: theme.dim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Message stream with auto-follow: sticks to the bottom while streaming,
/// wheel-up exits follow into browse, pill jumps back.
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
          Center(
            child: Text('Message tiny-code…',
                style: TextStyle(color: theme.dimmer, fontSize: 13)),
          )
        else
          ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: groups.length + (app.running ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == groups.length) return const _LiveTurn();
              return _groupWidget(context, groups[i], i);
            },
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
    return MouseRegion(
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

/// Primary send button — the only filled control in the bar.
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
            color: enabled ? theme.accentDim : theme.bg,
            border: Border.all(
                color: enabled ? theme.accent : theme.line, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.arrow_upward,
                  size: 16,
                  color: enabled ? theme.accent : theme.dimmer),
              const SizedBox(width: 7),
              Text('Send',
                  style: TextStyle(
                      color: enabled ? theme.accent : theme.dimmer,
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
    return MouseRegion(
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshSuggestions);
    // Rebuild on keystrokes so the Send button's enabled state tracks input.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
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
      debugPrint('[file-mention] text="$text" match=${m == null ? null : m.group(1)}');
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

  void _applySuggestion(String s) {
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
                if (_suggestions.isNotEmpty)
                  _AutocompletePopover(
                    items: _suggestions,
                    selectedIndex: _suggestionIndex,
                    onTap: _applySuggestion,
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.line),
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
                            onTap: () =>
                                context.read<AppState>().showSettings = true,
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
