import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/tab_state.dart';
import '../../theme/app_theme.dart';

/// Read-only file viewer: monospace lines with a number gutter, plus a
/// floating bar whose actions prefill the chat input with the @path mention.
class FileViewerPane extends StatefulWidget {
  const FileViewerPane({super.key, required this.filePath});

  final String filePath;

  @override
  State<FileViewerPane> createState() => _FileViewerPaneState();
}

class _FileViewerPaneState extends State<FileViewerPane> {
  List<String>? _lines;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final text = File(widget.filePath).readAsStringSync();
      setState(() {
        _lines = text.split('\n');
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _prefillChat(String text) {
    final app = context.read<AppState>();
    final tabs = context.read<TabState>();
    // Focus a chat tab first (there is always at least one).
    final chatTab = tabs.tabs
        .where((t) => t.type == TabType.chat)
        .firstOrNull;
    if (chatTab != null && chatTab.id != tabs.activeTabId) {
      tabs.activate(chatTab.id);
    }
    app.setInput(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    if (_error != null) {
      return Center(
        child: Text('Could not read file: $_error',
            style: TextStyle(color: theme.dim, fontSize: 13)),
      );
    }
    final lines = _lines;
    if (lines == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        ListView.builder(
          itemCount: lines.length,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          itemBuilder: (context, i) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: theme.dimmer,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  lines[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.ink,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 14,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: theme.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () => _prefillChat('@${widget.filePath} '),
                    icon: Icon(Icons.add, size: 14, color: theme.accent),
                    label: const Text('Add to Context'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _prefillChat(
                        '@${widget.filePath} explain this file'),
                    icon: Icon(Icons.bolt, size: 14, color: theme.accent),
                    label: const Text('Ask AI'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
