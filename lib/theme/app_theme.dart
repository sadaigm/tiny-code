import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../platform_env.dart';

/// Color tokens lifted from chat-redesign.html `:root`.
/// Override via theme.json (project dir wins over app dir); invalid keys
/// fall back silently to these defaults.
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF0e1114);
  static const panel = Color(0xFF14181d);
  static const stream = Color(0xFF101418);
  static const line = Color(0xFF232a31);
  static const ink = Color(0xFFdde3e8);
  static const dim = Color(0xFF8a939c);
  static const dimmer = Color(0xFF5c656e);
  static const user = Color(0xFF8ae234);
  static const userBubble = Color(0xFF1e2a1c);
  static const userBubbleBorder = Color(0xFF2c3d28);
  static const agent = Color(0xFFa8c8e0);
  static const accent = Color(0xFFe8b45a);
  static const accentDim = Color(0xFF6b5a33);
  static const tool = Color(0xFF4fd6c8);
  static const ok = Color(0xFF8ae234);
  static const err = Color(0xFFef6b6b);

  static const radius = 10.0;
}

/// Built-in light palette — same roles as [AppColors], tuned for a light
/// surface (switched at runtime by the settings panel).
class AppColorsLight {
  static const bg = Color(0xFFf5f6f8);
  static const panel = Color(0xFFffffff);
  static const stream = Color(0xFFeef0f3);
  static const line = Color(0xFFd8dce1);
  static const ink = Color(0xFF1c2126);
  static const dim = Color(0xFF5a636c);
  static const dimmer = Color(0xFF8b949d);
  static const user = Color(0xFF3e7d1f);
  static const userBubble = Color(0xFFe2efdc);
  static const userBubbleBorder = Color(0xFFc3d9b8);
  static const agent = Color(0xFF3d5a75);
  static const accent = Color(0xFF9a6a1a);
  static const accentDim = Color(0xFFeedfbf);
  static const tool = Color(0xFF0f8f84);
  static const ok = Color(0xFF3e7d1f);
  static const err = Color(0xFFc23b3b);
}

/// Mutable theme so theme.json overrides can apply at runtime.
class AppTheme extends ChangeNotifier {
  bool _isDark = true;

  Color _bg = AppColors.bg;
  Color _panel = AppColors.panel;
  Color _stream = AppColors.stream;
  Color _line = AppColors.line;
  Color _ink = AppColors.ink;
  Color _dim = AppColors.dim;
  Color _dimmer = AppColors.dimmer;
  Color _user = AppColors.user;
  Color _agent = AppColors.agent;
  Color _accent = AppColors.accent;
  Color _accentDim = AppColors.accentDim;
  Color _tool = AppColors.tool;
  Color _ok = AppColors.ok;
  Color _err = AppColors.err;
  Color _userBubble = AppColors.userBubble;
  Color _userBubbleBorder = AppColors.userBubbleBorder;

  bool get isDark => _isDark;

  /// Swap between the built-in dark and light palettes at runtime.
  void setDark(bool dark) {
    if (_isDark == dark) return;
    _isDark = dark;
    final c = dark
        ? (
            bg: AppColors.bg,
            panel: AppColors.panel,
            stream: AppColors.stream,
            line: AppColors.line,
            ink: AppColors.ink,
            dim: AppColors.dim,
            dimmer: AppColors.dimmer,
            user: AppColors.user,
            agent: AppColors.agent,
            accent: AppColors.accent,
            accentDim: AppColors.accentDim,
            tool: AppColors.tool,
            ok: AppColors.ok,
            err: AppColors.err,
            userBubble: AppColors.userBubble,
            userBubbleBorder: AppColors.userBubbleBorder,
          )
        : (
            bg: AppColorsLight.bg,
            panel: AppColorsLight.panel,
            stream: AppColorsLight.stream,
            line: AppColorsLight.line,
            ink: AppColorsLight.ink,
            dim: AppColorsLight.dim,
            dimmer: AppColorsLight.dimmer,
            user: AppColorsLight.user,
            agent: AppColorsLight.agent,
            accent: AppColorsLight.accent,
            accentDim: AppColorsLight.accentDim,
            tool: AppColorsLight.tool,
            ok: AppColorsLight.ok,
            err: AppColorsLight.err,
            userBubble: AppColorsLight.userBubble,
            userBubbleBorder: AppColorsLight.userBubbleBorder,
          );
    _bg = c.bg;
    _panel = c.panel;
    _stream = c.stream;
    _line = c.line;
    _ink = c.ink;
    _dim = c.dim;
    _dimmer = c.dimmer;
    _user = c.user;
    _agent = c.agent;
    _accent = c.accent;
    _accentDim = c.accentDim;
    _tool = c.tool;
    _ok = c.ok;
    _err = c.err;
    _userBubble = c.userBubble;
    _userBubbleBorder = c.userBubbleBorder;
    notifyListeners();
  }

  Color get bg => _bg;
  Color get panel => _panel;
  Color get stream => _stream;
  Color get line => _line;
  Color get ink => _ink;
  Color get dim => _dim;
  Color get dimmer => _dimmer;
  Color get user => _user;
  Color get agent => _agent;
  Color get accent => _accent;
  Color get accentDim => _accentDim;
  Color get tool => _tool;
  Color get ok => _ok;
  Color get err => _err;
  Color get userBubble => _userBubble;
  Color get userBubbleBorder => _userBubbleBorder;

  /// Loads theme.json from [dirs], later dirs winning. Unknown keys and
  /// unparsable hex values are ignored.
  void loadOverrides(List<Directory> dirs) {
    if (isWeb) return; // no filesystem on the web build
    for (final dir in dirs) {
      final file = File('${dir.path}/theme.json');
      if (!file.existsSync()) continue;
      try {
        final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        map.forEach(_apply);
      } catch (_) {
        // Malformed file — ignore entirely.
      }
    }
    notifyListeners();
  }

  void _apply(String key, dynamic value) {
    Color? color;
    if (value is String) color = _parseHex(value);
    if (color == null) return;
    switch (key) {
      case 'bg':
        _bg = color;
      case 'panel':
        _panel = color;
      case 'stream':
        _stream = color;
      case 'line':
        _line = color;
      case 'ink':
        _ink = color;
      case 'dim':
        _dim = color;
      case 'dimmer':
        _dimmer = color;
      case 'user':
        _user = color;
      case 'agent':
        _agent = color;
      case 'accent':
        _accent = color;
      case 'accentDim':
        _accentDim = color;
      case 'accent_dim':
        _accentDim = color;
      case 'tool':
        _tool = color;
      case 'ok':
        _ok = color;
      case 'err':
        _err = color;
    }
  }

  static Color? _parseHex(String s) {
    var h = s.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }
}

/// Text styles. Font families fall back to system defaults until real
/// Inter/JetBrains Mono assets are bundled (later phase).
class AppText {
  const AppText._();

  static const ui = TextStyle(fontFamily: 'Inter', color: AppColors.ink);
  static const mono =
      TextStyle(fontFamily: 'JetBrains Mono', color: AppColors.ink);
}
