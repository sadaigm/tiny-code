/// Tracks shell redirection targets so the agent (and /usage) can verify
/// writes actually landed: `>file`, `>>file`, `2>file`, `&>file`.
library;

class RedirectTracker {
  final _counts = <String, int>{};

  Map<String, int> get counts => Map.unmodifiable(_counts);

  /// Parse redirect targets out of a command string and, if [outputBytes] is
  /// provided, attribute the byte count to each newly-appended target.
  void record(String command, {int? outputBytes}) {
    for (final target in parseRedirectTargets(command)) {
      _counts[target] = (_counts[target] ?? 0) + (outputBytes ?? 0);
    }
  }

  void reset() => _counts.clear();
}

/// Extracts redirect target paths from a command. One target per `>` op.
List<String> parseRedirectTargets(String command) {
  final targets = <String>[];
  // Split on ; and && / || first — each segment carries its own redirects.
  for (final segment in command.split(RegExp(r';|&&|\|\|'))) {
    final match = RegExp(r'(?:\d)?>>?\s*([^\s;|&]+)|&>>?\s*([^\s;|&]+)').allMatches(segment);
    for (final m in match) {
      final target = m.group(1) ?? m.group(2);
      if (target != null && target != '/dev/null') targets.add(target);
    }
  }
  return targets;
}
