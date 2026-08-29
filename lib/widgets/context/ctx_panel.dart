import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/log_store.dart';
import '../../theme/app_theme.dart';
import 'accordion_panel.dart';
import 'file_tree.dart';

/// Right pane, split into two vertically stacked accordion panels:
/// "Working files" (top) and "Thoughts" (bottom, latest reasoning).
/// Collapsing one gives the other the freed space.
class CtxPanel extends StatefulWidget {
  const CtxPanel({super.key, required this.width});

  final double width;

  @override
  State<CtxPanel> createState() => _CtxPanelState();
}

class _CtxPanelState extends State<CtxPanel> {
  bool _filesCollapsed = false;
  bool _thoughtsCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();

    return Container(
      width: widget.width,
      color: theme.panel,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccordionPanel(
            title: 'Working files',
            collapsed: _filesCollapsed,
            onToggle: () => setState(() => _filesCollapsed = !_filesCollapsed),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                    title: 'Active plan',
                    empty: 'No plan yet',
                    child: _PlanSteps(app: app, theme: theme)),
                const SizedBox(height: 20),
                _Section(
                    title: 'Working files',
                    empty: 'No files touched',
                    child: _WorkingFiles(app: app, theme: theme)),
                const SizedBox(height: 20),
                _Section(
                    title: 'Workspace files',
                    empty: 'Empty workspace',
                    child: FileTree(root: app.configLoader.projectDir)),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.line),
          AccordionPanel(
            title: 'Thoughts',
            collapsed: _thoughtsCollapsed,
            onToggle: () =>
                setState(() => _thoughtsCollapsed = !_thoughtsCollapsed),
            child: _Thoughts(app: app, theme: theme),
          ),
        ],
      ),
    );
  }
}

/// Latest reasoning entry from the log, streaming-friendly.
class _Thoughts extends StatelessWidget {
  const _Thoughts({required this.app, required this.theme});

  final AppState app;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    String? text;
    for (final e in app.log.entries) {
      if (e.type == LogEntryType.reasoning && e.text.trim().isNotEmpty) {
        text = e.text;
      }
    }
    if (text == null || text.trim().isEmpty) {
      return Text('No thoughts yet',
          style: TextStyle(color: theme.dimmer, fontSize: 12.5));
    }
    return Text(text,
        style: TextStyle(color: theme.dim, fontSize: 12, height: 1.45));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.empty, required this.child});

  final String title;
  final String empty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                color: theme.dimmer,
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Plan checklist: done struck-dim, current (first open) amber.
class _PlanSteps extends StatelessWidget {
  const _PlanSteps({required this.app, required this.theme});

  final AppState app;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final steps = app.planSteps;
    if (steps.isEmpty) {
      return Text('No plan yet',
          style: TextStyle(color: theme.dimmer, fontSize: 12.5));
    }
    final current = steps.indexWhere((s) => !s.done);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${i + 1}  ',
                    style: TextStyle(color: theme.dimmer, fontSize: 12)),
                TextSpan(
                  text: steps[i].text,
                  style: TextStyle(
                    color: steps[i].done
                        ? theme.dimmer
                        : i == current
                            ? theme.accent
                            : theme.dim,
                    fontSize: 12,
                    decoration:
                        steps[i].done ? TextDecoration.lineThrough : null,
                    decorationColor: theme.dimmer,
                  ),
                ),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// Files touched by write/edit tools this session, newest last.
class _WorkingFiles extends StatelessWidget {
  const _WorkingFiles({required this.app, required this.theme});

  final AppState app;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final files = app.workingFiles.toList();
    if (files.isEmpty) {
      return Text('No files touched',
          style: TextStyle(color: theme.dimmer, fontSize: 12.5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(f,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.tool, fontSize: 11.5, fontFamily: 'monospace')),
          ),
      ],
    );
  }
}
