import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/telemetry_store.dart';
import '../../theme/app_theme.dart';

/// Zone 2: one card per source (each MCP server + local system/CLI) with
/// read (⬇) / write (⬆) rollups.
class SystemCards extends StatelessWidget {
  const SystemCards({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TelemetryStore>();
    final stats = t.sourceStats;

    if (stats.isEmpty) {
      return _EmptyZone(text: 'No systems touched yet this session.');
    }

    return SizedBox(
      height: 126,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final entry = stats.entries.elementAt(i);
          return _SystemCard(
              title: _displayName(entry.key), stats: entry.value);
        },
      ),
    );
  }

  static String _displayName(String source) => source == 'system'
      ? '💻 Local System / CLI'
      : '🔌 ${source.replaceFirst('mcp:', '').replaceAll('_', ' ')}';
}

class _SystemCard extends StatelessWidget {
  const _SystemCard({required this.title, required this.stats});

  final String title;
  final SourceStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: theme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: theme.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _Metric(
            icon: Icons.south,
            color: theme.secondary,
            text: stats.reads == 1
                ? '1 read operation'
                : '${stats.reads} read operations',
          ),
          const SizedBox(height: 6),
          _Metric(
            icon: Icons.north,
            color: theme.ok,
            text: stats.writes + stats.executes == 1
                ? '1 write / execute action'
                : '${stats.writes + stats.executes} writes / executes',
          ),
          if (stats.errors > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${stats.errors} error(s)',
                  style: TextStyle(color: theme.err, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.dim, fontSize: 12.5)),
        ),
      ],
    );
  }
}

class _EmptyZone extends StatelessWidget {
  const _EmptyZone({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      height: 126,
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: theme.line),
      ),
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(color: theme.dimmer, fontSize: 12.5)),
    );
  }
}
