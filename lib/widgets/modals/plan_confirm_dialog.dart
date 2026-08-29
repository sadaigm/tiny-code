import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../markview/markdown.dart';

/// Plan-mode confirm: shows the written plan; confirm → execute, regenerate
/// → re-run the plan request, close → keep the plan without executing.
class PlanConfirmDialog extends StatelessWidget {
  const PlanConfirmDialog({super.key, required this.plan});

  final String plan;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Center(
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 560),
        margin: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: theme.panel,
          border: Border.all(color: theme.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Proposed plan',
                  style: TextStyle(
                      color: theme.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            Divider(height: 1, thickness: 1, color: theme.line),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: MiniMarkdown(plan),
              ),
            ),
            Divider(height: 1, thickness: 1, color: theme.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: context.read<AppState>().confirmPlan,
                    style: TextButton.styleFrom(
                      backgroundColor: theme.accentDim,
                      foregroundColor: theme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Confirm ✓ execute', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: context.read<AppState>().regeneratePlan,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.dim,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    child: const Text('Regenerate ↻', style: TextStyle(fontSize: 13)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: context.read<AppState>().dismissPlan,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.dimmer,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 13)),
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
