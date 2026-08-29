import 'dart:io';

import '../models.dart';
import 'registry.dart';

/// plan_write · manage_tasks · mark_task_complete — all coordinate on the
/// plan file `.tiny-cli/<sessionId>/plan/current_task.md`, serialized by
/// the plan lock key (concurrency.dart).
void registerPlanTools(ToolRegistry registry) {
  registry
    ..register(planWriteDef, _planWrite)
    ..register(manageTasksDef, _manageTasks)
    ..register(markTaskCompleteDef, _markTaskComplete);
}

String _planPath(ToolContext ctx) =>
    '${ctx.cwd}/.tiny-cli/${ctx.sessionId ?? 'default'}/plan/current_task.md';

final planWriteDef = ToolDefinition(
  name: 'plan_write',
  description: 'Write the implementation plan (markdown) for the current '
      'session. Plan mode only.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'plan': {'type': 'string', 'description': 'Full markdown plan content'},
    },
    'required': ['plan'],
  },
  isModifying: true,
);

Future<String> _planWrite(Map<String, dynamic> args, ToolContext ctx) async {
  final file = File(_planPath(ctx));
  await file.parent.create(recursive: true);
  await file.writeAsString(args['plan'] as String);
  return 'Plan written to ${file.path}';
}

final manageTasksDef = ToolDefinition(
  name: 'manage_tasks',
  description: 'Manage the task list in the current plan. Actions: add '
      '(task), mark_done (task_number), reprioritize (task_number, before_number).',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'action': {'type': 'string', 'enum': ['add', 'mark_done', 'reprioritize']},
      'task': {'type': 'string'},
      'task_number': {'type': 'integer'},
      'before_number': {'type': 'integer'},
    },
    'required': ['action'],
  },
  isModifying: true,
);

Future<String> _manageTasks(Map<String, dynamic> args, ToolContext ctx) async {
  final file = File(_planPath(ctx));
  if (!file.existsSync()) throw StateError('no plan file; run plan_write first');
  final lines = (await file.readAsString()).split('\n');

  switch (args['action'] as String) {
    case 'add':
      final task = args['task'] as String?;
      if (task == null) throw StateError('task required for add');
      // Append after the last task line, or at the end.
      var lastTask = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('- [ ]') || lines[i].startsWith('- [x]')) lastTask = i;
      }
      lines.insert(lastTask + 1, '- [ ] $task');
      await file.writeAsString(lines.join('\n'));
      return 'Task added: $task';
    case 'mark_done':
      final n = args['task_number'] as int?;
      if (n == null) throw StateError('task_number required');
      final result = _markNth(lines, n);
      if (result == null) throw StateError('task #$n not found');
      await file.writeAsString(lines.join('\n'));
      return result;
    case 'reprioritize':
      final n = args['task_number'] as int?;
      final before = args['before_number'] as int?;
      if (n == null || before == null) {
        throw StateError('task_number and before_number required');
      }
      final taskLines = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('- [ ]') || lines[i].startsWith('- [x]')) taskLines.add(i);
      }
      if (n < 1 || n > taskLines.length) throw StateError('task #$n not found');
      final moved = lines.removeAt(taskLines[n - 1]);
      final insertAt = before - 1 < n ? taskLines[before - 1] : taskLines[before - 1] - 1;
      lines.insert(insertAt.clamp(0, lines.length), moved);
      await file.writeAsString(lines.join('\n'));
      return 'Task #$n moved before #$before';
    default:
      throw StateError('unknown action ${args['action']}');
  }
}

String? _markNth(List<String> lines, int n) {
  var count = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('- [ ]') || lines[i].startsWith('- [x]')) {
      count++;
      if (count == n) {
        lines[i] = lines[i].replaceFirst('- [ ]', '- [x]');
        return 'Task #$n marked done: ${lines[i].substring(6)}';
      }
    }
  }
  return null;
}

final markTaskCompleteDef = ToolDefinition(
  name: 'mark_task_complete',
  description: 'Mark the Nth task in the plan as done.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'task_number': {'type': 'integer'},
    },
    'required': ['task_number'],
  },
  isModifying: true,
);

Future<String> _markTaskComplete(Map<String, dynamic> args, ToolContext ctx) =>
    _manageTasks({'action': 'mark_done', 'task_number': args['task_number']}, ctx);
