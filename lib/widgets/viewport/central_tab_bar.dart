import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/tab_state.dart';
import '../../theme/app_theme.dart';

/// 36px desktop tab strip for the central viewport: chat + file tabs with
/// hover close, drag reorder, wheel scrolling, and a trailing "+" button.
class CentralTabBar extends StatefulWidget {
  const CentralTabBar({super.key});

  @override
  State<CentralTabBar> createState() => _CentralTabBarState();
}

class _CentralTabBarState extends State<CentralTabBar> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final tabs = context.watch<TabState>();
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.panel,
        border: Border(bottom: BorderSide(color: theme.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Listener(
              // Horizontal wheel-scroll for the tab strip.
              onPointerSignal: (s) {
                if (s is PointerScrollEvent && _scroll.hasClients) {
                  _scroll.position.jumpTo(
                    (_scroll.offset + s.scrollDelta.dy)
                        .clamp(0.0, _scroll.position.maxScrollExtent),
                  );
                }
              },
              child: ReorderableListView.builder(
                scrollController: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: tabs.tabs.length,
                onReorderItem: tabs.reorderItem,
                buildDefaultDragHandles: false,
                proxyDecorator: (child, _, _) => child,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) {
                  final tab = tabs.tabs[index];
                  return _TabTile(
                    key: ValueKey(tab.id),
                    index: index,
                    tab: tab,
                    selected: tab.id == tabs.activeTabId,
                    running: tab.type == TabType.chat &&
                        tab.sessionId ==
                            context.read<AppState>().activeSessionId &&
                        tabs.isRunning,
                  );
                },
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: 'New chat tab',
              onPressed: () => context.read<TabState>().newTab(),
              icon: Icon(Icons.add, color: theme.dim),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabTile extends StatefulWidget {
  const _TabTile({
    super.key,
    required this.index,
    required this.tab,
    required this.selected,
    required this.running,
  });

  final int index;
  final WorkspaceTab tab;
  final bool selected;
  final bool running;

  @override
  State<_TabTile> createState() => _TabTileState();
}

class _TabTileState extends State<_TabTile> {
  bool _hover = false;

  IconData get _icon {
    if (widget.tab.type == TabType.chat) {
      return Icons.chat_bubble_outline;
    }
    final ext = widget.tab.filePath!.split('.').last.toLowerCase();
    if (ext == 'md' || ext == 'markdown') return Icons.description_outlined;
    if (const {'dart', 'py', 'js', 'ts', 'json', 'sh', 'yaml', 'yml'}
        .contains(ext)) {
      return Icons.code;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final tabs = context.read<TabState>();
    final selected = widget.selected;
    final isFile = widget.tab.type == TabType.file;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ReorderableDragStartListener(
        index: widget.index,
        child: GestureDetector(
          onTap: () => tabs.activate(widget.tab.id),
          child: Container(
            width: 170,
            margin: const EdgeInsets.fromLTRB(0, 0, 1, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? theme.bg : theme.surface2,
              border: Border(
                top: BorderSide(
                  width: 2,
                  color: selected ? theme.accent : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(_icon,
                    size: 13,
                    color: selected ? theme.accent : theme.dim),
                const SizedBox(width: 6),
                if (widget.running && !isFile) ...[
                  const SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    widget.tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? theme.ink : theme.dim,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      fontFamily: isFile ? 'monospace' : null,
                    ),
                  ),
                ),
                if (widget.tab.isUnsaved)
                  Text('•',
                      style: TextStyle(color: theme.accent, fontSize: 14))
                else if (_hover || selected)
                  InkWell(
                    onTap: () => tabs.close(widget.tab.id),
                    child: Icon(Icons.close,
                        size: 14, color: theme.dim),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
