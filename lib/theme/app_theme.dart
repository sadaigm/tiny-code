import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../platform_env.dart';

/// Color tokens per the UX redesign spec (ux_designer_imp/06).
/// Override via theme.json (project dir wins over app dir); invalid keys
/// fall back silently to these defaults.
class AppColors {
  const AppColors._();

  static const bg = Color(0xFF121316);
  static const panel = Color(0xFF1A1B1E); // surface1: sidebars, panels
  static const surface2 = Color(0xFF24262B); // cards, chat bubbles, inputs
  static const surface3 = Color(0xFF2E3038); // dropdowns, floating overlays
  static const stream = Color(0xFF14161a);
  static const line = Color(0xFF2A2C33);
  static const hover = Color(0xFF2A2C33);
  static const ink = Color(0xFFF0F1F5);
  static const dim = Color(0xFF8C92A4);
  static const dimmer = Color(0xFF626a7a);
  static const user = Color(0xFF8ae234);
  static const userBubble = Color(0xFF1e2a1c);
  static const userBubbleBorder = Color(0xFF2c3d28);
  static const agent = Color(0xFFa8c8e0);
  static const accent = Color(0xFFD4A359); // muted gold
  static const accentDim = Color(0xFF5c4a28);
  static const accentStrong = Color(0xFFD4A359); // filled-button gold (dark keeps accent)
  static const secondary = Color(0xFF2DD4BF); // muted teal
  static const ok = Color(0xFF8ae234);
  static const err = Color(0xFFef6b6b);
  static const scrollbarThumb = Color(0xFF3F424D);

  static const radius = 8.0;
  static const radiusModal = 12.0;

  /// Standard transition for panel/expand animations.
  static const anim = Duration(milliseconds: 250);
  static const animCurve = Curves.easeInOutCubic;
}

/// Built-in light palette — same roles as [AppColors], per the light-theme
/// spec (ux_designer_imp/07_light_theme.md): desktop-class developer light
/// mode with WCAG AA/AAA contrast.
class AppColorsLight {
  static const bg = Color(0xFFF8F9FA); // chat canvas
  static const panel = Color(0xFFFFFFFF); // sidebars & cards
  static const surface2 = Color(0xFFF1F3F5); // hover/selected states
  static const surface3 = Color(0xFFE9EDF2); // dropdowns, floating input
  static const stream = Color(0xFFF8F9FA);
  static const line = Color(0xFFE2E8F0);
  static const hover = Color(0xFFF1F3F5);
  static const ink = Color(0xFF1E293B);
  static const dim = Color(0xFF64748B);
  static const dimmer = Color(0xFF94A3B8);
  static const user = Color(0xFF1E3A8A); // user bubble text (deep indigo)
  static const userBubble = Color(0xFFEBF2FE); // soft indigo tint
  static const userBubbleBorder = Color(0xFFC7DAF8);
  static const agent = Color(0xFF3d5a75);
  static const accent = Color(0xFFB87A00); // high-contrast gold
  static const accentDim = Color(0xFFF3E3C3); // pale gold fill for pills
  static const accentStrong = Color(0xFF9E6800); // filled buttons (accent hover)
  static const secondary = Color(0xFF0F766E); // paths, tags, tools
  static const ok = Color(0xFF3e7d1f);
  static const err = Color(0xFFc23b3b);
  static const scrollbarThumb = Color(0xFFC4C9D2);
}

/// Mutable theme so theme.json overrides can apply at runtime.
class AppTheme extends ChangeNotifier {
  bool _isDark = true;

  Color _bg = AppColors.bg;
  Color _panel = AppColors.panel;
  Color _surface2 = AppColors.surface2;
  Color _surface3 = AppColors.surface3;
  Color _stream = AppColors.stream;
  Color _line = AppColors.line;
  Color _hover = AppColors.hover;
  Color _ink = AppColors.ink;
  Color _dim = AppColors.dim;
  Color _dimmer = AppColors.dimmer;
  Color _user = AppColors.user;
  Color _agent = AppColors.agent;
  Color _accent = AppColors.accent;
  Color _accentDim = AppColors.accentDim;
  Color _accentStrong = AppColors.accentStrong;
  Color _secondary = AppColors.secondary;
  Color _ok = AppColors.ok;
  Color _err = AppColors.err;
  Color _userBubble = AppColors.userBubble;
  Color _userBubbleBorder = AppColors.userBubbleBorder;
  Color _scrollbarThumb = AppColors.scrollbarThumb;

  bool get isDark => _isDark;

