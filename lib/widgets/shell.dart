import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import 'chat/chat_pane.dart';
import 'context/ctx_panel.dart';
import 'sidebar/side_panel.dart';

/// 3-pane shell: sidebar · conversation (flex) · context.
/// The sidebar and context panes are resizable by dragging their dividers;
/// the conversation absorbs whatever space is left. Below 1100px logical the
/// context pane hides, then the sidebar collapses to 56px.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _dividerWidth = 6.0;
  static const double _sidebarMin = 200.0;
  static const double _sidebarMax = 400.0;
  static const double _ctxMin = 220.0;
  static const double _ctxMax = 480.0;
  static const double _chatMin = 500.0;

  double _sidebarWidth = 264.0;
  double _ctxWidth = 300.0;

  void _resizeSidebar(double delta) {
    setState(() {
      // Chat is the flex pane; a wide sidebar must not squeeze it under _chatMin.
      final total = MediaQuery.sizeOf(context).width;
      final available = total - _ctxWidth - 2 * _dividerWidth - _chatMin;
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(_sidebarMin, available.clamp(_sidebarMin, _sidebarMax));
    });
  }

  void _resizeCtx(double delta) {
    setState(() {
      final total = MediaQuery.sizeOf(context).width;
      final available = total - _sidebarWidth - 2 * _dividerWidth - _chatMin;
      _ctxWidth =
          (_ctxWidth - delta).clamp(_ctxMin, available.clamp(_ctxMin, _ctxMax));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final width = MediaQuery.sizeOf(context).width;
    final showCtx = width >= 1100;
    // Re-clamp on window resize: shrink the flex-side panes so the chat
    // keeps its minimum instead of overflowing when the window narrows.
    // The deficit is taken from the context pane first, then the sidebar.
    var sidebarWidth = width >= 860 ? _sidebarWidth : 56.0;
    var ctxWidth = _ctxWidth;
    if (showCtx) {
      final deficit = _chatMin -
          (width - sidebarWidth - ctxWidth - 2 * _dividerWidth);
      if (deficit > 0) {
        final fromCtx = (ctxWidth - _ctxMin).clamp(0.0, deficit);
        ctxWidth -= fromCtx;
        sidebarWidth -= (deficit - fromCtx).clamp(0.0, sidebarWidth - _sidebarMin);
      }
      _sidebarWidth = sidebarWidth;
      _ctxWidth = ctxWidth;
    } else if (sidebarWidth > 56.0) {
      final deficit = _chatMin - (width - sidebarWidth - _dividerWidth);
      if (deficit > 0) {
        sidebarWidth -= deficit.clamp(0.0, sidebarWidth - _sidebarMin);
      }
      _sidebarWidth = sidebarWidth;
    }

    return Scaffold(
      backgroundColor: theme.bg,
      body: Row(
        children: [
          SidePanel(width: sidebarWidth),
          if (width >= 860)
            _Divider(onDrag: _resizeSidebar, color: theme.line),
          const Expanded(child: ChatPane()),
          if (showCtx) ...[
            _Divider(onDrag: _resizeCtx, color: theme.line),
            CtxPanel(width: _ctxWidth),
          ],
        ],
      ),
    );
  }
}

/// Draggable vertical separator; [onDrag] receives the horizontal delta.
class _Divider extends StatelessWidget {
  const _Divider({required this.onDrag, required this.color});

  static const double _width = 6.0;

  final ValueChanged<double> onDrag;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDrag(details.primaryDelta!),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(width: _width, color: color),
      ),
    );
  }
}
