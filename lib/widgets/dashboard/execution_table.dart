import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/telemetry_store.dart';
import '../../theme/app_theme.dart';
import 'payload_views.dart';

enum _CategoryFilter { all, system, mcp }
enum _StatusFilter { all, errors }

/// Zone 3: filter bar + expandable execution list. Newest first.
class ExecutionTable extends StatefulWidget {
  const ExecutionTable({super.key});

  @override
  State<ExecutionTable> createState() => _ExecutionTableState();
}

class _ExecutionTableState extends State<ExecutionTable> {
  _CategoryFilter _category = _CategoryFilter.all;
  _StatusFilter _status = _StatusFilter.all;
  String _query = '';
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final t = context.watch<TelemetryStore>();

    final rows = t.events.reversed.where((e) {
      if (_category == _CategoryFilter.system && e.isMcp) return false;
      if (_category == _CategoryFilter.mcp && !e.isMcp) return false;
      if (_status == _StatusFilter.errors && e.ok) return false;
      if (_query.isNotEmpty &&
          !e.toolName.toLowerCase().contains(_query) &&
          !e.summary.toLowerCase().contains(_query)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterBar(theme),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          _EmptyTable(theme: theme)
        else
          Container(
            decoration: BoxDecoration(
              color: theme.surface2,
              borderRadius: BorderRadius.circular(AppColors.radius),
              border: Border.all(color: theme.line),
            ),
            child: Column(children: [
              _headerRow(theme),
              for (final e in rows) _row(theme, e),
            ]),
          ),
      ],
    );
  }

  Widget _filterBar(AppTheme theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _pill(theme, 'All Types', _category == _CategoryFilter.all,
            () => setState(() => _category = _CategoryFilter.all)),
        _pill(theme, '💻 System/CLI', _category == _CategoryFilter.system,
            () => setState(() => _category = _CategoryFilter.system)),
        _pill(theme, '🔌 MCP Servers', _category == _CategoryFilter.mcp,
            () => setState(() => _category = _CategoryFilter.mcp)),
        const SizedBox(width: 8),
        _pill(theme, 'Errors Only', _status == _StatusFilter.errors,
            () => setState(
                () => _status = _status == _StatusFilter.errors ? _StatusFilter.all : _StatusFilter.errors)),
        const SizedBox(width: 8),
        SizedBox(
          width: 220,
          height: 30,
          child: TextField(
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            style: TextStyle(color: theme.ink, fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search tool / keyword…',
              hintStyle: TextStyle(color: theme.dimmer, fontSize: 12),
              prefixIcon: Icon(Icons.search, size: 15, color: theme.dimmer),
              border: theme.focusBorder(),
              contentPadding: const EdgeInsets.symmetric(vertical: 7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(AppTheme theme, String label, bool active, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? theme.accentDim : theme.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? theme.accent : theme.line),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? theme.ink : theme.dim, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _headerRow(AppTheme theme) {
    const cols = ['STATUS', 'TIME', 'SYSTEM', 'CLASS', 'SUMMARY', ''];
    const flexes = [null, null, null, null, 1, null];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cols.length; i++)
            flexes[i] == 1
                ? Expanded(
                    child: _cell(theme, cols[i], dim: true, alignRight: false))
                : _cell(theme, cols[i], dim: true),
        ],
      ),
    );
  }

  Widget _row(AppTheme theme, ToolExecutionEvent e) {
    final isOpen = _expanded.contains(e.id);
    return Column(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => isOpen
                ? _expanded.remove(e.id)
                : _expanded.add(e.id)),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _statusBadge(theme, e),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: Text(
                        '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${e.timestamp.second.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            color: theme.dimmer,
                            fontSize: 11.5,
                            fontFamily: 'JetBrains Mono')),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 130,
                    child: Text(e.source,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.dim, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  _classBadge(theme, e.operation),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(e.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.ink, fontSize: 12.5)),
                  ),
                  const SizedBox(width: 8),
                  Icon(isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: theme.dimmer),
                ],
              ),
            ),
          ),
        ),
        if (isOpen) PayloadView(event: e),
      ],
    );
  }

  Widget _statusBadge(AppTheme theme, ToolExecutionEvent e) {
    final (label, fg) = e.ok
        ? (e.toolName == 'bash' ? 'Exit 0' : '200 OK', theme.ok)
        : ('ERR', theme.err);
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _classBadge(AppTheme theme, OperationClass op) {
    final (label, fg) = switch (op) {
      OperationClass.read => ('READ', theme.secondary),
      OperationClass.write => ('WRITE', theme.accent),
      OperationClass.execute => ('EXECUTE', theme.dim),
    };
    return Container(
      width: 66,
      padding: const EdgeInsets.symmetric(vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _cell(AppTheme theme, String text,
      {bool dim = false, bool alignRight = true}) {
    return Text(text,
        style: TextStyle(
            color: dim ? theme.dimmer : theme.dim,
            fontSize: 10,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600));
  }
}

class _EmptyTable extends StatelessWidget {
  const _EmptyTable({required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        height: 120,
        decoration: BoxDecoration(
          color: theme.surface2,
          borderRadius: BorderRadius.circular(AppColors.radius),
          border: Border.all(color: theme.line),
        ),
        alignment: Alignment.center,
        child: Text('No executions match the current filters.',
            style: TextStyle(color: theme.dimmer, fontSize: 12.5)),
      );
}
