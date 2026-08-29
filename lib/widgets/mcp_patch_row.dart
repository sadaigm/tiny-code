import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'mcp_cable.dart';

/// One MCP server row (patch-panel style, see mcp-manager-design-spec.md):
/// cable rail + name/meta + switch + reconnect, with an expandable tool
/// drawer underneath. Clicking the header (not the controls) toggles the
/// drawer.
class McpPatchRow extends StatefulWidget {
  const McpPatchRow(
      {super.key,
      required this.name,
      required this.toolCount,
      required this.enabled,
      required this.connected,
      this.tools = const []});

  final String name;
  final int toolCount;
  final bool enabled;
  final bool connected;
  final List<Map<String, dynamic>> tools;

  @override
  State<McpPatchRow> createState() => _McpPatchRowState();
}

class _McpPatchRowState extends State<McpPatchRow>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: false);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  CableState get _state => !widget.connected
      ? CableState.dead
      : widget.enabled
          ? CableState.live
          : CableState.off;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.read<AppState>();
    final state = _state;

    final metaColor =
        state == CableState.dead ? theme.err : theme.dimmer;
    final meta = switch (state) {
      CableState.dead => 'offline',
      CableState.off =>
        '${widget.toolCount} tools · off — hidden from the model',
      CableState.live => '${widget.toolCount} tools',
    };

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.tools.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  McpCable(state: state, pulse: _pulse),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.name,
                              style: TextStyle(
                                  color: theme.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(meta,
                              style: TextStyle(
                                  color: metaColor,
                                  fontSize: 10.5,
                                  fontFamily: 'JetBrains Mono')),
                        ],
                      ),
                    ),
                  ),
                  Switch(
                    value: widget.enabled,
                    activeThumbColor: theme.tool,
                    activeTrackColor: theme.line,
                    onChanged: (v) => app.host.mcpToggle(widget.name, v),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    // Kills the child process and re-runs connect +
                    // tools/list — picks up tools added/removed server-side.
                    onPressed: () => app.host.mcpReconnect(widget.name),
                    style: TextButton.styleFrom(
                        foregroundColor: theme.dim,
                        side: BorderSide(color: theme.line),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        minimumSize: const Size(0, 26),
                        textStyle: const TextStyle(
                            fontSize: 10.5, fontFamily: 'JetBrains Mono')),
                    child: const Text('reconnect'),
                  ),
                  if (widget.tools.isNotEmpty)
                    Text(_expanded ? '▾' : '▸',
                        style:
                            TextStyle(color: theme.dimmer, fontSize: 11)),
                ],
              ),
            ),
          ),
          if (_expanded && widget.tools.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(40, 10, 16, 12),
              decoration: BoxDecoration(
                color: theme.stream,
                border: Border(top: BorderSide(color: theme.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in widget.tools)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['name'] as String,
                              style: TextStyle(
                                  color: theme.tool,
                                  fontSize: 11.5,
                                  fontFamily: 'JetBrains Mono')),
                          if ((t['description'] as String?)?.isNotEmpty ==
                              true)
                            Text(t['description'] as String,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: theme.dim, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
