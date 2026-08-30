import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Collapsible workspace file tree — fully stateless. Expansion state
/// (expanded directory paths) lives in [AppState]; directories are listed
/// on build and dot-entries (other than .tiny-cli) are hidden.
class FileTree extends StatelessWidget {
  const FileTree({super.key, required this.root, this.onOpenFile});

  final String root;

  /// Double-click a file → open/focus its viewer tab.
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();
    return DirNode(
      dir: Directory(root),
      root: root,
      theme: theme,
      expanded: app.expandedTreeDirs,
      onToggle: app.toggleTreeDir,
      onOpenFile: onOpenFile,
    );
  }
}

/// Stateless directory node: renders its row (when not root) and, if
/// expanded, its sorted children.
class DirNode extends StatelessWidget {
  const DirNode({
    super.key,
    required this.dir,
    required this.root,
    required this.theme,
    required this.expanded,
    required this.onToggle,
    this.onOpenFile,
  });

  final Directory dir;
  final String root;
  final AppTheme theme;
  final Set<String> expanded;
  final void Function(String path) onToggle;
  final void Function(String path)? onOpenFile;

  List<FileSystemEntity> _list() {
    try {
      final entries = dir.listSync(followLinks: false);
      entries.sort((a, b) {
        final aDir = a is Directory, bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.path.compareTo(b.path);
      });
      return entries.where(_visible).toList();
    } catch (_) {
      return const [];
    }
  }

  static bool _visible(FileSystemEntity e) {
    final name = e.path.split(RegExp(r'[/\\]')).last;
    return !name.startsWith('.') || name == '.tiny-cli';
  }

  @override
  Widget build(BuildContext context) {
    final name = dir.path.split(RegExp(r'[/\\]')).last;
    final isRoot = dir.path == root;
    final isOpen = isRoot || expanded.contains(dir.path);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isRoot)
          InkWell(
            onTap: () => onToggle(dir.path),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(isOpen ? '▾' : '▸',
                      style: TextStyle(color: theme.dimmer, fontSize: 12)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: theme.dim,
                            fontSize: 13,
                            fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
          ),
        if (isOpen)
          Padding(
            padding: EdgeInsets.only(left: isRoot ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in _list())
                  if (e is Directory)
                    DirNode(
                      dir: e,
                      root: root,
                      theme: theme,
                      expanded: expanded,
                      onToggle: onToggle,
                      onOpenFile: onOpenFile,
                    )
                  else
                    InkWell(
                      onTap: () {},
                      onDoubleTap: () => onOpenFile?.call(e.path),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(e.path.split(RegExp(r'[/\\]')).last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: theme.tool,
                                      fontSize: 13,
                                      fontFamily: 'monospace')),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}
