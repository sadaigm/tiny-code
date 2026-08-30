import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/telemetry_store.dart';
import '../../theme/app_theme.dart';

/// Expanded row body: side-by-side JSON viewer for MCP/API calls, dark
/// terminal container for system/CLI calls.
class PayloadView extends StatelessWidget {
  const PayloadView({super.key, required this.event});

  final ToolExecutionEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.stream,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: theme.line),
      ),
      child: event.isMcp ? _jsonView(theme) : _terminalView(theme),
    );
  }

  Widget _jsonView(AppTheme theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _JsonPane(title: 'Request', text: _pretty(event.requestJson))),
        const SizedBox(width: 12),
        Expanded(child: _JsonPane(title: 'Response', text: _pretty(event.response))),
      ],
    );
  }

  Widget _terminalView(AppTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Command', theme),
        const SizedBox(height: 4),
        _CodeBlock(text: event.toolName == 'bash' ? _bashCommand() : event.requestJson),
        const SizedBox(height: 10),
        _SectionLabel('Output', theme),
        const SizedBox(height: 4),
        _CodeBlock(text: event.response.isEmpty ? '(empty)' : event.response),
      ],
    );
  }

  String _bashCommand() {
    try {
      final decoded = jsonDecode(event.requestJson);
      if (decoded is Map<String, dynamic>) {
        final cmd = decoded['command'];
        if (cmd is String) return cmd;
      }
    } catch (_) {}
    return event.requestJson;
  }

  static String _pretty(String s) {
    if (s.isEmpty) return '(empty)';
    try {
      final decoded = jsonDecode(s);
      final enc = const JsonEncoder.withIndent('  ').convert(decoded);
      return enc;
    } catch (_) {
      return s;
    }
  }
}

class _JsonPane extends StatelessWidget {
  const _JsonPane({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title, theme),
        const SizedBox(height: 4),
        _CodeBlock(text: text),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.theme);

  final String label;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(),
          style: TextStyle(
              color: theme.dimmer,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600));
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 320),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.line),
      ),
      child: SingleChildScrollView(
        child: SelectionArea(
          child: Text(text,
              style: TextStyle(
                  color: theme.ink,
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11.5,
                  height: 1.45)),
        ),
      ),
    );
  }
}
