import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import '../engine/config_loader.dart';
import '../platform_env.dart';

/// Selected workspace (project) directory.
///
/// Defaults to the home dir, so the app boots with `~/.tiny-cli/sessions`
/// in the sidebar. Recently used workspaces are remembered in
/// `~/.tiny-cli/workspaces/config.json` and offered on the startup page.
/// The launch CWD is captured but intentionally unused.
class WorkspaceState extends ChangeNotifier {
  WorkspaceState() {
    final home = homeDir;
    _home = home;
    _dir = home;
    launchCwd = currentPath;
    _loadRecent();
    _applyDefaultWorkspace();
  }

  /// `workspace` on the default profile of ~/.tiny-cli/agents.json boots the
  /// app straight into that project (whole context: sessions, theme, cwd).
  Future<void> _applyDefaultWorkspace() async {
    final ws = await ConfigLoader.defaultWorkspace(homeDir: _home);
    if (ws == null || ws == _dir) return;
    await _set(ws);
  }

  static String get _recentFile =>
      '$homeDir/.tiny-cli/workspaces/config.json';

  late final String _home;
  String? _dir;
  String? get dir => _dir;

  /// Directory the process was launched from (captured, not used yet).
  late final String launchCwd;

  /// Most-recently-used first.
  List<String> recent = [];

  bool get isHome => _dir == _home;

  void _loadRecent() {
    try {
      final f = File(_recentFile);
      if (!f.existsSync()) return;
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      recent = (map['recent'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((p) => Directory(p).existsSync())
          .toList();
    } catch (_) {
      // Malformed file — start fresh.
    }
  }

  Future<void> _saveRecent() async {
    try {
      final f = File(_recentFile);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'recent': recent.take(10)}));
    } catch (_) {
      // Best effort.
    }
  }

  /// Opens the native folder picker; notifies on a new selection.
  Future<void> pick() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    await _set(result);
  }

  /// Selects a recent-workspace entry from the startup list.
  Future<void> select(String dir) => _set(dir);

  /// Back to the default home workspace.
  Future<void> useHome() => _set(_home);

  Future<void> _set(String dir) async {
    _dir = dir;
    notifyListeners();
    if (dir == _home) return; // home is the implicit default, not a "recent"
    recent = [dir, ...recent.where((p) => p != dir)];
    await _saveRecent();
  }
}
