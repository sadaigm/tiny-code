import 'dart:convert';
import 'dart:io';

import 'models.dart';
import '../platform_env_io.dart' as env;

/// Loads configuration from the same files tiny-cli uses, so both apps
/// share agents and sessions:
///   project: `<cwd>/.tiny-cli/agents.json`      (wins)
///   home:    `~/.tiny-cli/agents.json`          (auto-created with a default)
///   global:  `~/.config/tiny-cli/config.json`   (lastSessionId, permissionMode)
class ConfigLoader {
  ConfigLoader({String? projectDir, String? homeDir})
      : projectDir = projectDir ?? Directory.current.path,
        homeDir = homeDir ?? env.homeDir;

  final String projectDir;
  final String homeDir;

  String get projectConfigFile => '$projectDir/.tiny-cli/agents.json';
  String get homeConfigFile => '$homeDir/.tiny-cli/agents.json';
  String get globalConfigFile => '$homeDir/.config/tiny-cli/config.json';
  String get sessionsDir => '$projectDir/.tiny-cli/sessions';

  Future<AgentConfig> load() async {
    var raw = await _tryRead(projectConfigFile) ?? await _tryRead(homeConfigFile);

    if (raw == null) {
      raw = _defaultProfilesJson();
      await _writeFile(homeConfigFile, raw);
    }

    AgentConfig config;
    try {
      final profiles = (jsonDecode(raw) as List<dynamic>)
          .map((p) => p as Map<String, dynamic>)
          .toList();
      final profile =
          profiles.firstWhere((p) => p['name'] == 'default', orElse: () => profiles.first);
      config = _configFromProfile(profile);
    } catch (_) {
      config = AgentConfig(endpoint: 'http://localhost:11434/v1', model: 'llama3.2:latest');
    }

    // Global settings merge (same precedence as tiny-cli).
    final globalRaw = await _tryRead(globalConfigFile);
    if (globalRaw != null) {
      try {
        final global = jsonDecode(globalRaw) as Map<String, dynamic>;
        final perm = global['permissionMode'] as String?;
        if (perm != null) {
          config = config.copyWith(
              permissionMode: PermissionMode.values.byName(perm));
        }
      } catch (_) {
        // Malformed global config — ignore.
      }
    }
    return config;
  }

  AgentConfig _configFromProfile(Map<String, dynamic> p) {
    final env = p['environment'] as Map<String, dynamic>?;
    final prompts = <String, String>{};
    final promptOverrides = p['prompts'] as Map<String, dynamic>?;
    promptOverrides?.forEach((k, v) {
      if (v is String) prompts[k] = v;
    });
    final systemPrompt = p['systemPrompt'] as String?;
    if (systemPrompt != null) prompts.putIfAbsent('chat', () => systemPrompt);

    final servers = (p['mcpServers'] as List<dynamic>? ?? [])
        .map((s) => McpServerConfig.fromJson(s as Map<String, dynamic>))
        .toList();

    // `settings` object (written by the app's settings panel) overrides the
    // profile-level values; the global config still wins (merged in load()).
    final settings = p['settings'] as Map<String, dynamic>?;
    final settingsPerm = settings?['permissionMode'] as String?;
    final permRaw = settingsPerm ?? p['permissionMode'] as String?;

    return AgentConfig(
      endpoint:
          '${env?['hostUrl'] ?? 'http://localhost:11434'}${env?['appBasePath'] ?? '/v1'}',
      apiKey: env?['apiKey'] as String?,
      model: p['model'] as String? ?? 'llama3.2:latest',
      temperature: (p['temperature'] as num?)?.toDouble(),
      prompts: prompts,
      mcpServers: servers,
      permissionMode: permRaw == null
          ? PermissionMode.notify
          : PermissionMode.values.byName(permRaw),
      maxIterations: p['maxIterations'] as int? ?? 25,
      compactionThresholdTokens: p['compactionThresholdTokens'] as int? ?? 35000,
      compactionRetainTokens: p['compactionRetainTokens'] as int? ?? 8000,
      cwd: projectDir,
    );
  }

  /// Persist settings-panel choices into the `settings` object of the
  /// default profile in the effective agents.json (project wins over home).
  Future<void> saveSettings({String? permissionMode, String? agentMode}) async {
    final file = await _tryRead(projectConfigFile) != null
        ? projectConfigFile
        : homeConfigFile;
    final raw = await _tryRead(file);
    if (raw == null) return;
    try {
      final profiles =
          (jsonDecode(raw) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      final profile = profiles.firstWhere((p) => p['name'] == 'default',
          orElse: () => profiles.first);
      final settings =
          Map<String, dynamic>.from(profile['settings'] as Map? ?? {});
      if (permissionMode != null) settings['permissionMode'] = permissionMode;
      if (agentMode != null) settings['agentMode'] = agentMode;
      profile['settings'] = settings;
      await _writeFile(file, jsonEncode(profiles));
    } catch (_) {
      // Malformed config — skip persistence.
    }
  }

  /// Persist the full MCP server list into the `mcpServers` array of the
  /// default profile in the effective agents.json (project wins over home).
  Future<void> saveMcpServers(List<McpServerConfig> servers) async {
    final file = await _tryRead(projectConfigFile) != null
        ? projectConfigFile
        : homeConfigFile;
    final raw = await _tryRead(file);
    if (raw == null) return;
    try {
      final profiles =
          (jsonDecode(raw) as List<dynamic>).whereType<Map<String, dynamic>>().toList();
      final profile = profiles.firstWhere((p) => p['name'] == 'default',
          orElse: () => profiles.first);
      profile['mcpServers'] = [for (final s in servers) s.toJson()];
      await _writeFile(file, jsonEncode(profiles));
    } catch (_) {
      // Malformed config — skip persistence.
    }
  }

  /// Default workspace declared as `workspace` on the default profile of
  /// the home agents.json. Booting applies it to the whole project context
  /// (sessions, theme, file tree, agent cwd). Null when absent/invalid.
  static Future<String?> defaultWorkspace({String? homeDir}) async {
    final home = homeDir ?? env.homeDir;
    final raw = await _tryRead('$home/.tiny-cli/agents.json');
    if (raw == null) return null;
    try {
      final profiles = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final profile = profiles.firstWhere((p) => p['name'] == 'default',
          orElse: () => profiles.first);
      final ws = profile['workspace'] as String?;
      if (ws != null && Directory(ws).existsSync()) return ws;
    } catch (_) {
      // Malformed config — ignore.
    }
    return null;
  }

  String _defaultProfilesJson() => jsonEncode([
        {
          'name': 'default',
          'model': 'llama3.2:latest',
          'description': 'Default local assistant (Ollama)',
          'temperature': 0.7,
          'environment': {
            'hostUrl': 'http://localhost:11434',
            'appBasePath': '/v1',
            'insecure': true,
          },
        }
      ]);

  Future<void> saveGlobal(Map<String, dynamic> data) async {
    await _writeFile(globalConfigFile, jsonEncode(data));
  }
}

Future<String?> _tryRead(String path) async {
  try {
    return await File(path).readAsString();
  } catch (_) {
    return null;
  }
}

Future<void> _writeFile(String path, String content) async {
  try {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(content);
  } catch (_) {
    // Best-effort — unreadable locations fall back to defaults.
  }
}
