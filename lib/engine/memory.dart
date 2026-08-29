import 'dart:io';

const _memoryCap = 10 * 1024;
const _stopwords = {
  'the', 'a', 'an', 'and', 'or', 'to', 'of', 'in', 'on', 'for', 'with', 'is',
  'are', 'was', 'be', 'this', 'that', 'it', 'as', 'at', 'by', 'from', 'not',
};

class MemoryFile {
  MemoryFile(this.path, this.description, this.body);

  final String path; // relative to the memory dir
  final String description;
  final String body;
}

/// Parse a memory file: YAML-ish frontmatter `name`/`description` + body.
MemoryFile? parseMemoryFile(String relativePath, String raw) {
  String description = '';
  var body = raw;
  if (raw.startsWith('---')) {
    final end = raw.indexOf('\n---', 3);
    if (end > 0) {
      final front = raw.substring(3, end);
      body = raw.substring(end + 4);
      final m = RegExp(r'description:\s*(.+)').firstMatch(front);
      if (m != null) description = m.group(1)!.trim().replaceAll(RegExp('^[\'"]|[\'"]\$'), '');
    }
  }
  return MemoryFile(relativePath, description, body.trim());
}

/// Memory roots, same precedence structure as skill discovery
/// (see skills.dart): home-global first, workspace-local last; per memory
/// name, the first root that has it wins.
List<String> memoryRoots(String projectDir, String homeDir) => [
      '$homeDir/.tiny-cli/agent/memory',
      '$homeDir/.agents/memory',
      '$projectDir/.tiny-cli/memory',
      '$projectDir/.agents/memory',
    ];

/// Load memories from the roots above (the tiny-cli TUI writes to
/// `<workspace>/.tiny-cli/memory/`). In each root, when a `MEMORY.md` index
/// exists, only files referenced by its `- [title](file)` lines are
/// considered; otherwise every `.md` in the dir. Filter by keyword relevance
/// to [query], cap at 10k chars. Returns the `<project_memory>` block
/// (empty if nothing relevant).
String collectMemory(String projectDir, String homeDir, String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.length > 2 && !_stopwords.contains(w))
      .toSet();
  if (words.isEmpty) return '';

  // name → root dir, first root wins.
  final found = <String, String>{};
  for (final root in memoryRoots(projectDir, homeDir)) {
    final memDir = Directory(root);
    if (!memDir.existsSync()) continue;

    final names = <String>[];
    final index = File('$root/MEMORY.md');
    if (index.existsSync()) {
      for (final line in index.readAsStringSync().split('\n')) {
        if (!line.startsWith('- [')) continue;
        final m = RegExp(r'\]\(([^)]+)\)').firstMatch(line);
        if (m != null) names.add(m.group(1)!);
      }
    }
    if (names.isEmpty) {
      for (final entity in memDir.listSync(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.md')) {
          final name = entity.path.split(RegExp(r'[/\\]')).last;
          if (name != 'MEMORY.md') names.add(name);
        }
      }
    }
    for (final name in names) {
      found.putIfAbsent(name, () => root);
    }
  }

  final picked = <MemoryFile>[];
  var total = 0;
  for (final entry in found.entries) {
    try {
      final name = entry.key;
      final file = File('${entry.value}/$name');
      if (!file.existsSync()) continue;
      final parsed = parseMemoryFile(name, file.readAsStringSync());
      if (parsed == null || parsed.body.isEmpty) continue;
      // Relevance: overlap of query keywords with name+description+body.
      final haystack = '${parsed.description} ${parsed.body}'.toLowerCase();
      final hits = words.where(haystack.contains).length;
      // `user`-type memories are always included.
      final isUser = parsed.body.contains('type: user') ||
          parsed.body.contains('type: feedback');
      if (hits == 0 && !isUser) continue;
      if (total + parsed.body.length > _memoryCap) {
        picked.add(MemoryFile(parsed.path, parsed.description,
            '${parsed.body.substring(0, _memoryCap - total)}\n…[truncated]'));
        total = _memoryCap;
        break;
      }
      picked.add(parsed);
      total += parsed.body.length;
    } catch (_) {}
  }
  if (picked.isEmpty) return '';

  final buf = StringBuffer('\n\n<project_memory>\n');
  for (final m in picked) {
    buf.write('--- $m.path ---\n${m.body}\n\n');
  }
  buf.write('</project_memory>');
  return buf.toString();
}
