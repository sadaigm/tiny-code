import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';

/// One accordion slot: always-visible header row; when expanded it takes a
/// fair share of the parent height and its content scrolls inside.
/// Collapsing frees the space to sibling panels.
class AccordionPanel extends StatelessWidget {
  const AccordionPanel(
      {super.key,
      required this.title,
      required this.collapsed,
      required this.onToggle,
      required this.child});

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _Header(title: title, collapsed: true, onToggle: onToggle),
      );
    }
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: title, collapsed: false, onToggle: onToggle),
          const SizedBox(height: 8),
          Expanded(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.title, required this.collapsed, required this.onToggle});

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text('▾',
                  style: TextStyle(color: theme.dimmer, fontSize: 12)),
            ),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
                style: TextStyle(
                    color: theme.dimmer,
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
