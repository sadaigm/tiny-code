import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/tab_state.dart';
import '../theme/app_theme.dart';
import 'context/ctx_panel.dart';
import 'sidebar/side_panel.dart';
import 'viewport/viewport_container.dart';

/// 3-pane shell: sidebar · conversation (flex) · context.
/// The sidebar and context panes are resizable by dragging their dividers;
/// the conversation absorbs whatever space is left. Below 1100px logical the
/// context pane hides, then the sidebar collapses to a 56px icon rail.
/// Shortcuts: Ctrl+B sidebar, Ctrl+Shift+B context panel, Ctrl+N new chat,
/// Ctrl+K focus chat search.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _dividerWidth = 6.0;
  static const double _sidebarMin = 200.0;
  static const double _sidebarMax = 320.0;
  static const double _ctxMin = 280.0;
  static const double _ctxMax = 450.0;
  static const double _chatMin = 500.0;
  static const double _railWidth = 56.0;

  double _sidebarWidth = 260.0;
  double _ctxWidth = 320.0;
  bool _sidebarCollapsed = false;
  bool _ctxHidden = false;
  int _searchFocusTick = 0;

  void _toggleSidebar() => setState(() => _sidebarCollapsed = !_sidebarCollapsed);

  void _toggleCtx() => setState(() => _ctxHidden = !_ctxHidden);

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
    // User toggle only wins when there is room; the breakpoint force-hides.
    final showCtx = width >= 1100 && !_ctxHidden;
    final collapsed = _sidebarCollapsed || width < 860;
    // Re-clamp on window resize: shrink the flex-side panes so the chat
    // keeps its minimum instead of overflowing when the window narrows.
    // The deficit is taken from the context pane first, then the sidebar.
    var sidebarWidth = collapsed ? _railWidth : _sidebarWidth;
    var ctxWidth = _ctxWidth;
    if (showCtx && !collapsed) {
      final deficit = _chatMin -
          (width - sidebarWidth - ctxWidth - 2 * _dividerWidth);
      if (deficit > 0) {
        final fromCtx = (ctxWidth - _ctxMin).clamp(0.0, deficit);
        ctxWidth -= fromCtx;
        sidebarWidth -= (deficit - fromCtx).clamp(0.0, sidebarWidth - _sidebarMin);
      }
      _sidebarWidth = sidebarWidth;
      _ctxWidth = ctxWidth;
    } else if (!collapsed && sidebarWidth > _railWidth) {
      final deficit = _chatMin - (width - sidebarWidth - _dividerWidth);
      if (deficit > 0) {
        sidebarWidth -= deficit.clamp(0.0, sidebarWidth - _sidebarMin);
      }
      _sidebarWidth = sidebarWidth;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyB,
            control: true, shift: true): _toggleCtx,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            () => context.read<TabState>().newTab(),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            () => context.read<TabState>().newTab(),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true):
            () => context.read<TabState>()
                .close(context.read<TabState>().activeTabId!),
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            () => context.read<TabState>().cycle(1),
        const SingleActivator(LogicalKeyboardKey.tab,
            control: true, shift: true): () => context.read<TabState>().cycle(-1),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            () => setState(() => _searchFocusTick++),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.bg,
          body: Row(
            children: [
              SidePanel(
                width: sidebarWidth,
                collapsed: collapsed,
                searchFocusTick: _searchFocusTick,
              ),
              if (!collapsed)
                _Divider(onDrag: _resizeSidebar, color: theme.line),
              Expanded(child: ViewportContainer(showCtxToggle: showCtx, onToggleCtx: _toggleCtx)),
              if (showCtx) ...[
                _Divider(onDrag: _resizeCtx, color: theme.line),
                CtxPanel(width: ctxWidth, onCollapse: _toggleCtx),
              ],
            ],
          ),
        ),
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
