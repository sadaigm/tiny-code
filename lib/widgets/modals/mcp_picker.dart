import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../mcp_patch_row.dart';

/// /mcp picker — patch-panel style (see mcp-manager-design.html): each
/// server leads with a "cable" whose state encodes the connection
/// (teal pulse = live, flat = off, broken red = dead), a toggle that
/// hides its tools from the model, a reconnect button, and an accordion
/// drawer listing the server's tools.
class McpPickerDialog extends StatelessWidget {
  const McpPickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    final servers = app.mcpServers.isEmpty
        ? [
            for (final s in app.config.mcpServers)
              {'name': s.name, 'enabled': true, 'toolCount': 0}
          ]
        : app.mcpServers;

    final wired = servers
        .where((s) => (s['connected'] as bool? ?? true) && (s['enabled'] as bool? ?? true))
        .length;
    final toolTotal = servers.fold<int>(
        0,
        (n, s) => n +
            ((s['connected'] as bool? ?? true) && (s['enabled'] as bool? ?? true)
                ? (s['toolCount'] as int? ?? 0)
                : 0));

    return Center(
      child: Container(
        width: 480,
        // Fixed height so the dialog doesn't resize as rows expand —
        // the drawer scrolls inside instead of growing the panel.
        height: 560,
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
        decoration: BoxDecoration(
          color: theme.panel,
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MCP servers',
                      style: TextStyle(
                          color: theme.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                      'Tool servers wired into this session. Flip a switch to '
                      'drop its tools; reconnect to re-read them.',
                      style: TextStyle(color: theme.dim, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (servers.isEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('No servers configured (agents.json mcpServers)',
                      style: TextStyle(color: theme.dimmer, fontSize: 12.5)),
                ),
              )
            else
              Expanded(
                // Tight fit: the list area fills the fixed-height panel so
                // the footer stays pinned to the bottom even when the rows
                // are short/collapsed.
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in servers)
                        McpPatchRow(
                          name: s['name'] as String,
                          toolCount: s['toolCount'] as int? ?? 0,
                          enabled: s['enabled'] as bool? ?? true,
                          connected: s['connected'] as bool? ?? true,
                          tools: (s['tools'] as List<dynamic>? ?? const [])
                              .whereType<Map<String, dynamic>>()
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Footer: wired counts + tools in context.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.line)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(13)),
              ),
              child: servers.isEmpty
                  ? TextButton(
                      onPressed: () => app.showMcpPicker = false,
                      style:
                          TextButton.styleFrom(foregroundColor: theme.dim),
                      child: const Text('Close',
                          style: TextStyle(fontSize: 13)),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                              '$wired of ${servers.length} wired · '
                              '$toolTotal tools in context',
                              style: TextStyle(
                                  color: theme.dimmer,
                                  fontSize: 10.5,
                                  fontFamily: 'JetBrains Mono')),
                        ),
                        TextButton(
                          onPressed: () => app.showMcpPicker = false,
                          style: TextButton.styleFrom(
                              foregroundColor: theme.dim,
                              minimumSize: const Size(0, 28)),
                          child:
                              const Text('Close', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
