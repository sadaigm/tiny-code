import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../state/app_state.dart';
import '../../state/session_store_notifier.dart';
import '../../theme/app_theme.dart';
import '../workspace_gate.dart';

/// Left pane: brand, new chat, search, session list, profile footer.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final collapsed = width < 100;

    return Container(
      width: width,
      color: theme.panel,
      child: collapsed
          ? Center(
              child: Icon(Icons.add_comment_outlined,
                  size: 20, color: theme.dimmer))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BrandHeader(),
                _NewChatButton(),
                _SearchField(),
                const Expanded(child: _SessionList()),
                _ProfileFooter(),
              ],
            ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.accentDim,
            ),
            alignment: Alignment.center,
            child: Text('▲', style: TextStyle(color: theme.accent, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('tiny-code',
                    style: TextStyle(
                        color: theme.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                Text(context.watch<AppState>().config.model,
                    style: TextStyle(color: theme.dimmer, fontSize: 11)),
              ],
            ),
          ),
          _IconAction(
              icon: Icons.folder_open_outlined,
              tooltip: 'Workspace',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const WorkspaceGate()))),
        ],
      ),
    );
  }
}

class _IconAction extends StatefulWidget {
  const _IconAction(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _hover ? theme.line : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 16, color: theme.dim),
          ),
        ),
      ),
    );
  }
}

class _NewChatButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: TextButton(
        onPressed: () => context.read<AppState>().newChat(),
        style: TextButton.styleFrom(
          backgroundColor: theme.accentDim,
          foregroundColor: theme.accent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.centerLeft,
        ),
        child: const Text('＋ New chat', style: TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: TextField(
        onChanged: (q) => context.read<SessionStoreNotifier>().query = q,
        style: TextStyle(color: theme.ink, fontSize: 13),

        decoration: InputDecoration(
          hintText: 'Search chats…',
          hintStyle: TextStyle(color: theme.dimmer, fontSize: 13),
          prefixIcon:
              Icon(Icons.search, size: 16, color: theme.dimmer),
          isDense: true,
          filled: true,
          fillColor: theme.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.line),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
        ),
      ),
    );
  }
}

/// Session list grouped by recency: Today / Yesterday / This week / Older.
class _SessionList extends StatelessWidget {
  const _SessionList();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final sessions = context.watch<SessionStoreNotifier>();
    final grouped = sessions.grouped(DateTime.now());

    if (grouped.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('No chats yet',
            style: TextStyle(color: theme.dimmer, fontSize: 12)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      itemCount: grouped.length,
      itemBuilder: (context, sectionIndex) {
        final label = grouped.keys.elementAt(sectionIndex);
        final items = grouped[label]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(label,
                  style: TextStyle(
                      color: theme.dimmer,
                      fontSize: 10.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600)),
            ),
            for (final s in items) _SessionTile(metadata: s),
          ],
        );
      },
    );
  }
}

class _SessionTile extends StatefulWidget {
  const _SessionTile({required this.metadata});

  final SessionMetadata metadata;

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final metadata = widget.metadata;
    final active = context.watch<SessionStoreNotifier>().activeId == metadata.id;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => context.read<AppState>().openSession(metadata.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? theme.accentDim
                : (_hover ? theme.panel : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            metadata.title ?? 'untitled',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: active ? theme.accent : theme.dim, fontSize: 12.5),
          ),
        ),
      ),
    );
  }
}

class _ProfileFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Container(
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: theme.line))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: theme.line,
            child: Text('🐝', style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('local',
                  style: TextStyle(color: theme.ink, fontSize: 13)),
              Text('agent desktop',
                  style: TextStyle(color: theme.dimmer, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
