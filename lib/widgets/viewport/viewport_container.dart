import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/tab_state.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_pane.dart';
import 'central_tab_bar.dart';
import 'file_viewer_pane.dart';

/// Central workspace: tab strip on top, active tab's view below. A single
/// ChatPane instance serves all chat tabs (session state lives in providers,
/// swapped by TabState.activate → AppState.openSession); file tabs live in an
/// IndexedStack so their scroll/content survives switching.
class ViewportContainer extends StatelessWidget {
  const ViewportContainer(
      {super.key, this.showCtxToggle = false, this.onToggleCtx});

  final bool showCtxToggle;
  final VoidCallback? onToggleCtx;

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<TabState>();
    final active = tabs.active;
    if (active == null) return const SizedBox.shrink();

    final fileTabs = tabs.tabs.where((t) => t.type == TabType.file).toList();
    final children = <Widget>[
      for (final t in fileTabs)
        FileViewerPane(key: ValueKey(t.id), filePath: t.filePath!),
      ChatPane(showCtxToggle: showCtxToggle, onToggleCtx: onToggleCtx),
    ];
    final index = active.type == TabType.file
        ? fileTabs.indexOf(active)
        : children.length - 1;

    return Stack(
      children: [
        Column(
          children: [
            const CentralTabBar(),
            Expanded(child: IndexedStack(index: index, children: children)),
          ],
        ),
        if (tabs.pendingSwitchTabId != null)
          Positioned(
            top: 44,
            right: 12,
            child: _InterruptDialog(tabId: tabs.pendingSwitchTabId!),
          ),
      ],
    );
  }
}

/// Popped by TabState when a switch/close would interrupt a running turn.
/// Rendered inline (the pane uses a Column, not a Stack) at the top-right.
class _InterruptDialog extends StatelessWidget {
  const _InterruptDialog({required this.tabId});

  final String tabId;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final tabs = context.read<TabState>();
    final isClose = tabId == tabs.activeTabId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isClose
                ? 'Close tab and interrupt the running turn?'
                : 'Switch tabs and interrupt the running turn?',
            style: TextStyle(color: theme.ink, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: tabs.cancelPendingSwitch,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final wasActive = tabId == tabs.activeTabId;
                  // Interrupt the engine; openSession would also do it, but
                  // the close path never reaches openSession.
                  context.read<AppState>().interrupt();
                  tabs.confirmPendingSwitch();
                  if (wasActive) tabs.close(tabId);
                },
                child: const Text('Interrupt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
