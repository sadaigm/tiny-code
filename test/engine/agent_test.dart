import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/agent.dart';
import 'package:tiny_code/engine/model_client.dart';
import 'package:tiny_code/engine/models.dart';

/// Headless AgentLoop tests with a fake model — no real endpoint needed.
/// The real-endpoint hello-world check from task T2.4 runs manually
/// (needs credentials); these cover the loop mechanics.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tiny_code_agent');
  });

  tearDown(() async => tmp.deleteSync(recursive: true));

  Agent agentWith(FakeModel model, {PermissionMode perm = PermissionMode.notify}) {
    return Agent(
      AgentConfig(
        endpoint: 'http://fake',
        model: 'fake-model',
        permissionMode: perm,
        sessionId: 's1',
        cwd: tmp.path,
      ),
      modelClient: model,
    );
  }

  test('plain reply: no tools, streamedFinal set when onText present', () async {
    final model = FakeModel([
      ModelResponse(content: 'hi there'),
    ]);
    final agent = agentWith(model);
    final deltas = <String>[];
    final result = await agent.run('hello',
        mode: AgentMode.chat,
        cbs: AgentCallbacks(onText: deltas.add));

    expect(result.content, 'hi there');
    expect(result.streamedFinal, isTrue);
    expect(deltas.join(''), 'hi there'); // fake model replays content as a delta
    expect(model.receivedRequests.first.messages.first.role, MessageRole.system);
  });

  test('tool round trip: write file then final answer', () async {
    final model = FakeModel([
      ModelResponse(content: '', toolCalls: [
        ToolCall(id: 't1', name: 'write',
            argumentsJson: '{"path":"out.txt","content":"data"}'),
      ]),
      ModelResponse(content: 'done, wrote out.txt'),
    ]);
    final agent = agentWith(model);
    final steps = <AgentStep>[];
    final result = await agent.run('write out.txt',
        mode: AgentMode.agent,
        cbs: AgentCallbacks(
          onStep: steps.add,
          onApproval: (_) async => const ApprovalDecision(approved: true),
        ));

    expect(result.content, startsWith('done'));
    expect(steps.single.toolResult, contains('Wrote'));
    expect(File('${tmp.path}/out.txt').readAsStringSync(), 'data');
    // history: system, user, assistant(toolcall), tool, assistant(final)
    final roles = agent.getHistory().map((m) => m.role).toList();
    expect(roles, [
      MessageRole.system,
      MessageRole.user,
      MessageRole.assistant,
      MessageRole.tool,
      MessageRole.assistant,
    ]);
  });

  test('denied approval records denial, agent continues', () async {
    final model = FakeModel([
      ModelResponse(content: '', toolCalls: [
        ToolCall(id: 't1', name: 'bash', argumentsJson: '{"command":"echo hi"}'),
      ]),
      ModelResponse(content: 'ok, skipped it'),
    ]);
    final agent = agentWith(model);
    final result = await agent.run('run something',
        cbs: AgentCallbacks(onApproval: (_) async => const ApprovalDecision(approved: false)));

    expect(result.content, contains('ok'));
    final toolMsg = agent
        .getHistory()
        .firstWhere((m) => m.role == MessageRole.tool);
    expect(toolMsg.content, 'Denied by user.');
  });

  test('plan mode blocks non-allowlisted tool', () async {
    final model = FakeModel([
      ModelResponse(content: '', toolCalls: [
        ToolCall(id: 't1', name: 'write',
            argumentsJson: '{"path":"x.txt","content":"no"}'),
      ]),
      ModelResponse(content: 'plan only'),
    ]);
    final agent = agentWith(model);
    await agent.run('edit something',
        mode: AgentMode.plan, cbs: AgentCallbacks(onApproval: (_) async => const ApprovalDecision(approved: true)));

    final toolMsg = agent
        .getHistory()
        .firstWhere((m) => m.role == MessageRole.tool);
    expect(toolMsg.content, contains('not available'));
    expect(File('${tmp.path}/x.txt').existsSync(), isFalse);
  });

  test('auto permission mode skips approval entirely', () async {
    final model = FakeModel([
      ModelResponse(content: '', toolCalls: [
        ToolCall(id: 't1', name: 'bash', argumentsJson: '{"command":"echo hi"}'),
      ]),
      ModelResponse(content: 'ran'),
    ]);
    var asked = 0;
    final agent = agentWith(model, perm: PermissionMode.auto);
    await agent.run('run',
        cbs: AgentCallbacks(onApproval: (_) async {
          asked++;
          return const ApprovalDecision(approved: true);
        }));
    expect(asked, 0);
  });

  test('mode system prompt contains cwd substitution', () async {
    final model = FakeModel([ModelResponse(content: 'ok')]);
    final agent = agentWith(model);
    await agent.run('hi', mode: AgentMode.chat);
    final sys = model.receivedRequests.first.messages.first;
    expect(sys.content, isNot(contains(r'$')));
  });
}

/// Scripted model: returns queued responses in order, records requests.
class FakeModel implements IModelClient {
  FakeModel(this.script);

  final List<ModelResponse> script;
  final receivedRequests = <({List<Message> messages, List<ToolDefinition> tools})>[];
  int _i = 0;

  @override
  Future<ModelResponse> chat(
    List<Message> messages,
    List<ToolDefinition> tools, {
    void Function(String delta)? onText,
    void Function(String delta)? onReasoning,
    Future<void> Function()? abortSignal,
  }) async {
    receivedRequests.add((messages: [...messages], tools: [...tools]));
    final r = script[_i++];
    // Replay content as deltas so streaming is exercised.
    if (onText != null && r.content.isNotEmpty && r.toolCalls.isEmpty) {
      onText(r.content);
    }
    return r;
  }

  @override
  Future<ModelResponse> chatSync(List<Message> messages) async =>
      throw UnimplementedError();
}
