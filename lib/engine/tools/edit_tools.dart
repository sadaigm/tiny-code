import 'dart:io';

import '../models.dart';
import 'registry.dart';

/// search_replace · insert_lines · list
void registerEditTools(ToolRegistry registry) {
  registry
    ..register(searchReplaceDef, _searchReplace)
    ..register(insertLinesDef, _insertLines)
    ..register(listDef, _list);
}

final searchReplaceDef = ToolDefinition(
  name: 'search_replace',
  description: 'Replace an exact text occurrence in a file. Fails if the '
      'search text is not found.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
      'search': {'type': 'string'},
      'replace': {'type': 'string'},
    },
    'required': ['path', 'search', 'replace'],
  },
  isModifying: true,
);

Future<String> _searchReplace(Map<String, dynamic> args, ToolContext ctx) async {
  final file = File(_resolve(args['path'] as String, ctx));
  final text = await file.readAsString();
  final search = args['search'] as String;
  if (!text.contains(search)) {
    throw StateError('search text not found in ${args['path']}');
  }
  final replaced = text.replaceFirst(search, args['replace'] as String);
  await file.writeAsString(replaced);
  return 'Replaced 1 occurrence in ${args['path']}';
}

final insertLinesDef = ToolDefinition(
  name: 'insert_lines',
  description: 'Insert text before the given line (1-based) in a file.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
      'line': {'type': 'integer', 'description': 'Insert before this line'},
      'text': {'type': 'string'},
    },
    'required': ['path', 'line', 'text'],
  },
  isModifying: true,
);

Future<String> _insertLines(Map<String, dynamic> args, ToolContext ctx) async {
  final file = File(_resolve(args['path'] as String, ctx));
  final lines = (await file.readAsString()).split('\n');
  final at = ((args['line'] as int) - 1).clamp(0, lines.length);
  lines.insertAll(at, (args['text'] as String).split('\n'));
  await file.writeAsString(lines.join('\n'));
  return 'Inserted ${at + 1} before line ${args['line']} in ${args['path']}';
}

final listDef = ToolDefinition(
  name: 'list',
  description: 'List a directory\'s entries.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'path': {'type': 'string', 'description': 'Directory (default: cwd)'},
    },
  },
);

Future<String> _list(Map<String, dynamic> args, ToolContext ctx) async {
  final dir = Directory(_resolve(args['path'] as String? ?? '.', ctx));
  final entries = dir.listSync(followLinks: false).map((e) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    return e is Directory ? '$name/' : name;
  }).toList()
    ..sort();
  if (entries.isEmpty) return '(empty)';
  return entries.join('\n');
}

String _resolve(String p, ToolContext ctx) =>
    p.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p) ? p : '${ctx.cwd}/$p';
