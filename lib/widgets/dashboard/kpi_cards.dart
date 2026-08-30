import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/telemetry_store.dart';
import '../../theme/app_theme.dart';

/// Zone 1: four executive-summary cards — totals, context fill, connected
/// systems, duration/latency.
class KpiCards extends StatelessWidget {
  const KpiCards({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final t = context.watch<TelemetryStore>();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _KpiCard(
              label: 'Total Executions',
              value: t.totalCalls == 0 ? '—' : '${t.totalCalls} Tool Calls',
              sub: t.totalCalls == 0
                  ? 'No activity yet'
                  : '${t.succeededCalls} pass · ${t.failedCalls} fail',
              valueColor: t.failedCalls > 0 ? theme.err : theme.ok,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              label: 'Tokens / Context',
              value: t.contextTokens == 0
                  ? '—'
                  : '${_fmtTokens(t.contextTokens)} Tokens',
              sub: '',
              valueColor: theme.ink,
              footer: LinearProgressIndicator(
                value: t.contextFill,
                minHeight: 4,
                backgroundColor: theme.surface3,
                valueColor: AlwaysStoppedAnimation(theme.accent),
                borderRadius: BorderRadius.circular(2),
              ),
              subText: '${(t.contextFill * 100).round()}% context fill',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              label: 'Connected Systems',
              value: t.totalCalls == 0 ? '—' : '${t.mcpServerCount} MCP + CLI',
              sub: t.totalCalls == 0 ? 'Idle' : 'Active & Ready',
              valueColor: theme.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _KpiCard(
              label: 'Duration / Latency',
              value: t.elapsed == null ? '—' : _fmtDuration(t.elapsed!),
              sub: t.avgDurationMs == null
                  ? 'No executions'
                  : 'Avg ${t.avgDurationMs}ms / call',
              valueColor: theme.ink,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTokens(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  static String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
    this.footer,
    this.subText,
  });

  final String label;
  final String value;
  final String sub;
  final Color valueColor;
  final Widget? footer;
  final String? subText;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: theme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: theme.dimmer,
              fontSize: 10.5,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subText ?? sub,
            style: TextStyle(color: theme.dim, fontSize: 12),
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: footer!),
          ],
        ],
      ),
    );
  }
}
