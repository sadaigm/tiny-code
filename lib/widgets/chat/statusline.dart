import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Bottom statusline, per design:
///
/// `[agent]  📁 temp1  🧠 0 tok ░░░░░░░░░░ 0% (0 B)  🔒 notify`
/// `Session: 34dd2481-…  (copy)`
///
/// Tokens come engine-side via UsageEvent (`AppState.contextTokens`); the
/// meter fills against `config.compactionThresholdTokens`.
class Statusline extends StatelessWidget {
  const Statusline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();

    final tokens = app.contextTokens;
    final capacity = app.config.compactionThresholdTokens;
    final pct = capacity > 0 ? (tokens / capacity).clamp(0.0, 1.0) : 0.0;
    final filled = (pct * 10).round();
    final cwdParts = app.configLoader.projectDir
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    final cwd = cwdParts.isEmpty ? 'cwd' : cwdParts.last;
    final id = app.activeSessionId;
    final session = id ?? '—';
    final mode = app.planMode
        ? 'plan'
        : app.chatMode
            ? 'chat'
            : 'agent';

    final dim = TextStyle(color: theme.dim, fontSize: 11.5);
    final dimmer = TextStyle(color: theme.dimmer, fontSize: 11.5, height: 1.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('[$mode]', style: dim),
              const SizedBox(width: 12),
              Text('📁 $cwd', style: dimmer),
              const SizedBox(width: 12),
              Text('🧠 $tokens tok', style: dimmer),
              const SizedBox(width: 6),
              Text('▓' * filled + '░' * (10 - filled),
                  style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      color: theme.dimmer,
                      fontSize: 11.5,
                      letterSpacing: 1)),
              Text(
                  '${(pct * 100).round()}% (${_fmtBytes(tokens * 4)})  🔒 '
                  '${app.config.permissionMode.name}',
                  style: dimmer),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Session: $session', style: dimmer),
            if (id != null)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Clipboard.setData(ClipboardData(text: id)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.copy,
                        size: 12, color: theme.dimmer),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _fmtBytes(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
