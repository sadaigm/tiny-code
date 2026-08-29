import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/state/command_registry.dart';

void main() {
  test('filterCommands: empty token lists all', () {
    expect(filterCommands(''), hasLength(kCommands.length));
  });

  test('filterCommands: prefix match', () {
    final hits = filterCommands('/comp');
    expect(hits, hasLength(1));
    expect(hits.single.name, '/compact');
  });

  test('filterCommands: no match', () {
    expect(filterCommands('/zzz'), isEmpty);
  });
}
