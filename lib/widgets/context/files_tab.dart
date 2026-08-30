import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'file_tree.dart';

/// Files tab: files touched this session above the workspace tree,
/// with a filter field narrowing the tree.
class FilesTab extends StatefulWidget {
  const FilesTab({super.key});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        _SectionTitle(theme, 'Working files'),
        const SizedBox(height: 6),
        _WorkingFiles(app: app, theme: theme),
        const SizedBox(height: 16),
        _SectionTitle(theme, 'Workspace'),
        const SizedBox(height: 6),
        _TreeFilter(
            value: _filter, onChanged: (v) => setState(() => _filter = v)),
        const SizedBox(height: 6),
        if (_filter.isEmpty)
          FileTree(root: app.configLoader.projectDir)
        else
          _FilteredFiles(root: app.configLoader.projectDir, filter: _filter),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.theme, this.text);

  final AppTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: TextStyle(
            color: theme.dimmer,
            fontSize: 10.5,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600));
  }
}

/// Files touched by write/edit tools this session, newest last.
class _WorkingFiles extends StatelessWidget {
  const _WorkingFiles({required this.app, required this.theme});

  final AppState app;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final files = app.workingFiles.toList();
    if (files.isEmpty) {
      return Text('No files touched',
          style: TextStyle(color: theme.dimmer, fontSize: 12.5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in files)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: theme.secondary)),
                Expanded(
                  child: Text(f,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.dim,
                          fontSize: 11.5,
                          fontFamily: 'JetBrains Mono')),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TreeFilter extends StatelessWidget {
  const _TreeFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return TextField(
      onChanged: onChanged,
      style: TextStyle(color: theme.ink, fontSize: 12),
      decoration: InputDecoration(
        hintText: 'Filter files…',
        hintStyle: TextStyle(color: theme.dimmer, fontSize: 12),
        prefixIcon: Icon(Icons.search, size: 14, color: theme.dimmer),
        isDense: true,
        filled: true,
        fillColor: theme.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          borderSide: BorderSide(color: theme.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          borderSide: BorderSide(color: theme.line),
        ),
        focusedBorder: theme.focusBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
      ),
    );
  }
}

/// Flat filename match under [root] when a filter is active.
class _FilteredFiles extends StatelessWidget {
  const _FilteredFiles({required this.root, required this.filter});

  final String root;
  final String filter;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final query = filter.toLowerCase();
    final matches = <String>[];
    _walk(Directory(root), query, matches, 0);
    if (matches.isEmpty) {
      return Text('No matches',
          style: TextStyle(color: theme.dimmer, fontSize: 12.5));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(m,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: theme.dim,
                    fontSize: 11.5,
                    fontFamily: 'JetBrains Mono')),
          ),
      ],
    );
  }

  void _walk(Directory dir, String query, List<String> out, int depth) {
    if (depth > 6 || out.length > 100) return;
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.path.split('/').last;
      if (name.startsWith('.') && name != '.tiny-cli') continue;
      if (e is Directory) {
        _walk(e, query, out, depth + 1);
      } else if (name.toLowerCase().contains(query)) {
        out.add(e.path.replaceFirst('$root/', ''));
      }
    }
  }
}