  /// Swap between the built-in dark and light palettes at runtime.
  void setDark(bool dark) {
    if (_isDark == dark) return;
    _isDark = dark;
    final c = dark
        ? (
            bg: AppColors.bg,
            panel: AppColors.panel,
            surface2: AppColors.surface2,
            surface3: AppColors.surface3,
            stream: AppColors.stream,
            line: AppColors.line,
            hover: AppColors.hover,
            ink: AppColors.ink,
            dim: AppColors.dim,
            dimmer: AppColors.dimmer,
            user: AppColors.user,
            agent: AppColors.agent,
            accent: AppColors.accent,
            accentDim: AppColors.accentDim,
            accentStrong: AppColors.accentStrong,
            secondary: AppColors.secondary,
            ok: AppColors.ok,
            err: AppColors.err,
            userBubble: AppColors.userBubble,
            userBubbleBorder: AppColors.userBubbleBorder,
            scrollbarThumb: AppColors.scrollbarThumb,
          )
        : (
            bg: AppColorsLight.bg,
            panel: AppColorsLight.panel,
            surface2: AppColorsLight.surface2,
            surface3: AppColorsLight.surface3,
            stream: AppColorsLight.stream,
            line: AppColorsLight.line,
            hover: AppColorsLight.hover,
            ink: AppColorsLight.ink,
            dim: AppColorsLight.dim,
            dimmer: AppColorsLight.dimmer,
            user: AppColorsLight.user,
            agent: AppColorsLight.agent,
            accent: AppColorsLight.accent,
            accentDim: AppColorsLight.accentDim,
            accentStrong: AppColorsLight.accentStrong,
            secondary: AppColorsLight.secondary,
            ok: AppColorsLight.ok,
            err: AppColorsLight.err,
            userBubble: AppColorsLight.userBubble,
            userBubbleBorder: AppColorsLight.userBubbleBorder,
            scrollbarThumb: AppColorsLight.scrollbarThumb,
          );
    _bg = c.bg;
    _panel = c.panel;
    _surface2 = c.surface2;
    _surface3 = c.surface3;
    _stream = c.stream;
    _line = c.line;
    _hover = c.hover;
    _ink = c.ink;
    _dim = c.dim;
    _dimmer = c.dimmer;
    _user = c.user;
    _agent = c.agent;
    _accent = c.accent;
    _accentDim = c.accentDim;
    _accentStrong = c.accentStrong;
    _secondary = c.secondary;
    _ok = c.ok;
    _err = c.err;
    _userBubble = c.userBubble;
    _userBubbleBorder = c.userBubbleBorder;
    _scrollbarThumb = c.scrollbarThumb;
    notifyListeners();
  }

  Color get bg => _bg;
  Color get panel => _panel;

  /// Elevated interactive surface (cards, bubbles, inputs).
  Color get surface2 => _surface2;

  /// Floating overlays (menus, floating input, tooltips).
  Color get surface3 => _surface3;
  Color get stream => _stream;
  Color get line => _line;
  Color get border => _line;
  Color get hover => _hover;
  Color get ink => _ink;
  Color get dim => _dim;
  Color get dimmer => _dimmer;
  Color get user => _user;
  Color get agent => _agent;
  Color get accent => _accent;
  Color get accentDim => _accentDim;
  Color get accentStrong => _accentStrong;
  Color get secondary => _secondary;
  Color get tool => _secondary;
  Color get ok => _ok;
  Color get err => _err;
  Color get userBubble => _userBubble;
  Color get userBubbleBorder => _userBubbleBorder;
  Color get scrollbarThumb => _scrollbarThumb;

  /// Themed scrollbar per spec: 4px thumb, rounded.
  ScrollbarThemeData scrollbarTheme() => ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(_scrollbarThumb),
        thickness: const WidgetStatePropertyAll(4.0),
        radius: const Radius.circular(4),
      );

  /// Gold focus outline per spec (2px accent border).
  InputBorder focusBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppColors.radius),
        borderSide: BorderSide(color: _accent, width: 1.5),
      );

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
      case 'panel' || 'surface1':
        _panel = color;
      case 'surface2':
        _surface2 = color;
      case 'surface3':
        _surface3 = color;
      case 'stream':
        _stream = color;
      case 'line' || 'border':
        _line = color;
      case 'hover':
        _hover = color;
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
      case 'accentStrong':
        _accentStrong = color;
      case 'accent_dim':
        _accentDim = color;
      case 'tool' || 'secondary':
        _secondary = color;
      case 'ok':
        _ok = color;
      case 'err':
        _err = color;
      case 'scrollbarThumb':
        _scrollbarThumb = color;
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
