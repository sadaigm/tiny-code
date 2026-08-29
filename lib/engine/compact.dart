import 'models.dart';
import 'model_client.dart';

/// Rough token estimate: 4 chars ≈ 1 token.
int estimateTokens(List<Message> messages) =>
    messages.fold(0, (n, m) => n + ((m.content.length + 1) / 4).ceil());

const _summaryPrompt =
    'Summarize the conversation so far for a coding assistant. Keep: the '
    'user\'s goal, decisions made, files touched, current state, and next '
    'steps. Be terse — bullet points.';

class CompactionResult {
  CompactionResult({required this.messages, required this.beforeTokens, required this.afterTokens});

  final List<Message> messages;
  final int beforeTokens;
  final int afterTokens;
}

/// If [messages] exceed [thresholdTokens], summarize the old part via a
/// non-streaming model call and keep the most recent [retainTokens] verbatim.
/// The summary lands as a `[PREVIOUS CONTEXT SUMMARY]` system message, which
/// the agent's prompt rebuild preserves.
Future<CompactionResult?> maybeCompact(
  List<Message> messages, {
  required IModelClient model,
  required int thresholdTokens,
  required int retainTokens,
  bool force = false,
  String? instructions,
}) async {
  final before = estimateTokens(messages);
  if (!force && before <= thresholdTokens) return null;
  if (messages.isEmpty) return null;

  // Walk from the end, retaining recent messages up to the token budget.
  var kept = <Message>[];
  var keptTokens = 0;
  for (final m in messages.reversed) {
    final t = ((m.content.length + 1) / 4).ceil();
    if (keptTokens + t > retainTokens && kept.isNotEmpty) break;
    kept.insert(0, m);
    keptTokens += t;
  }
  final toSummarize = messages.take(messages.length - kept.length).toList();

  String summary;
  try {
    final response = await model.chat(
      [
        ...toSummarize,
        Message(role: MessageRole.user,
            content: instructions == null || instructions.isEmpty
                ? _summaryPrompt
                : '$_summaryPrompt\nFocus on: $instructions'),
      ],
      const [], // no tools for summarization
    );
    summary = response.content.trim();
  } catch (_) {
    summary = '(compaction summary unavailable; older context dropped)';
  }

  final compacted = [
    Message(
      role: MessageRole.system,
      content: '[PREVIOUS CONTEXT SUMMARY]\n$summary',
    ),
    ...kept,
  ];
  return CompactionResult(
    messages: compacted,
    beforeTokens: before,
    afterTokens: estimateTokens(compacted),
  );
}
