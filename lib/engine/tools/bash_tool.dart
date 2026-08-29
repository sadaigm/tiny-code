import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'registry.dart';

const _maxOutputChars = 30_000;
const _defaultTimeout = Duration(seconds: 120);

void registerBashTool(ToolRegistry registry) {
  registry.register(bashDef, _bash);
}

final bashDef = ToolDefinition(
  name: 'bash',
  description: 'Run a shell command and return its merged stdout/stderr. '
      'Long-running commands time out. Software installs and network '
      'commands are risky and always require user approval. Prefer the '
      'read/search tools to verify files instead of installing browsers '
      'or parsers.',
  parametersSchema: {
    'type': 'object',
    'properties': {
      'command': {'type': 'string'},
      'timeout_ms': {'type': 'integer', 'description': 'Optional timeout in ms'},
    },
    'required': ['command'],
  },
  isModifying: true,
);

/// Risk classifier for bash commands: package installs, browser/parser
/// downloads, and network fetches always require explicit user approval,
/// regardless of permission mode. Matches the whole command line so
/// `foo && apt install …` is caught too. Used by the agent's approval
/// gate (agent._needsApproval).
final _riskyPatterns = <RegExp>[
  RegExp(r'\b(apt|apt-get|snap|brew|dnf|yum|pacman)(-get)?\s+(-y\s+)?install\b'),
  RegExp(r'\b(pip3?|uv)\s+install\b'),
  RegExp(r'\bnpm\s+(install|i)\b|\bnpx\s+\S*install|\byarn\s+(add|install)\b'),
  RegExp(r'\bplaywright\s+install\b|\bchromium\b.*\binstall\b|\binstall\b.*\bchromium\b'),
  RegExp(r'\b(curl|wget|ftp|scp|rsync|ssh)\b'),
  RegExp(r'\bgit\s+clone\b'),
];

bool isRiskyBashCommand(String command) =>
    _riskyPatterns.any((p) => p.hasMatch(command));

Future<String> _bash(Map<String, dynamic> args, ToolContext ctx) async {
  final command = args['command'] as String;
  final timeout = args['timeout_ms'] == null
      ? _defaultTimeout
      : Duration(milliseconds: args['timeout_ms'] as int);

  final proc = await Process.start(
    _shell(),
    [..._shellFlag(), command],
    workingDirectory: ctx.cwd,
  );

  // Drain both streams fully before reading the buffer — exitCode alone
  // can win the race against pending stdout.
  final stdoutFuture = proc.stdout.transform(utf8.decoder).join();
  final stderrFuture = proc.stderr.transform(utf8.decoder).join();
  await proc.stdin.close();

  final exitCode = await proc.exitCode.timeout(timeout, onTimeout: () {
    proc.kill(ProcessSignal.sigkill);
    return -1;
  });
  final out = '${await stdoutFuture}${await stderrFuture}';

  var text = out;
  if (text.length > _maxOutputChars) {
    text =
        '${text.substring(0, _maxOutputChars)}\n[...truncated at $_maxOutputChars chars]';
  }
  if (exitCode == -1) {
    return 'Command timed out after ${timeout.inSeconds}s. Partial output:\n$text';
  }
  return 'exit code $exitCode\n$text';
}

String _shell() => Platform.isWindows ? 'cmd.exe' : 'bash';
List<String> _shellFlag() => Platform.isWindows ? <String>['/c'] : <String>['-c'];
