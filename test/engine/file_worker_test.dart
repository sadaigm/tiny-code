import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/file_worker.dart';

void main() {
  late Directory tmp;
  late FileWorkerPool pool;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tiny_code_pool');
    pool = FileWorkerPool(size: 2);
    await File('${tmp.path}/alpha.dart').writeAsString('hello world\nfoo bar');
    await File('${tmp.path}/beta.txt').writeAsString('nothing here');
    await Directory('${tmp.path}/.git').create();
    await File('${tmp.path}/.git/config').writeAsString('hello hidden');
  });

  tearDown(() async {
    pool.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('grep finds matches and skips .git', () async {
    final result = await pool.run({'op': 'grep', 'root': tmp.path, 'pattern': 'hello'});
    final matches = (result['matches'] as List).cast<String>();
    expect(matches, hasLength(1));
    expect(matches.single, contains('alpha.dart:1'));
  });

  test('grep regex mode', () async {
    final result = await pool
        .run({'op': 'grep', 'root': tmp.path, 'pattern': 'f.o bar', 'isRegex': true});
    expect((result['matches'] as List), hasLength(1));
  });

  test('glob matches pattern', () async {
    final result = await pool.run({'op': 'glob', 'root': tmp.path, 'pattern': '*.dart'});
    expect((result['files'] as List).cast<String>(), ['alpha.dart']);
  });

  test('pool round-robins across workers', () async {
    final f1 = pool.run({'op': 'glob', 'root': tmp.path, 'pattern': '*'});
    final f2 = pool.run({'op': 'glob', 'root': tmp.path, 'pattern': '*'});
    final f3 = pool.run({'op': 'glob', 'root': tmp.path, 'pattern': '*'});
    final results = await Future.wait([f1, f2, f3]);
    for (final r in results) {
      expect((r['files'] as List), isNotEmpty);
    }
  });
}
