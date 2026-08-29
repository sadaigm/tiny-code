import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/state/log_store.dart';

void main() {
  test('grouping: user rows own group, non-user runs merge', () {
    final groups = groupEntries([
      LogEntry(type: LogEntryType.system, text: 'memory compacted'),
      LogEntry(type: LogEntryType.user, text: 'hello'),
      LogEntry(type: LogEntryType.reasoning, text: 'hmm'),
      LogEntry(type: LogEntryType.toolCall, text: '{}', toolName: 'bash'),
      LogEntry(type: LogEntryType.toolResult, text: 'ok'),
      LogEntry(type: LogEntryType.assistant, text: 'done'),
      LogEntry(type: LogEntryType.user, text: 'again'),
      LogEntry(type: LogEntryType.assistant, text: 'sure'),
    ]);

    // TS spec rule: each user entry is its own group; the agent run that
    // follows is a separate group (MessageLog.groupEntries).
    expect(groups, hasLength(5));
    expect(groups[0].entries.single.type, LogEntryType.system); // divider
    expect(groups[1].userText, 'hello');
    expect(groups[1].entries, isEmpty);
    expect(groups[2].userText, isNull);
    expect(groups[2].entries, hasLength(4)); // reasoning+call+result+assistant
    expect(groups[3].userText, 'again');
    expect(groups[4].userText, isNull);
    expect(groups[4].entries.single.text, 'sure');
  });

  test('grouping: trailing agent run flushes', () {
    final groups = groupEntries([
      LogEntry(type: LogEntryType.user, text: 'q'),
      LogEntry(type: LogEntryType.toolCall, text: 'x', toolName: 'read'),
    ]);
    expect(groups, hasLength(2));
    expect(groups[1].entries.single.toolName, 'read');
  });

  test('LogStore adds and folds', () {
    final store = LogStore();
    store.add(LogEntry(type: LogEntryType.user, text: 'hi'));
    store.add(LogEntry(type: LogEntryType.assistant, text: 'yo'));
    expect(store.groups, hasLength(2));
    expect(store.groups[1].expanded, isTrue);
    store.toggleFold(1);
    expect(store.groups[1].expanded, isFalse);
  });

  test('StreamingTextNotifier buffers deltas', () {
    final s = StreamingTextNotifier();
    s.begin();
    s.append('a');
    s.append('b');
    expect(s.text, 'ab');
    s.end();
    expect(s.live, isFalse);
  });
}
