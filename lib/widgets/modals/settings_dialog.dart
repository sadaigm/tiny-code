import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Dark/light toggle — applies immediately (the whole app watches
/// AppTheme, so no OK needed).
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Row(
      children: [
        for (final mode in const ['dark', 'light'])
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context.read<AppTheme>().setDark(mode == 'dark'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (theme.isDark ? mode == 'dark' : mode == 'light')
                      ? theme.accentDim
                      : theme.bg,
                  border: Border.all(
                      color: (theme.isDark ? mode == 'dark' : mode == 'light')
                          ? theme.accent
                          : theme.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                        mode == 'dark'
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        size: 15,
                        color: (theme.isDark ? mode == 'dark' : mode == 'light')
                            ? theme.accent
                            : theme.dim),
                    const SizedBox(width: 6),
                    Text(mode,
                        style: TextStyle(
                            color:
                                (theme.isDark ? mode == 'dark' : mode == 'light')
                                    ? theme.accent
                                    : theme.dim,
                            fontSize: 12.5)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ⚙ Settings panel: three tabs (Mode / Context / Session). Everything
/// that has options is a clickable control; OK applies for the session,
/// Save also persists to agents.json `settings`. See setting_plan.md.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, this.initialTab = 0});

  /// Tab to open on (2 = MCP servers, used by the /mcp command).
  final int initialTab;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _tab = 0;
  late PermissionMode _perm;
  late String _agentMode; // 'agent' | 'plan' | 'chat'
  final _compactFocus = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _tab = widget.initialTab.clamp(0, 3);
    _perm = app.config.permissionMode;
    _agentMode = app.planMode
        ? 'plan'
        : app.chatMode
            ? 'chat'
            : 'agent';
  }

  @override
  void dispose() {
    _compactFocus.dispose();
    super.dispose();
  }

  void _apply({bool save = false}) {
    final app = context.read<AppState>();
    app.applySettings(
      permissionMode: _perm,
      planMode: _agentMode == 'plan',
      chatMode: _agentMode == 'chat',
    );
    if (save) app.saveSettings();
    app.showSettings = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    final size = MediaQuery.sizeOf(context);
    const nav = ['General', 'Agent permissions', 'MCP servers', 'Shortcuts'];

    return BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        color: theme.bg.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Container(
          width: math.min(800, size.width * 0.85),
          height: math.min(600, size.height * 0.85),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.panel,
            border: Border.all(color: theme.line),
            borderRadius: BorderRadius.circular(AppColors.radiusModal),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings',
                  style: TextStyle(
                      color: theme.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < nav.length; i++)
                            _NavItem(
                              label: nav[i],
                              selected: _tab == i,
                              onTap: () => setState(() => _tab = i),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _pageContent(theme, app),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        context.read<AppState>().showSettings = false,
                    style: TextButton.styleFrom(foregroundColor: theme.dim),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _apply(),
                    style: TextButton.styleFrom(foregroundColor: theme.dim),
                    child: const Text('OK', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _apply(save: true),
                    style: TextButton.styleFrom(
                      backgroundColor: theme.accentDim,
                      foregroundColor: theme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child:
                        const Text('Save changes', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pages: 0 General · 1 Agent permissions · 2 MCP servers · 3 Shortcuts.
  Widget _pageContent(AppTheme theme, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tab == 0) ...[
          _Label('Theme', theme),
          const _ThemeToggle(),
          const SizedBox(height: 18),
          _Label('Default agent mode', theme),
          _PillRow(
            options: const ['agent', 'plan', 'chat'],
            selected: _agentMode,
            onSelect: (v) => setState(() => _agentMode = v),
          ),
          const SizedBox(height: 6),
          Text('plan — research & write a plan · chat — reply without tools',
              style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
          const SizedBox(height: 18),
          _Label('Compact now', theme),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _compactFocus,
                  style: TextStyle(color: theme.ink, fontSize: 12.5),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: theme.line)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    hintText: 'optional focus instructions',
                    hintStyle: TextStyle(color: theme.dimmer, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context
                    .read<AppState>()
                    .host
                    .requestCompact(_compactFocus.text.trim()),
                style: TextButton.styleFrom(
                    backgroundColor: theme.accentDim,
                    foregroundColor: theme.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8)),
                child: const Text('Compact', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              'Summarizes the conversation so far into a short context summary '
              '(auto-runs at ~${app.config.compactionThresholdTokens} tokens).',
              style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
          const SizedBox(height: 18),
          _Label('Loaded profile (agents.json)', theme),
          _InfoRow('Session', app.activeSessionId ?? '(unsaved)', theme),
          _InfoRow('Model', app.config.model, theme),
          _InfoRow('Endpoint', app.config.endpoint, theme),
          _InfoRow('Temperature',
              app.config.temperature?.toString() ?? 'default', theme),
          _InfoRow('Max iterations', '${app.config.maxIterations}', theme),
          _InfoRow('Compact threshold',
              '~${app.config.compactionThresholdTokens} tokens', theme),
          _InfoRow('Compact retain',
              '~${app.config.compactionRetainTokens} tokens', theme),
          _InfoRow('Skills', '${app.config.activeSkills.length} active', theme),
        ],
        if (_tab == 1) ...[
          _Label('Permission mode', theme),
          _PillRow(
            options: const ['notify', 'autoEdit', 'auto'],
            selected: _perm.name,
            onSelect: (v) =>
                setState(() => _perm = PermissionMode.values.byName(v)),
          ),
          const SizedBox(height: 6),
          Text(
              'notify — approve every tool · autoEdit — auto-approve edits · auto — approve all',
              style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
          const SizedBox(height: 18),
          _ActionRow(
            label: 'Running turn',
            button: 'Stop',
            onPressed: () {
              app.interrupt();
              app.showSettings = false;
            },
            theme: theme,
          ),
          _ActionRow(
            label: 'Message stream',
            button: 'Clear',
            onPressed: () {
              app.log.clear();
              app.showSettings = false;
            },
            theme: theme,
          ),
        ],
        if (_tab == 2) ...[
          _Label('MCP Tool Servers', theme),
          Builder(builder: (context) {
            final servers = app.mcpServers.isEmpty
                ? [
                    for (final s in app.config.mcpServers)
                      {
                        'name': s.name,
                        'enabled': true,
                        'toolCount': 0,
                        'connected': false,
                        'tools': const <Map<String, dynamic>>[],
                      }
                  ]
                : app.mcpServers;
            final wired = servers
                .where((s) =>
                    (s['connected'] as bool? ?? true) &&
                    (s['enabled'] as bool? ?? true))
                .length;
            final toolTotal = servers.fold<int>(
                0,
                (n, s) => n +
                    ((s['connected'] as bool? ?? true) &&
                            (s['enabled'] as bool? ?? true)
                        ? (s['toolCount'] as int? ?? 0)
                        : 0));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (servers.isEmpty)
                  Text('No servers configured (agents.json mcpServers)',
                      style: TextStyle(color: theme.dimmer, fontSize: 12.5))
                else ...[
                  Text(
                      '$wired of ${servers.length} wired · '
                      '$toolTotal tools in context',
                      style: TextStyle(
                          color: theme.dimmer,
                          fontSize: 10.5,
                          fontFamily: 'JetBrains Mono')),
                  const SizedBox(height: 8),
                  for (final s in servers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _McpServerCard(map: s),
                    ),
                ],
              ],
            );
          }),
        ],
        if (_tab == 3) ...[
          _InfoRow('New chat', 'Ctrl+N', theme),
          _InfoRow('Toggle sidebar', 'Ctrl+B', theme),
          _InfoRow('Toggle context panel', 'Ctrl+Shift+B', theme),
          _InfoRow('Search chats', 'Ctrl+K', theme),
          _InfoRow('Send message', 'Enter', theme),
          _InfoRow('Message history', '↑ / ↓ (empty input)', theme),
        ],
      ],
    );
  }
}

/// Vertical nav entry in the settings modal's left column.
class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? theme.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radius),
            border: Border(
                left: BorderSide(
                    color: selected ? theme.accent : Colors.transparent,
                    width: 3)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? theme.ink : theme.dim, fontSize: 12.5)),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.theme);
  final String text;
  final AppTheme theme;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                color: theme.dim,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      );
}

/// Radio-pill row for single-choice options.
class _PillRow extends StatelessWidget {
  const _PillRow(
      {required this.options, required this.selected, required this.onSelect});
  final List<String> options;
  final String selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Row(
      children: [
        for (final o in options)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onSelect(o),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: o == selected ? theme.accentDim : theme.bg,
                  border: Border.all(
                      color: o == selected ? theme.accent : theme.line),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(o,
                    style: TextStyle(
                        color: o == selected ? theme.accent : theme.dim,
                        fontSize: 12.5)),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(
      {required this.label,
      required this.button,
      required this.onPressed,
      required this.theme});
  final String label;
  final String button;
  final VoidCallback onPressed;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(color: theme.dim, fontSize: 12.5))),
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                  foregroundColor: theme.dim,
                  side: BorderSide(color: theme.line),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
              child: Text(button, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, this.theme);
  final String label;
  final String value;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(label,
                  style: TextStyle(color: theme.dimmer, fontSize: 12)),
            ),
            Expanded(
                child: Text(value,
                    style: TextStyle(color: theme.dim, fontSize: 12))),
          ],
        ),
      );
}

