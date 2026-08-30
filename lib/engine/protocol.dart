import 'models.dart';

/// Engine → UI events. Sent over the isolate's SendPort; instances cross
/// directly (same isolate group), so no JSON encoding layer is needed.
sealed class AgentEvent {
  const AgentEvent();
}

class StepEvent extends AgentEvent {
  const StepEvent(this.step);

  final AgentStep step;
}

class TextDeltaEvent extends AgentEvent {
  const TextDeltaEvent(this.delta);

  final String delta;
}

class ThinkingDeltaEvent extends AgentEvent {
  const ThinkingDeltaEvent(this.delta);

  final String delta;
}

class ApprovalRequestEvent extends AgentEvent {
  const ApprovalRequestEvent({required this.id, required this.call});

  final String id;
  final ToolCall call;
}

class AskUserEvent extends AgentEvent {
  const AskUserEvent({required this.id, required this.payload});

  final String id;
  final AskUserPayload payload;
}

class CompactionEvent extends AgentEvent {
  const CompactionEvent(this.beforeTokens, this.afterTokens);

  final int beforeTokens;
  final int afterTokens;
}

class ModelErrorEvent extends AgentEvent {
  const ModelErrorEvent(this.message);

  final String message;
}

class StatusEvent extends AgentEvent {
  const StatusEvent({required this.running, this.turnDone});

  final bool running;
  final bool? turnDone;
}

class EngineCrashedEvent extends AgentEvent {
  const EngineCrashedEvent(this.message);

  final String message;
}

/// UI → engine commands.
sealed class AgentCommand {
  const AgentCommand();
}

class SendMessageCommand extends AgentCommand {
  const SendMessageCommand(this.text, {this.mode, this.continueSession = true});

  final String text;
  final AgentMode? mode;
  final bool continueSession;
}

class InterruptCommand extends AgentCommand {
  const InterruptCommand();
}

class ApprovalResponseCommand extends AgentCommand {
  const ApprovalResponseCommand({required this.id, required this.approved, this.sessionAlways = false});

  final String id;
  final bool approved;
  final bool sessionAlways;
}

class AskUserResponseCommand extends AgentCommand {
  const AskUserResponseCommand({required this.id, required this.response});

  final String id;
  final AskUserResponse response;
}

class NewSessionCommand extends AgentCommand {
  const NewSessionCommand(this.sessionId);

  final String sessionId;
}

class ResumeCommand extends AgentCommand {
  const ResumeCommand(this.messages);

  final List<Message> messages;
}

class McpToggleCommand extends AgentCommand {
  const McpToggleCommand({required this.name, required this.enabled});

  final String name;
  final bool enabled;
}

class McpReconnectCommand extends AgentCommand {
  const McpReconnectCommand({required this.name});

  final String name;
}

class McpDeleteCommand extends AgentCommand {
  const McpDeleteCommand({required this.name});

  final String name;
}

class UsageRequestCommand extends AgentCommand {
  const UsageRequestCommand();
}

class CompactRequestCommand extends AgentCommand {
  const CompactRequestCommand({this.instructions});
  final String? instructions;
}

class SetPermissionModeCommand extends AgentCommand {
  const SetPermissionModeCommand(this.mode);
  final PermissionMode mode;
}

class UsageEvent extends AgentEvent {
  const UsageEvent(this.usage);

  /// {toolCounts: {name: n}, redirects: {path: bytes}, maxConcurrency: int}
  final Map<String, dynamic> usage;
}

class McpServersEvent extends AgentEvent {
  const McpServersEvent(this.servers);

  /// [{name, enabled, toolCount}]
  final List<Map<String, dynamic>> servers;
}
