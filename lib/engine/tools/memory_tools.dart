import 'dart:io';

import '../models.dart';
import 'registry.dart';

/// memory (project-memory write) · create_skill · ask_user
void registerMemoryTools(ToolRegistry registry) {
  registry
    ..register(memoryDef, _memory)
    ..register(createSkillDef, _createSkill);
}

final memoryDef = ToolDefinition(
  name: 'memory',
  description: 'Persist a durable fact to project memory '
      '(.tiny-cli/memory/). name: kebab-case slug, description: one line, '
      'content: the fact.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'description': {'type': 'string'},
      'content': {'type': 'string'},
    },
    'required': ['name', 'description', 'content'],
  },
  isModifying: true,
);

Future<String> _memory(Map<String, dynamic> args, ToolContext ctx) async {
  final name = args['name'] as String;
  final dir = Directory('${ctx.cwd}/.tiny-cli/memory');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name.md');
  final isNew = !file.existsSync();
  await file.writeAsString(
      '---\nname: $name\ndescription: ${args['description']}\n---\n\n${args['content']}\n');

  // Keep the index in sync — one pointer line per memory.
  final index = File('${dir.path}/MEMORY.md');
  final pointer = '- [${args['description']}]($name.md)';
  final existing = index.existsSync() ? await index.readAsString() : '';
  final updated = existing
      .split('\n')
      .where((l) => !l.contains('($name.md)'))
      .toList()
    ..add(pointer);
  await index.writeAsString('${updated.where((l) => l.isNotEmpty).join('\n')}\n');
  return isNew ? 'Memory saved: $name' : 'Memory updated: $name';
}

final createSkillDef = ToolDefinition(
  name: 'create_skill',
  description: 'Create a skill file (markdown with name/description '
      'frontmatter) under .tiny-cli/skills/.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'name': {
        'type': 'string',
        'description': 'lowercase a-z, 0-9, hyphens; 1-64 chars',
      },
      'description': {'type': 'string'},
      'body': {'type': 'string'},
    },
    'required': ['name', 'description', 'body'],
  },
  isModifying: true,
);

Future<String> _createSkill(Map<String, dynamic> args, ToolContext ctx) async {
  final name = args['name'] as String;
  if (!RegExp(r'^[a-z0-9-]{1,64}$').hasMatch(name)) {
    throw StateError('invalid skill name: $name');
  }
  final dir = Directory('${ctx.cwd}/.tiny-cli/skills');
  await dir.create(recursive: true);
  await File('${dir.path}/$name.md').writeAsString(
      '---\nname: $name\ndescription: ${args['description']}\n---\n\n${(args['body'] as String).trim()}\n');
  return 'Skill created: $name';
}

final askUserDef = ToolDefinition(
  name: 'ask_user',
  description: 'Ask the user clarifying multiple-choice questions before '
      'proceeding.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'context': {'type': 'string'},
      'questions': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'question': {'type': 'string'},
            'options': {'type': 'array', 'items': {'type': 'string'}},
          },
          'required': ['question', 'options'],
        },
      },
    },
    'required': ['questions'],
  },
);

/// Registered by the engine host — the handler needs the UI bridge, so it is
/// injected at wiring time rather than living here.
void registerAskUser(ToolRegistry registry, ToolHandler handler) {
  registry.register(askUserDef, handler);
}
