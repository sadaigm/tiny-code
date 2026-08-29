import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/models.dart';

void main() {
  test('Message round-trips through JSON', () {
    final m = Message(
      role: MessageRole.assistant,
      content: 'hello',
      toolCalls: [ToolCall(id: 'c1', name: 'bash', argumentsJson: '{"command":"ls"}')],
    );
    final back = Message.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>);
    expect(back.role, MessageRole.assistant);
    expect(back.content, 'hello');
    expect(back.toolCalls!.single.name, 'bash');
    expect(back.toolCalls!.single.args['command'], 'ls');
  });

  test('Session round-trips through JSON', () {
    final s = Session(
      metadata: SessionMetadata(
        id: 'abc',
        createdAt: DateTime.utc(2026, 1, 1),
        lastUpdatedAt: DateTime.utc(2026, 1, 2),
        title: 'test',
        permissionMode: PermissionMode.autoEdit,
      ),
      messages: [Message(role: MessageRole.user, content: 'hi')],
    );
    final back = Session.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.metadata.id, 'abc');
    expect(back.metadata.permissionMode, PermissionMode.autoEdit);
    expect(back.messages.single.content, 'hi');
  });

  test('ToolCall.args tolerates malformed JSON', () {
    final c = ToolCall(id: 'x', name: 'bash', argumentsJson: '{not json');
    expect(c.args, isEmpty);
  });
}
