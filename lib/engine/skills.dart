import 'dart:io';

class Skill {
  Skill(this.name, this.description, this.body);

  final String name; // dir name
  final String description;
  final String body;
}

/// Discovery mirrors tiny-cli (packages/resources/src/discover.ts), in the
/// same precedence order — first wins on name collision:
/// 1. `~/.tiny-cli/agent/skills/` — root .md files + `<dir>/SKILL.md` dirs
/// 2. `~/.agents/skills/` — `<dir>/SKILL.md` dirs only
/// 3. `<cwd>/.tiny-cli/skills/` — root .md files + `<dir>/SKILL.md` dirs
/// 4. `.agents/skills/` walking cwd → ancestors
List<Skill> discoverSkills(String cwd, String homeDir) {
  final roots = <String>[
    '$homeDir/.tiny-cli/agent/skills',
    '$homeDir/.agents/skills',
    '$cwd/.tiny-cli/skills',
    '$cwd/.agents/skills',
    ..._ancestorDirs(cwd).map((d) => '$d/.agents/skills'),
  ];
  final byName = <String, Skill>{};
  void add(String name, File file) {
    if (byName.containsKey(name)) return;
    try {
      byName[name] = _parse(name, file.readAsStringSync());
    } catch (_) {}
  }

  for (var i = 0; i < roots.length; i++) {
    final dir = Directory(roots[i]);
    if (!dir.existsSync()) continue;
    // Roots 0 and 2 (the tiny-cli dirs) also load bare .md files.
    if (i == 0 || i == 2) {
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.md')) {
          final name = entity.path.split(RegExp(r'[/\\]')).last;
          add(name.endsWith('.md') ? name.substring(0, name.length - 3) : name,
              entity);
        }
      }
    }
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final skillFile = File('${entity.path}/SKILL.md');
      if (!skillFile.existsSync()) continue;
      add(entity.path.split(RegExp(r'[/\\]')).last, skillFile);
    }
  }
  return byName.values.toList();
}

Skill _parse(String name, String raw) {
  var description = '';
  var body = raw;
  if (raw.startsWith('---')) {
    final end = raw.indexOf('\n---', 3);
    if (end > 0) {
      final front = raw.substring(3, end);
      body = raw.substring(end + 4);
      final m = RegExp(r'description:\s*(.+)').firstMatch(front);
      if (m != null) description = m.group(1)!.trim();
    }
  }
  return Skill(name, description, body.trim());
}

/// System-prompt fragment: XML listing of all skills, plus full bodies of the
/// active ones.
String skillsPromptFragment(List<Skill> skills, List<String> activeSkills) {
  if (skills.isEmpty) return '';
  final buf = StringBuffer('\n\n<available_skills>');
  for (final s in skills) {
    buf.write('\n  <skill name="${s.name}">${s.description}</skill>');
  }
  buf.write('\n</available_skills>');

  final active =
      skills.where((s) => activeSkills.contains(s.name)).toList();
  if (active.isNotEmpty) {
    buf.write('\n\n<active_skills>');
    for (final s in active) {
      buf.write('\n  <skill name="${s.name}">\n${s.body}\n  </skill>');
    }
    buf.write('\n</active_skills>');
  }
  return buf.toString();
}

List<String> _ancestorDirs(String cwd) {
  final dirs = <String>[];
  var dir = Directory(cwd).absolute;
  while (true) {
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
    dirs.add(dir.path);
  }
  return dirs;
}
