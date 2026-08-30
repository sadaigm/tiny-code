import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/telemetry_store.dart';
import '../../theme/app_theme.dart';
import 'execution_table.dart';
import 'kpi_cards.dart';
import 'system_cards.dart';

/// Session Telemetry & Execution Monitoring Dashboard — the alternate
/// canvas view behind the topbar toggle. Subscribes only to
/// [TelemetryStore], never to the streaming-text notifier.
class SessionDashboard extends StatelessWidget {
  const SessionDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return ChangeNotifierProvider.value(
      value: context.watch<AppState>().telemetry,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _zoneLabel(theme, 'Session Overview'),
            const SizedBox(height: 8),
            const KpiCards(),
            const SizedBox(height: 20),
            _zoneLabel(theme, 'Business Data & System Activity'),
            const SizedBox(height: 8),
            const SystemCards(),
            const SizedBox(height: 20),
            _zoneLabel(theme, 'Execution Inspector'),
            const SizedBox(height: 8),
            const ExecutionTable(),
          ],
        ),
      ),
    );
  }

  Widget _zoneLabel(AppTheme theme, String text) => Text(text.toUpperCase(),
      style: TextStyle(
          color: theme.dimmer,
          fontSize: 10.5,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600));
}
