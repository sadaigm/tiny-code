import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';

/// Lightweight markdown renderer for agent replies: headings, bullet lists,
/// fenced code blocks, inline code chips, bold. Styled per the chat redesign
/// (headings in agent color, dim lists, mono code on panel bg).
class MiniMarkdown extends StatelessWidget {
  const MiniMarkdown(this.source, {super.key, this.fontSize = 13.5});

  final String source;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final blocks = _parseBlocks(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _block(context, theme, blocks[i]),
        ],
      ],
    );
  }

  List<_Block> _parseBlocks(String src) {
    final blocks = <_Block>[];
    var inCode = false;
    final code = <String>[];
    for (final line in src.split('\n')) {
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          blocks.add(_Block(_Kind.code, code.join('\n')));
          code.clear();
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      final h = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line);
      if (h != null) {
        blocks.add(_Block(_Kind.heading, h.group(2)!, level: h.group(1)!.length));
        continue;
      }
      if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
        blocks.add(_Block(_Kind.bullet,
            line.replaceFirst(RegExp(r'^\s*[-*]\s+'), '')));
        continue;
      }
      if (line.trim().isEmpty) {
        blocks.add(const _Block(_Kind.gap, ''));
        continue;
      }
      blocks.add(_Block(_Kind.paragraph, line));
    }
    if (code.isNotEmpty) blocks.add(_Block(_Kind.code, code.join('\n')));
    return blocks;
  }

  Widget _block(BuildContext context, AppTheme theme, _Block b) {
    switch (b.kind) {
      case _Kind.heading:
        final size = fontSize + (b.level <= 2 ? 3 : 1.5);
        return Padding(
          padding: EdgeInsets.only(top: b.level <= 2 ? 4 : 2),
          child: Text(b.text,
              style: TextStyle(
                  color: theme.tool,
                  fontSize: size,
                  fontWeight: FontWeight.w600,
                  height: 1.4)),
        );
      case _Kind.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TextStyle(color: theme.dim, fontSize: fontSize)),
              Expanded(
                  child: Text.rich(_inline(theme, b.text),
                      style: TextStyle(
                          color: theme.dim,
                          fontSize: fontSize,
                          height: 1.5))),
            ],
          ),
        );
      case _Kind.paragraph:
        return Text.rich(_inline(theme, b.text),
            style: TextStyle(
                color: theme.ink, fontSize: fontSize, height: 1.5));
      case _Kind.gap:
        return const SizedBox(height: 2);
      case _Kind.code:
        return GestureDetector(
          onLongPress: () => copyCode(context, b.text),
          child: Container(
            width: double.infinity,
            color: theme.panel,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(b.text,
                style: TextStyle(
                    color: theme.tool,
                    fontSize: fontSize - 1,
                    fontFamily: 'monospace',
                    height: 1.45)),
          ),
        );
    }
  }

  /// Inline spans: `code` chips and **bold**.
  TextSpan _inline(AppTheme theme, String text) {
    final children = <TextSpan>[];
    final pattern = RegExp(r'`([^`]+)`|\*\*([^*]+)\*\*');
    var pos = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > pos) {
        children.add(TextSpan(text: text.substring(pos, m.start)));
      }
      if (m.group(1) != null) {
        children.add(TextSpan(
            text: ' ${m.group(1)} ',
            style: TextStyle(
                color: theme.tool,
                fontFamily: 'monospace',
                fontSize: fontSize - 1,
                backgroundColor: theme.panel)));
      } else {
        children.add(TextSpan(
            text: m.group(2),
            style: TextStyle(fontWeight: FontWeight.w600)));
      }
      pos = m.end;
    }
    if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
    return TextSpan(children: children);
  }
}

enum _Kind { heading, bullet, paragraph, gap, code }

class _Block {
  const _Block(this.kind, this.text, {this.level = 0});
  final _Kind kind;
  final String text;
  final int level;
}

/// Copy-to-clipboard helper for code blocks (used by long-press).
void copyCode(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: code));
  ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
}