/// One MCP server in the settings tab: expansion card with status dot,
/// tool-count subtitle, reconnect/enable/delete controls, and the tool
/// list in the expanded body.
class _McpServerCard extends StatelessWidget {
  const _McpServerCard({required this.map});

  final Map<String, dynamic> map;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final name = map['name'] as String;
    final connected = map['connected'] as bool? ?? false;
    final enabled = map['enabled'] as bool? ?? true;
    final toolCount = map['toolCount'] as int? ?? 0;
    final tools = (map['tools'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.surface2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.line),
        borderRadius: BorderRadius.circular(AppColors.radius),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          dense: true,
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? const Color(0xFF4CAF50) : theme.err,
            ),
          ),
          title: Text(name,
              style: TextStyle(
                  color: theme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          subtitle: Text('$toolCount tools wired',
              style: TextStyle(color: theme.dim, fontSize: 11.5)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Reconnect $name',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.refresh, size: 18),
                color: theme.dim,
                onPressed: () => context.read<AppState>().host.mcpReconnect(name),
              ),
              Switch(
                value: enabled,
                activeThumbColor: theme.accent,
                onChanged: (v) => context.read<AppState>().host.mcpToggle(name, v),
              ),
              IconButton(
                tooltip: 'Delete $name',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: theme.dim,
                onPressed: () => context.read<AppState>().mcpDelete(name),
              ),
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: theme.panel,
              child: tools.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('(no tools / not connected)',
                          style:
                              TextStyle(color: theme.dimmer, fontSize: 11)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final t in tools)
                          ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              t['name'] as String? ?? '',
                              style: TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11.5,
                                  color: theme.ink,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              t['description'] as String? ?? '',
                              style: TextStyle(
                                  color: theme.dimmer, fontSize: 11),
                            ),
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
