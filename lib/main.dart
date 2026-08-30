import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'platform_env.dart';
import 'state/app_state.dart';
import 'state/workspace.dart';
import 'theme/app_theme.dart';
import 'widgets/shell.dart';

void main() {
  // file_picker 10.x ships no native Linux plugin, so nothing calls
  // registerWith() and FilePicker._instance stays uninitialized there.
  if (isLinux) FilePicker.platform = FilePickerLinux();
  runApp(const TinyCodeApp());
}

/// Boots the app for the selected workspace; shows the gate first when no
/// workspace is remembered, and swaps the engine wholesale when it changes.
class TinyCodeApp extends StatelessWidget {
  const TinyCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppTheme()
        ..loadOverrides([
          Directory(homeDir), // lowest priority
        ]),
      child: ChangeNotifierProvider(
        create: (_) => WorkspaceState(),
        child: Builder(
          builder: (context) {
            final theme = context.watch<AppTheme>();
            final workspace = context.watch<WorkspaceState>();
            return MaterialApp(
              title: 'tiny-code',
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(useMaterial3: true).copyWith(
                scaffoldBackgroundColor: theme.bg,
                scrollbarTheme: theme.scrollbarTheme(),
              ),
              // Boots into the default (home) workspace; keyed on the dir so
              // changing workspace tears the old AppState (and its engine
              // isolate) down and boots fresh. No app-wide SelectionArea —
              // it hijacks mouse events and kills click cursors on UI
              // controls. Selection is scoped per content area (chat
              // stream, thoughts log) instead; see selection_fix.md.
              home: _WorkspaceApp(
                  dir: workspace.dir!, key: ValueKey(workspace.dir)),
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceApp extends StatefulWidget {
  const _WorkspaceApp({super.key, required this.dir});

  final String dir;

  @override
  State<_WorkspaceApp> createState() => _WorkspaceAppState();
}

class _WorkspaceAppState extends State<_WorkspaceApp> {
  Future<AppState>? _future;
  AppState? _created;

  @override
  void initState() {
    super.initState();
    // Workspace theme.json wins over the home-level one (idempotent reload
    // on workspace switch — home defaults were already applied at root).
    // Deferred a frame: this State is created mid-build, and notifying the
    // AppTheme provider now would call markNeedsBuild during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppTheme>().loadOverrides([
        Directory(homeDir),
        Directory(widget.dir),
      ]);
    });
    _future = AppState.create(projectDir: widget.dir).then((app) async {
      // Restore the persisted light/dark choice from agents.json
      // (`settings.theme`) — deferred like loadOverrides above.
      final saved = await app.configLoader.loadTheme();
      if (mounted && saved != null) {
        context.read<AppTheme>().setDark(saved == 'dark');
      }
      return _created = app;
    });
  }

  @override
  void dispose() {
    _created?.dispose(); // kills the engine isolate for the old workspace
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorScreen(error: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final app = snapshot.data!;
        return MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: app),
            ChangeNotifierProvider.value(value: app.log),
            ChangeNotifierProvider.value(value: app.streaming),
            ChangeNotifierProvider.value(value: app.sessions),
            ChangeNotifierProvider.value(value: app.tabState),
          ],
          child: const AppShell(),
        );
      },
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Failed to start engine: $error')),
    );
  }
}
