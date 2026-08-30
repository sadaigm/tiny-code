import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Plan tab: overall progress bar plus a read-only step checklist.
/// Steps are done (green check) / current first-open (teal spinner) /
/// pending (dim). Manual toggling is not supported by the plan store yet.
class PlanTab extends StatelessWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final steps = context.watch<AppState>().planSteps;

    if (steps.isEmpty) {
      return Center(
        heightFactor: 6,
        child: Text('No active plan. Ask in plan mode to generate steps.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.dimmer, fontSize: 12.5)),
      );
    }

    final done = steps.where((s) => s.done).length;
    final current = steps.indexWhere((s) => !s.done);
    // Plan steps are read-only content — selectable for copy.
    return SelectionArea(
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: steps.isEmpty ? 0 : done / steps.length,
            minHeight: 4,
            backgroundColor: theme.surface2,
            valueColor: AlwaysStoppedAnimation(theme.accent),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Text('$done of ${steps.length} steps',
              style: TextStyle(color: theme.dimmer, fontSize: 11)),
        ),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: steps[i].done
                      ? Icon(Icons.check_circle, size: 15, color: theme.ok)
                      : i == current
                          ? SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.6, color: theme.secondary))
                          : Icon(Icons.radio_button_unchecked,
                              size: 14, color: theme.dimmer),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    steps[i].text,
                    style: TextStyle(
                      color: steps[i].done
                          ? theme.dimmer
                          : i == current
                              ? theme.ink
                              : theme.dim,
                      fontSize: 12,
                      height: 1.35,
                      decoration:
                          steps[i].done ? TextDecoration.lineThrough : null,
                      decorationColor: theme.dimmer,
                    ),
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
