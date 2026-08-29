import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Engine crashed mid-turn: resume the session in a fresh engine isolate,
/// retry the last message, or discard and start clean.
class RecoveryDialog extends StatelessWidget {
  const RecoveryDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Center(
      child: Container(
        width: 460,
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.panel,
          border: Border.all(color: theme.err),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Engine crashed',
                style: TextStyle(
                    color: theme.err,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.dim, fontSize: 12.5, height: 1.4)),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: () => context.read<AppState>().resumeFromCrash(),
                  style: TextButton.styleFrom(
                    backgroundColor: theme.accentDim,
                    foregroundColor: theme.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Resume session', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => context.read<AppState>().retryFromCrash(),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.dim,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Retry last message', style: TextStyle(fontSize: 13)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: context.read<AppState>().discardCrash,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.dimmer,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  child: const Text('Discard', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
