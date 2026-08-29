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
  const SettingsDialog({super.key});

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
    const tabs = ['Mode', 'Context', 'Session'];

    return Center(
      child: Container(
        width: 520,
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.panel,
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings',
                style: TextStyle(
                    color: theme.ink, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _TabButton(
                    label: tabs[i],
                    selected: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_tab == 0) ...[
              _Label('Theme', theme),
              const _ThemeToggle(),
              const SizedBox(height: 18),
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
              _Label('Default agent mode', theme),
              _PillRow(
                options: const ['agent', 'plan', 'chat'],
                selected: _agentMode,
                onSelect: (v) => setState(() => _agentMode = v),
              ),
              const SizedBox(height: 6),
              Text('plan — research & write a plan · chat — reply without tools',
                  style: TextStyle(color: theme.dimmer, fontSize: 11.5)),
            ],
            if (_tab == 1) ...[
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
                        hintStyle:
                            TextStyle(color: theme.dimmer, fontSize: 12),
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
            ],
            if (_tab == 2) ...[
              _ActionRow(
                label: 'MCP servers',
                button: 'Manage',
                onPressed: () {
                  app.showSettings = false;
                  app.showMcpPicker = true;
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
              _ActionRow(
                label: 'Running turn',
                button: 'Stop',
                onPressed: () {
                  app.interrupt();
                  app.showSettings = false;
                },
                theme: theme,
              ),
              const SizedBox(height: 10),
              _Label('Loaded profile (agents.json)', theme),
              _InfoRow('Session', app.activeSessionId ?? '(unsaved)', theme),
              _InfoRow('Model', app.config.model, theme),
              _InfoRow('Endpoint', app.config.endpoint, theme),
              _InfoRow('Temperature',
                  app.config.temperature?.toString() ?? 'default', theme),
              _InfoRow('Max iterations',
                  '${app.config.maxIterations}', theme),
              _InfoRow('Compact threshold',
                  '~${app.config.compactionThresholdTokens} tokens', theme),
              _InfoRow('Compact retain',
                  '~${app.config.compactionRetainTokens} tokens', theme),
              _InfoRow(
                  'Skills', '${app.config.activeSkills.length} active', theme),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => context.read<AppState>().showSettings = false,
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
                  child: const Text('Save', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton(
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? theme.accentDim : Colors.transparent,
            border: Border(bottom: BorderSide(
                color: selected ? theme.accent : Colors.transparent, width: 2)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? theme.accent : theme.dim, fontSize: 12.5)),
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
