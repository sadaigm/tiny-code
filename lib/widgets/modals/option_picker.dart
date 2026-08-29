import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart' show PermissionMode;
import '../../engine/skills.dart' show discoverSkills;
import '../../platform_env_io.dart' show homeDir;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// /mode picker — radio rows; tapping a mode applies it immediately
/// (persists via saveSettings) and closes.
class ModePickerDialog extends StatelessWidget {
  const ModePickerDialog({super.key});

  static const _labels = {
    PermissionMode.notify: ('notify', 'Ask before every tool call'),
    PermissionMode.autoEdit: ('auto-edit', 'Auto-approve edits, ask for the rest'),
    PermissionMode.auto: ('auto', 'Auto-approve everything'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    return _Frame(
      title: 'Permission mode',
      theme: theme,
      child: Column(
        children: [
          for (final m in PermissionMode.values)
            _RadioRow(
              theme: theme,
              label: _labels[m]!.$1,
              description: _labels[m]!.$2,
              selected: app.config.permissionMode == m,
              onTap: () {
                app.applySettings(permissionMode: m);
                app.saveSettings();
                app.showModePicker = false;
              },
            ),
        ],
      ),
    );
  }
}

/// /skills picker — switch rows; toggles apply live, Done closes.
/// The next turn's system prompt picks up the new active set.
class SkillPickerDialog extends StatelessWidget {
  const SkillPickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    final skills = discoverSkills(app.configLoader.projectDir, homeDir);
    if (skills.isEmpty) {
      return _Frame(
        title: 'Skills',
        theme: theme,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'No skills discovered (.agents/skills/*/SKILL.md)',
            style: TextStyle(color: theme.dim, fontSize: 13),
          ),
        ),
      );
    }
    return _Frame(
      title: 'Skills',
      theme: theme,
      footer: TextButton(
        onPressed: () => app.showSkillPicker = false,
        child: const Text('Done'),
      ),
      child: Column(
        children: [
          for (final s in skills)
          SwitchListTile(
            value: app.config.activeSkills.contains(s.name),
            onChanged: (_) => app.toggleSkill(s.name),
            activeColor: theme.tool,
            title: Text(s.name,
                style: TextStyle(color: theme.ink, fontSize: 13)),
            subtitle: Text(
              s.description.split('\n').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.dim, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame(
      {required this.title, required this.theme, required this.child, this.footer});

  final String title;
  final AppTheme theme;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
        decoration: BoxDecoration(
          color: theme.panel,
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(title,
                  style: TextStyle(
                      color: theme.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            Flexible(child: SingleChildScrollView(child: child)),
            if (footer != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: footer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.theme,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: selected ? theme.tool : theme.dimmer,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: selected ? theme.ink : theme.dim,
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : null)),
                Text(description,
                    style: TextStyle(color: theme.dim, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
