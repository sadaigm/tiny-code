import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart' show AskUserAnswer, AskUserResponse;
import '../../engine/protocol.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Tool-approval modal: Allow / Deny / Always this session.
class ApprovalDialog extends StatelessWidget {
  const ApprovalDialog({super.key, required this.request});

  final ApprovalRequestEvent request;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.read<AppState>();
    final args = const JsonEncoder.withIndent('  ')
        .convert(request.call.args)
        .replaceFirst('{', '{\n');

    return AlertDialog(
      backgroundColor: theme.panel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), side: BorderSide(color: theme.line)),
      title: Text('Approve tool call',
          style: TextStyle(color: theme.ink, fontSize: 15)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.call.name,
                style: TextStyle(color: theme.tool, fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.line),
              ),
              child: SingleChildScrollView(
                child: Text(args,
                    style: TextStyle(color: theme.dim, fontSize: 12, fontFamily: 'JetBrains Mono')),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => app.respondApproval(request.id, approved: false),
          child: Text('Deny', style: TextStyle(color: theme.err)),
        ),
        TextButton(
          onPressed: () =>
              app.respondApproval(request.id, approved: true, sessionAlways: true),
          child: Text('Always this session', style: TextStyle(color: theme.dim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: theme.accentDim, foregroundColor: theme.accent),
          onPressed: () => app.respondApproval(request.id, approved: true),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}

/// Questionnaire modal driven by the ask_user tool.
class QuestionnaireDialog extends StatelessWidget {
  const QuestionnaireDialog({super.key, required this.request});

  final AskUserEvent request;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final app = context.read<AppState>();

    return AlertDialog(
      backgroundColor: theme.panel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), side: BorderSide(color: theme.line)),
      title: Text('A few questions',
          style: TextStyle(color: theme.ink, fontSize: 15)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final q in request.payload.questions)
              _QuestionTile(question: q.question, options: q.options),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => app.respondAskUser(request.id, AskUserResponse.skipped()),
          child: Text('Skip', style: TextStyle(color: theme.dimmer)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: theme.accentDim, foregroundColor: theme.accent),
          onPressed: () {
            final answers = <AskUserAnswer>[];
            // Selections are collected via the tile's internal state,
            // stored on the widget tree through a lookup key.
            for (final q in request.payload.questions) {
              final sel = _QuestionTile.selections[q.question];
              if (sel != null) {
                answers.add(AskUserAnswer(question: q.question, selected: sel));
              }
            }
            app.respondAskUser(request.id, AskUserResponse.answered(answers));
            _QuestionTile.selections.clear();
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _QuestionTile extends StatefulWidget {
  const _QuestionTile({required this.question, required this.options});

  final String question;
  final List<String> options;

  // Static so the dialog's submit button can read all answers.
  static final selections = <String, String>{};

  @override
  State<_QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<_QuestionTile> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.question, style: TextStyle(color: theme.ink, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opt in widget.options)
                ChoiceChip(
                  label: Text(opt, style: TextStyle(fontSize: 12)),
                  selected: _selected == opt,
                  onSelected: (sel) {
                    setState(() => _selected = opt);
                    _QuestionTile.selections[widget.question] = opt;
                  },
                  labelStyle: TextStyle(
                      color: _selected == opt ? theme.accent : theme.dim),
                  backgroundColor: theme.bg,
                  side: BorderSide(
                      color: _selected == opt ? theme.accentDim : theme.line),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
