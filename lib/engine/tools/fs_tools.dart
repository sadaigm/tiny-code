import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'registry.dart';

const maxReadChars = 200_000;

void registerFsTools(ToolRegistry registry) {
  registry
    ..register(readDef, _read)
    ..register(writeDef, _write);
}

// ── read ────────────────────────────────────────────────────────────
final readDef = ToolDefinition(
  name: 'read',
  description: 'Read a text file. Returns the content; optionally limited '
      'to a line range (1-based, inclusive).',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'File path (relative to cwd)'},
      'start': {'type': 'integer', 'description': 'First line (1-based)'},
      'end': {'type': 'integer', 'description': 'Last line (inclusive)'},
    },
    'required': ['path'],
  },
);

Future<String> _read(Map<String, dynamic> args, ToolContext ctx) async {
  final path = _resolve(args['path'] as String, ctx);
  final text = await File(path).readAsString(encoding: utf8);
  final lines = text.split('\n');
  final start = ((args['start'] as int?) ?? 1) - 1;
  final end = args['end'] as int? ?? lines.length;
  var slice = lines
      .getRange(start.clamp(0, lines.length), end.clamp(0, lines.length))
      .join('\n');
  if (slice.length > maxReadChars) {
    slice = '${slice.substring(0, maxReadChars)}\n[...truncated at $maxReadChars chars]';
  }
  return slice;
}

// ── write ───────────────────────────────────────────────────────────
final writeDef = ToolDefinition(
  name: 'write',
  description: 'Create or overwrite a file with the given content.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
      'content': {'type': 'string'},
    },
    'required': ['path', 'content'],
  },
  isModifying: true,
);

Future<String> _write(Map<String, dynamic> args, ToolContext ctx) async {
  final path = _resolve(args['path'] as String, ctx);
  final file = File(path);
  final content = args['content'] as String? ?? '';
  await file.parent.create(recursive: true);
  await file.writeAsString(content, encoding: utf8);
  return 'Wrote ${content.length} chars to ${args['path']}';
}

String _resolve(String p, ToolContext ctx) {
  if (p.startsWith('/') || p.startsWith(RegExp(r'[A-Za-z]:[\\/]'))) {
    return p;
  }
  return '${ctx.cwd}/$p';
}
