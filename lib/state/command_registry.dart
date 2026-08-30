/// Command behavior class: how the autocomplete popover dispatches it.
enum CommandType {
  /// Has sub-options — picking it swaps the popover to its children;
  /// command text never enters the input.
  selector,

  /// Needs free text — fills the input with the command and lets the
  /// user type the argument.
  input,

  /// Runs immediately when picked.
  direct,
}

/// Single shared registry of slash commands for the autocomplete popover
/// and (later) command dispatch. Mirrors tiny-cli's command set.
class CommandSpec {
  const CommandSpec(this.name, this.argsHint, this.description,
      {this.type = CommandType.input});
  final String name; // e.g. '/compact'
  final String argsHint; // e.g. '[instructions]'
  final String description;
  final CommandType type;
}

const kCommands = <CommandSpec>[
  CommandSpec('/mcp', '', 'MCP servers: enable/disable, tool counts',
      type: CommandType.selector),
  CommandSpec('/mode', '', 'Show the permission mode',
      type: CommandType.selector),
  CommandSpec('/plan', '<goal>', 'Research and write an execution plan'),
  CommandSpec('/skills', '', 'List discovered skills',
      type: CommandType.selector),
  CommandSpec('/context', '', 'Show injected context: instructions/memory/skills',
      type: CommandType.direct),
  CommandSpec('/compact', '[instructions]',
      'Summarize the conversation to free context'),
];

CommandSpec? commandByName(String name) {
  for (final c in kCommands) {
    if (c.name == name) return c;
  }
  return null;
}

List<CommandSpec> filterCommands(String token) {
  if (token.isEmpty) return kCommands;
  final t = token.toLowerCase();
  return kCommands.where((c) => c.name.startsWith(t)).toList();
}
