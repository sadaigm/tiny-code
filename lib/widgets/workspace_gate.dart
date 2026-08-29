import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/workspace.dart';
import '../theme/app_theme.dart';

/// Workspace chooser: recent workspaces (from ~/.tiny-cli/workspaces/config.json)
/// plus the native folder picker. Reached from the sidebar folder button.
class WorkspaceGate extends StatelessWidget {
  const WorkspaceGate({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final workspace = context.watch<WorkspaceState>();
    return Scaffold(
      backgroundColor: theme.bg,
      appBar: AppBar(
        backgroundColor: theme.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.dim),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Workspace',
            style: TextStyle(
                color: theme.ink, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: Center(
        child: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sessions live in the workspace .tiny-cli/ folder',
                  style: TextStyle(color: theme.dim, fontSize: 12.5)),
              const SizedBox(height: 12),
              if (workspace.recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No recent workspaces yet',
                      style:
                          TextStyle(color: theme.dimmer, fontSize: 12.5)),
                )
              else
                for (final dir in workspace.recent)
                  _RecentTile(
                    path: dir,
                    active: dir == workspace.dir,
                    onTap: () {
                      workspace.select(dir);
                      Navigator.of(context).pop();
                    },
                  ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () async {
                  await workspace.pick();
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  backgroundColor: theme.accentDim,
                  foregroundColor: theme.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('Open folder…', style: TextStyle(fontSize: 13.5)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  workspace.useHome();
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(foregroundColor: theme.dim),
                child: const Text('Use home (~/.tiny-cli)',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatefulWidget {
  const _RecentTile(
      {required this.path, required this.active, required this.onTap});

  final String path;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<_RecentTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: widget.active
                ? theme.accentDim
                : (_hover ? theme.panel : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.folder_outlined,
                size: 15, color: widget.active ? theme.accent : theme.dim),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: widget.active ? theme.accent : theme.dim,
                      fontSize: 12.5)),
            ),
          ]),
        ),
      ),
    );
  }
}
