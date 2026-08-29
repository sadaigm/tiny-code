import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/tools/bash_tool.dart';
import 'package:tiny_code/engine/tools/fs_tools.dart';
import 'package:tiny_code/engine/tools/registry.dart';

void main() {
  late Directory tmp;
  late ToolRegistry registry;
  late ToolContext ctx;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tiny_code_test');
    registry = ToolRegistry();
    registerFsTools(registry);
    registerBashTool(registry);
    ctx = ToolContext(cwd: tmp.path);
  });

  tearDown(() async => tmp.deleteSync(recursive: true));

  test('write then read round trip', () async {
    final wrote = await registry.call(
        'write', {'path': 'sub/a.txt', 'content': 'line1\nline2'}, ctx);
    expect(wrote, contains('Wrote'));

    final read = await registry
        .call('read', {'path': 'sub/a.txt', 'start': 2, 'end': 2}, ctx);
    expect(read, 'line2');
  });

  test('bash echoes and reports exit code', () async {
    final out = await registry
        .call('bash', {'command': 'echo hello'}, ctx);
    expect(out, contains('exit code 0'));
    expect(out, contains('hello'));
  }, skip: Platform.isWindows ? 'posix shell' : false);

  test('bash failing command reports nonzero exit', () async {
    final out = await registry
        .call('bash', {'command': 'exit 3'}, ctx);
    expect(out, contains('exit code 3'));
  }, skip: Platform.isWindows ? 'posix shell' : false);

  test('bash timeout kills the process', () async {
    final out = await registry.call(
        'bash', {'command': 'sleep 30', 'timeout_ms': 300}, ctx);
    expect(out, contains('timed out'));
  }, skip: Platform.isWindows ? 'posix shell' : false);

  test('unknown tool throws', () async {
    expect(
      () => registry.call('nope', {}, ctx),
      throwsStateError,
    );
  });
}
