import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/concurrency.dart';

void main() {
  test('MutexMap serializes same key, parallelizes different keys', () async {
    final m = MutexMap();
    final order = <String>[];

    final a = m.acquire('k').then((_) async {
      await Future.delayed(const Duration(milliseconds: 30));
      order.add('a');
      m.release('k');
    });
    final b = m.acquire('k').then((_) async {
      order.add('b');
      m.release('k');
    });
    final c = m.acquire('other').then((_) async {
      order.add('c');
      m.release('other');
    });
    await Future.wait([a, b, c]);
    expect(order, containsAll(['a', 'b', 'c']));
    expect(order.indexOf('a'), lessThan(order.indexOf('b'))); // serialized
  });

  test('MutationGate runs one at a time', () async {
    final gate = MutationGate();
    var inside = 0;
    var maxInside = 0;

    Future<void> task() async {
      await gate.acquire();
      inside++;
      maxInside = maxInside < inside ? inside : maxInside;
      await Future.delayed(const Duration(milliseconds: 20));
      inside--;
      gate.release();
    }

    await Future.wait([task(), task(), task()]);
    expect(maxInside, 1);
  });

  test('classifyLockKey', () {
    expect(classifyLockKey('read', {}), isNull);
    expect(classifyLockKey('grep', {}), isNull);
    expect(classifyLockKey('bash', {}), bashLock);
    expect(classifyLockKey('ask_user', {}), askUserLock);
    expect(classifyLockKey('write', {'path': 'a.txt'}), 'path:a.txt');
    expect(classifyLockKey('plan_write', {}), planLock);
  });

  test('computeMaxConcurrency from windows', () {
    final windows = [
      ExecWindow('a', 0, 100),
      ExecWindow('b', 50, 150), // overlaps a
      ExecWindow('c', 120, 130), // overlaps b only
      ExecWindow('d', 200, 250), // disjoint
    ];
    expect(computeMaxConcurrency(windows), 2); // a+b overlap; c only overlaps b
    expect(computeMaxConcurrency([]), 0);
    expect(computeMaxConcurrency([ExecWindow('x', 0, 10)]), 1);
  });
}
