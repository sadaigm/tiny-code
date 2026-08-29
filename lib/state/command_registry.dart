/// Single shared registry of slash commands for the autocomplete popover
/// and (later) command dispatch. Mirrors tiny-cli's command set.
class CommandSpec {
  const CommandSpec(this.name, this.argsHint, this.description);
  final String name; // e.g. '/compact'
  final String argsHint; // e.g. '[instructions]'
  final String description;
}

const kCommands = <CommandSpec>[
  CommandSpec('/help', '', 'List commands'),
  CommandSpec('/clear', '', 'Clear the message stream'),
  CommandSpec('/usage', '', 'Tool call statistics for this session'),
  CommandSpec('/find', '<text>', 'Search the loaded log entries'),
  CommandSpec('/mcp', '', 'MCP servers: enable/disable, tool counts'),
  CommandSpec('/mode', '', 'Show the permission mode'),
  CommandSpec('/session', '', 'Show the active session'),
  CommandSpec('/plan', '<goal>', 'Research and write an execution plan'),
  CommandSpec('/compact', '[instructions]', 'Summarize the conversation to free context'),
  CommandSpec('/skills', '', 'List discovered skills'),
  CommandSpec('/context', '', 'Show injected context: instructions/memory/skills'),
  CommandSpec('/stop', '', 'Interrupt the running turn'),
];

List<CommandSpec> filterCommands(String token) {
  if (token.isEmpty) return kCommands;
  final t = token.toLowerCase();
  return kCommands.where((c) => c.name.startsWith(t)).toList();
}
