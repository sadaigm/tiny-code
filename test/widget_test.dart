import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tiny_code/state/app_state.dart';
import 'package:tiny_code/theme/app_theme.dart';
import 'package:tiny_code/widgets/shell.dart';

void main() {
  test('AppColors tokens match chat-redesign.html palette', () {
    expect(AppColors.bg, const Color(0xFF0e1114));
    expect(AppColors.panel, const Color(0xFF14181d));
    expect(AppColors.stream, const Color(0xFF101418));
    expect(AppColors.line, const Color(0xFF232a31));
    expect(AppColors.ink, const Color(0xFFdde3e8));
    expect(AppColors.accent, const Color(0xFFe8b45a));
    expect(AppColors.tool, const Color(0xFF4fd6c8));
    expect(AppColors.err, const Color(0xFFef6b6b));
  });

  testWidgets(
    '3-pane shell: ctx panel hides below 1100px',
    (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // All setup here is real I/O (file reads, Isolate.spawn) which never
    // completes in the fake-async zone of a widget test — run it for real.
    // A project config is seeded so load() never falls back to the real
    // ~/.tiny-cli/agents.json (which may define real MCP servers).
    final AppState? stateOrNull = await tester.runAsync(() async {
      final projectDir =
          await Directory.systemTemp.createTemp('tiny_code_widget_test');
      await Directory('${projectDir.path}/.tiny-cli').create(recursive: true);
      await File('${projectDir.path}/.tiny-cli/agents.json').writeAsString(
          '[{"name":"default","model":"test","environment":{"hostUrl":"http://localhost:1","appBasePath":"/v1"}}]');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      return AppState.create(projectDir: projectDir.path);
    });
    addTearDown(() => stateOrNull?.dispose());
    // The rest of the test is meaningless without a state — fail loudly.
    final state = stateOrNull ?? fail('AppState.create returned null');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppTheme()),
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: state.log),
          ChangeNotifierProvider.value(value: state.streaming),
          ChangeNotifierProvider.value(value: state.sessions),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    expect(find.text('ACTIVE PLAN'), findsOneWidget);

    tester.view.physicalSize = const Size(900, 900);
    // Not pumpAndSettle — the streaming cursor blinks forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ACTIVE PLAN'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
