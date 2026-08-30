import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/log_store.dart';
import '../../theme/app_theme.dart';

/// Thoughts tab: streaming reasoning entries plus a raw tool-call log.
/// Clear empties the view; the autoscroll toggle pins the log to the
/// latest entry.
class ThoughtsTab extends StatefulWidget {
  const ThoughtsTab({super.key});

  @override
  State<ThoughtsTab> createState() => _ThoughtsTabState();
}

class _ThoughtsTabState extends State<ThoughtsTab> {
  final _controller = ScrollController();
  bool _autoscroll = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    if (!_autoscroll || !_controller.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final log = context.watch<LogStore>();
    _jumpToBottom();

    final reasoning = log.entries
        .where((e) =>
            e.type == LogEntryType.reasoning && e.text.trim().isNotEmpty)
        .toList();
    final toolCalls = log.entries
        .where((e) => e.type == LogEntryType.toolCall)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text('REASONING',
                    style: TextStyle(
                        color: theme.dimmer,
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
              ),
              _ToggleChip(
                label: 'Autoscroll',
                active: _autoscroll,
                onTap: () => setState(() => _autoscroll = !_autoscroll),
              ),
              const SizedBox(width: 4),
              _ToggleChip(
                label: 'Clear',
                active: false,
                onTap: () => log.clear(),
              ),
            ],
          ),
        ),
        Expanded(
          // Reasoning + tool log are content: drag-selectable.
          child: SelectionArea(
            child: ListView(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (reasoning.isEmpty && toolCalls.isEmpty)
                Text('No thoughts yet',
                    style: TextStyle(color: theme.dimmer, fontSize: 12.5)),
              for (final e in reasoning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(e.text,
                      style: TextStyle(
                          color: theme.dim,
                          fontSize: 12,
                          height: 1.45,
                          fontFamily: 'JetBrains Mono')),
                ),
              if (toolCalls.isNotEmpty) ...[
                Text('TOOL CALLS',
                    style: TextStyle(
                        color: theme.dimmer,
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                for (final e in toolCalls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '· ${e.toolName ?? 'tool'}  ${e.text}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.dimmer,
                          fontSize: 11,
                          fontFamily: 'JetBrains Mono'),
                    ),
                  ),
              ],
            ],
          ),
          ),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active ? theme.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.line),
            ),
            child: Text(label,
                style: TextStyle(color: theme.dim, fontSize: 10.5)),
          ),
        ),
      ),
    );
  }
}
