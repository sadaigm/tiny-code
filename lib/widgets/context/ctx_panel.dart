import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'files_tab.dart';
import 'plan_tab.dart';
import 'thoughts_tab.dart';

/// Right pane: a segmented tab bar (Files / Plan / Thoughts) above the
/// active inspector view, with a collapse chevron and settings shortcut.
class CtxPanel extends StatefulWidget {
  const CtxPanel({super.key, required this.width, this.onCollapse});

  final double width;
  final VoidCallback? onCollapse;

  @override
  State<CtxPanel> createState() => _CtxPanelState();
}

class _CtxPanelState extends State<CtxPanel> {
  int _tab = 0;

  static const _tabs = ['Files', 'Plan', 'Thoughts'];

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();

    return Container(
      width: widget.width,
      color: theme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Expanded(child: _TabBar(
                  tabs: _tabs,
                  current: _tab,
                  onSelect: (i) => setState(() => _tab = i),
                )),
                const SizedBox(width: 4),
                _HeaderIcon(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onTap: () =>
                        context.read<AppState>().showSettings = true),
                _HeaderIcon(
                  icon: Icons.chevron_right,
                  tooltip: 'Collapse panel (Ctrl+Shift+B)',
                  onTap: widget.onCollapse,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.line),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppColors.anim,
              switchInCurve: AppColors.animCurve,
              switchOutCurve: AppColors.animCurve,
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: switch (_tab) {
                  0 => const FilesTab(),
                  1 => const PlanTab(),
                  _ => const ThoughtsTab(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented [a | b | c] selector with a gold underline on the active tab.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.tabs, required this.current, required this.onSelect});

  final List<String> tabs;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: i == current
                              ? theme.accent
                              : Colors.transparent,
                          width: 2)),
                ),
                child: Text(tabs[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: i == current ? theme.ink : theme.dim,
                        fontSize: 12,
                        fontWeight:
                            i == current ? FontWeight.w600 : FontWeight.w400)),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderIcon extends StatefulWidget {
  const _HeaderIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  State<_HeaderIcon> createState() => _HeaderIconState();
}

class _HeaderIconState extends State<_HeaderIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _hover ? theme.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 15, color: theme.dim),
          ),
        ),
      ),
    );
  }
}
