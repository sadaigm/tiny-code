import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/tools/bash_redirect.dart';
import 'package:tiny_code/engine/tools/edit_tools.dart';
import 'package:tiny_code/engine/tools/fs_tools.dart';
import 'package:tiny_code/engine/tools/memory_tools.dart';
import 'package:tiny_code/engine/tools/plan_tools.dart';
import 'package:tiny_code/engine/tools/registry.dart';

void main() {
  late Directory tmp;
  late ToolRegistry registry;
  late ToolContext ctx;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tiny_code_tools2');
    registry = ToolRegistry();
    registerFsTools(registry);
    registerEditTools(registry);
    registerPlanTools(registry);
    registerMemoryTools(registry);
    ctx = ToolContext(sessionId: 's1', cwd: tmp.path);
  });

  tearDown(() async => tmp.deleteSync(recursive: true));

  group('edit tools', () {
    test('search_replace replaces exactly once', () async {
      await registry.call('write', {'path': 'f.txt', 'content': 'aaa bbb aaa'}, ctx);
      final out = await registry.call(
          'search_replace', {'path': 'f.txt', 'search': 'bbb', 'replace': 'ccc'}, ctx);
      expect(out, contains('Replaced 1'));
      expect(File('${tmp.path}/f.txt').readAsStringSync(), 'aaa ccc aaa');
    });

    test('search_replace fails loudly on no match', () async {
      await registry.call('write', {'path': 'f.txt', 'content': 'aaa'}, ctx);
      expect(
        () => registry.call(
            'search_replace', {'path': 'f.txt', 'search': 'zzz', 'replace': 'y'}, ctx),
        throwsStateError,
      );
    });

    test('insert_lines inserts before line', () async {
      await registry.call('write', {'path': 'f.txt', 'content': 'one\nthree'}, ctx);
      await registry.call(
          'insert_lines', {'path': 'f.txt', 'line': 2, 'text': 'two'}, ctx);
      expect(File('${tmp.path}/f.txt').readAsLinesSync(), ['one', 'two', 'three']);
    });

    test('list shows dirs with trailing slash', () async {
      await Directory('${tmp.path}/sub').create();
      await File('${tmp.path}/x.txt').writeAsString('x');
      final out = await registry.call('list', {}, ctx);
      expect(out, contains('sub/'));
      expect(out, contains('x.txt'));
    });
  });

  group('plan tools', () {
    test('plan_write then manage_tasks add/mark_done', () async {
      await registry.call(
          'plan_write', {'plan': '# Plan\n\n- [ ] first\n- [ ] second'}, ctx);
      final planFile = File('${tmp.path}/.tiny-cli/s1/plan/current_task.md');
      expect(planFile.existsSync(), isTrue);

      await registry.call(
          'manage_tasks', {'action': 'add', 'task': 'third'}, ctx);
      var text = planFile.readAsStringSync();
      expect(text, contains('- [ ] third'));

      final done = await registry.call(
          'manage_tasks', {'action': 'mark_done', 'task_number': 1}, ctx);
      expect(done, contains('first'));
      text = planFile.readAsStringSync();
      expect(text, contains('- [x] first'));

      final shortcut = await registry.call(
          'mark_task_complete', {'task_number': 2}, ctx);
      expect(shortcut, contains('second'));
    });

    test('manage_tasks mark_done out of range throws', () async {
      await registry.call('plan_write', {'plan': '- [ ] only'}, ctx);
      expect(
        () => registry.call('manage_tasks', {'action': 'mark_done', 'task_number': 5}, ctx),
        throwsStateError,
      );
    });
  });

  group('memory tool', () {
    test('memory writes file + index pointer, updates in place', () async {
      await registry.call('memory',
          {'name': 'my-fact', 'description': 'A fact', 'content': 'facts'}, ctx);
      final mem = File('${tmp.path}/.tiny-cli/memory/my-fact.md');
      expect(mem.readAsStringSync(), contains('description: A fact'));
      expect(File('${tmp.path}/.tiny-cli/memory/MEMORY.md').readAsStringSync(),
          contains('(my-fact.md)'));

      await registry.call('memory',
          {'name': 'my-fact', 'description': 'Updated', 'content': 'v2'}, ctx);
      final index =
          File('${tmp.path}/.tiny-cli/memory/MEMORY.md').readAsStringSync();
      expect('(my-fact.md)'.allMatches(index), hasLength(1)); // no dup line
    });

    test('create_skill validates name', () async {
      expect(
        () => registry.call('create_skill',
            {'name': 'Bad Name', 'description': 'd', 'body': 'b'}, ctx),
        throwsStateError,
      );
      final ok = await registry.call('create_skill',
          {'name': 'good-skill', 'description': 'd', 'body': 'b'}, ctx);
      expect(ok, contains('good-skill'));
    });
  });

  group('bash redirect tracking', () {
    test('parseRedirectTargets', () {
      expect(
        parseRedirectTargets('echo hi > a.txt; echo yo >> b.txt 2> err.log'),
        ['a.txt', 'b.txt', 'err.log'],
      );
      expect(parseRedirectTargets('echo none > /dev/null'), isEmpty);
      expect(parseRedirectTargets('echo plain'), isEmpty);
    });

    test('tracker accumulates byte counts per target', () {
      final t = RedirectTracker();
      t.record('echo hi > a.txt', outputBytes: 3);
      t.record('echo yo >> a.txt', outputBytes: 3);
      t.record('echo x > b.txt', outputBytes: 2);
      expect(t.counts['a.txt'], 6);
      expect(t.counts['b.txt'], 2);
    });
  });
}
