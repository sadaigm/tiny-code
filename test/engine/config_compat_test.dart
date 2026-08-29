import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tiny_code/engine/config_loader.dart';
import 'package:tiny_code/engine/models.dart';
import 'package:tiny_code/engine/session_store.dart';

void main() {
  late Directory home;
  late Directory project;
  late ConfigLoader loader;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('tiny_code_home');
    project = await Directory.systemTemp.createTemp('tiny_code_project');
    loader = ConfigLoader(projectDir: project.path, homeDir: home.path);
  });

  tearDown(() async {
    home.deleteSync(recursive: true);
    project.deleteSync(recursive: true);
  });

  test('auto-creates ~/.tiny-cli/agents.json default when nothing exists',
      () async {
    final config = await loader.load();
    expect(config.endpoint, 'http://localhost:11434/v1');
    expect(config.model, 'llama3.2:latest');
    expect(File(loader.homeConfigFile).existsSync(), isTrue);
  });

  test('project agents.json wins over home', () async {
    await File(loader.projectConfigFile).parent.create(recursive: true);
    await File(loader.projectConfigFile).writeAsString(jsonEncode([
      {
        'name': 'default',
        'model': 'glm-4.6',
        'temperature': 0.3,
        'environment': {
          'hostUrl': 'https://api.example.com',
          'appBasePath': '/v1',
          'apiKey': 'sk-test',
        },
        'mcpServers': [
          {'name': 'wp', 'type': 'stdio', 'command': 'wp-mcp', 'args': ['--x']}
        ],
      }
    ]));

    final config = await loader.load();
    expect(config.model, 'glm-4.6');
    expect(config.endpoint, 'https://api.example.com/v1');
    expect(config.apiKey, 'sk-test');
    expect(config.temperature, 0.3);
    expect(config.mcpServers.single.name, 'wp');
    expect(config.mcpServers.single.type, McpTransport.stdio);
  });

  test('global config overrides permissionMode', () async {
    await File(loader.globalConfigFile).parent.create(recursive: true);
    await File(loader.globalConfigFile)
        .writeAsString(jsonEncode({'permissionMode': 'auto'}));
    final config = await loader.load();
    expect(config.permissionMode, PermissionMode.auto);
  });

  test('sessions save/load/list in tiny-cli format and order', () async {
    final store = SessionStore(loader.sessionsDir);
    final now = DateTime.now();
    final s1 = Session(
      metadata: SessionMetadata(
          id: 'old', createdAt: now, lastUpdatedAt: now.subtract(const Duration(hours: 2))),
      messages: [Message(role: MessageRole.user, content: 'earlier')],
    );
    final s2 = Session(
      metadata: SessionMetadata(id: 'new', createdAt: now, lastUpdatedAt: now, title: 'newer'),
      messages: [Message(role: MessageRole.user, content: 'later')],
    );
    await store.save(s1);
    await store.save(s2);

    final list = await store.list();
    expect(list.map((m) => m.id), ['new', 'old']); // newest first

    final loaded = await store.load('new');
    expect(loaded!.messages.single.content, 'later');
    expect(loaded.metadata.title, 'newer');

    // File content is tiny-cli-shaped JSON.
    final raw =
        jsonDecode(File('${loader.sessionsDir}/new.json').readAsStringSync());
    expect(raw['metadata']['id'], 'new');
    expect(raw['messages'][0]['role'], 'user');

    await store.delete('old');
    expect(await store.load('old'), isNull);
  });

  test('corrupt session file is skipped by list()', () async {
    final store = SessionStore(loader.sessionsDir);
    await Directory(loader.sessionsDir).create(recursive: true);
    await File('${loader.sessionsDir}/bad.json').writeAsString('{nope');
    expect(await store.list(), isEmpty);
  });
}
