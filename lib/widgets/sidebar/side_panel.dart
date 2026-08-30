import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/models.dart';
import '../../state/app_state.dart';
import '../../state/tab_state.dart';
import '../../state/session_store_notifier.dart';
import '../../theme/app_theme.dart';
import '../workspace_gate.dart';

/// Left pane: brand, workspace picker, new chat, search, session list,
/// profile footer. Renders a 56px icon rail when [collapsed].
class SidePanel extends StatefulWidget {
  const SidePanel({
    super.key,
    required this.width,
    this.collapsed = false,
    this.searchFocusTick = 0,
  });

  final double width;
  final bool collapsed;
  /// Increments to request focus on the search field (Ctrl+K).
  final int searchFocusTick;

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.searchFocusTick != 0) _grabFocus();
  }

  @override
  void didUpdateWidget(SidePanel old) {
    super.didUpdateWidget(old);
    if (old.searchFocusTick != widget.searchFocusTick) _grabFocus();
  }

  void _grabFocus() {
    if (widget.collapsed) return;
    _searchFocus.requestFocus();
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();

    return Container(
      width: widget.width,
      color: theme.panel,
      child: widget.collapsed
          ? _IconRail(onNewChat: () => context.read<TabState>().newTab())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BrandHeader(),
                _WorkspacePicker(),
                _NewChatButton(),
                _SearchField(focus: _searchFocus),
                const Expanded(child: _SessionList()),
                _ProfileFooter(),
              ],
            ),
    );
  }
}

/// Collapsed 56px rail: brand mark, new chat, avatar.
class _IconRail extends StatelessWidget {
  const _IconRail({required this.onNewChat});

  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Column(
      children: [
        const SizedBox(height: 18),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radius),
            color: theme.accentDim,
          ),
          alignment: Alignment.center,
          child: Text('▲', style: TextStyle(color: theme.accent, fontSize: 13)),
        ),
        const SizedBox(height: 14),
        _RailButton(
            icon: Icons.add_comment_outlined, tooltip: 'New chat (Ctrl+N)',
            onTap: onNewChat),
        _RailButton(
            icon: Icons.folder_open_outlined,
            tooltip: 'Workspace',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkspaceGate()))),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: CircleAvatar(
            radius: 14,
            backgroundColor: theme.line,
            child: Text('🐝', style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }
}

class _RailButton extends _HoverIcon {
  const _RailButton(
      {required super.icon, required super.tooltip, required super.onTap});

  @override
  double get size => 20;
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppColors.radius),
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
        ],
      ),
    );
  }
}

/// Active workspace directory row; tap to switch via the workspace gate.
class _WorkspacePicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    final dir = context.watch<AppState>().configLoader.projectDir;
    final label = dir.split('/').last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Tooltip(
        message: dir,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkspaceGate())),
          icon: Icon(Icons.folder_open_outlined, size: 14, color: theme.dim),
          label: Text(label.isEmpty ? 'workspace' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: theme.dim,
                  fontSize: 11.5,
                  fontFamily: 'JetBrains Mono')),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: theme.line),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
        ),
      ),
    );
  }
}

class _HoverIcon extends StatefulWidget {
  const _HoverIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  double get size => 16;

  @override
  State<_HoverIcon> createState() => _HoverIconState();
}

class _HoverIconState extends State<_HoverIcon> {
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
              color: _hover ? theme.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: widget.size, color: theme.dim),
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
      child: Tooltip(
        message: 'New chat (Ctrl+N)',
        child: TextButton(
          onPressed: () => context.read<TabState>().newTab(),
          style: TextButton.styleFrom(
            backgroundColor: theme.accentStrong,
            foregroundColor: theme.bg,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            alignment: Alignment.centerLeft,
          ),
          child: const Text('＋ New chat',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.focus});

  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: TextField(
        focusNode: focus,
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
            borderRadius: BorderRadius.circular(AppColors.radius),
            borderSide: BorderSide(color: theme.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.radius),
            borderSide: BorderSide(color: theme.line),
          ),
          focusedBorder: theme.focusBorder(),
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
    final sessions = context.watch<SessionStoreNotifier>();
    final active = sessions.activeId == metadata.id;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => context.read<TabState>().openChat(metadata.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active ? theme.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radius),
            // Active sessions carry a 3px gold indicator strip.
            border: Border(
                left: BorderSide(
                    color: active ? theme.accent : Colors.transparent,
                    width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  metadata.title ?? 'untitled',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: active ? theme.ink : theme.dim, fontSize: 12.5),
                ),
              ),
              // Space is always reserved so hover doesn't re-layout the
              // row (that re-layout is what made the tile flicker).
              SizedBox(
                width: 22,
                height: 22,
                child: IgnorePointer(
                  ignoring: !_hover || active,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _hover && !active ? 1 : 0,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 13,
                      tooltip: 'Delete',
                      icon: Icon(Icons.delete_outline, color: theme.dimmer),
                      onPressed: () => sessions.delete(metadata.id),
                    ),
                  ),
                ),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: theme.line,
            child: Text('🐝', style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _PulseDot(),
                    const SizedBox(width: 5),
                    Text('local',
                        style: TextStyle(color: theme.ink, fontSize: 12.5)),
                  ],
                ),
                Text('agent desktop',
                    style: TextStyle(color: theme.dimmer, fontSize: 11)),
              ],
            ),
          ),
          _FooterGear(),
        ],
      ),
    );
  }
}

/// Pulsing green engine-connectivity dot.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppTheme>();
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.3).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
          width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: theme.ok)),
    );
  }
}

class _FooterGear extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return _HoverIcon(
      icon: Icons.settings_outlined,
      tooltip: 'Settings',
      onTap: () { app.settingsTab = 0; app.showSettings = true; },
    );
  }
}
