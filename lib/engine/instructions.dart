import 'dart:io';

/// Upward lookup of instruction files (CLAUDE.md / AGENTS.md) from `cwd` to
/// the filesystem root, nearest first. Wrapped in `<project_instructions>`
/// blocks for the system prompt.
String collectInstructions(String cwd) {
  final blocks = <String>[];
  final seen = <String>{};
  var dir = Directory(cwd).absolute;
  while (true) {
    for (final name in const ['CLAUDE.md', 'AGENTS.md']) {
      final f = File('${dir.path}/$name');
      final key = f.path;
      if (!seen.contains(key) && f.existsSync()) {
        seen.add(key);
        try {
          final text = f.readAsStringSync().trim();
          if (text.isNotEmpty) {
            blocks.add('<project_instructions path="$name">\n$text\n</project_instructions>');
          }
        } catch (_) {}
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break; // fs root
    dir = parent;
  }
  return blocks.isEmpty ? '' : '\n\n${blocks.join('\n\n')}';
}
