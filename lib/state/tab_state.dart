import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'app_state.dart';

enum TabType { chat, file }

class WorkspaceTab {
  WorkspaceTab({
    required this.id,
    required this.type,
    this.sessionId,
    this.filePath,
    this.isUnsaved = false,
  });

  final String id;
  final TabType type;

  /// Chat tab: the session it shows. Null until the engine assigns an id on
  /// first send (app_state.dart assigns activeSessionId lazily) — a null
  /// session tab is a view of the "live" current chat.
  String? sessionId;

  /// File tab: absolute path of the file being viewed.
  final String? filePath;
  bool isUnsaved;

  /// Display title; refreshed by TabState for chat tabs from session metadata.
  String title = 'New chat';

  String get fileTitle => filePath!.split('/').last;
}

/// Central-viewport tab state. Chat tabs are bookmarks over sessions: the
/// single engine in [AppState] stays the source of truth, and activating a
/// chat tab swaps the live session via openSession/newChat. File tabs are
/// read-only viewers that never touch the engine.
class TabState extends ChangeNotifier {
  TabState(this.app) {
    // The startup tab has no session id yet; adopt it when the engine
    // assigns one on first send.
    app.addListener(_onAppChanged);
  }

  final AppState app;
  final List<WorkspaceTab> tabs = [];
  String? activeTabId;

  /// Set when a switch/close needs an interrupt confirmation; the viewport
  /// renders the dialog and calls [confirmPendingSwitch]/[cancelPendingSwitch].
  String? pendingSwitchTabId;

  WorkspaceTab? get active =>
      tabs.where((t) => t.id == activeTabId).firstOrNull;

  bool get isRunning => app.running;

  @override
  void notifyListeners() {
    _refreshTitles();
    super.notifyListeners();
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    super.dispose();
  }

  void _onAppChanged() {
    // Adopt the engine-assigned session id into the null (startup) tab —
    // only while it's the active tab (first send). Otherwise the id belongs
    // to an openSession() we initiated for another tab, and adopting here
    // would duplicate that session across two tabs.
    final nullTab = tabs
        .where((t) => t.type == TabType.chat && t.sessionId == null)
        .firstOrNull;
    if (nullTab != null &&
        nullTab.id == activeTabId &&
        app.activeSessionId != null) {
      nullTab.sessionId = app.activeSessionId;
    }
    notifyListeners();
  }

  void _refreshTitles() {
    for (final t in tabs) {
      if (t.type == TabType.chat) {
        final meta = t.sessionId == null
            ? null
            : app.sessions.meta(t.sessionId!);
        t.title = meta?.title?.isNotEmpty == true ? meta!.title! : 'New chat';
      } else {
        t.title = t.fileTitle;
      }
    }
  }

  /// One chat tab at startup; no engine session created yet (matches the
  /// pre-tab behavior of an empty untitled chat).
  void ensureChatTab() {
    if (tabs.isNotEmpty) return;
    final tab = WorkspaceTab(id: const Uuid().v4(), type: TabType.chat);
    tabs.add(tab);
    activeTabId = tab.id;
    notifyListeners();
  }

  /// "+" button: fresh chat session in a new tab. An untouched startup tab
  /// (null session, still live) is adopted rather than duplicated.
  void newTab() {
    final nullTabs = tabs
        .where((t) => t.type == TabType.chat && t.sessionId == null)
        .toList();
    if (nullTabs.isNotEmpty && nullTabs.first == active) {
      app.newChat();
      nullTabs.first.sessionId = app.activeSessionId;
      notifyListeners();
      return;
    }
    for (final t in nullTabs) {
      _remove(t.id);
    }
    app.newChat();
    final tab = WorkspaceTab(
      id: const Uuid().v4(),
      type: TabType.chat,
      sessionId: app.activeSessionId,
    );
    tabs.add(tab);
    activeTabId = tab.id;
    notifyListeners();
  }

  /// Sidebar session click: focus the tab if open, else open + activate.
  void openChat(String sessionId) {
    final existing = tabs
        .where((t) => t.type == TabType.chat && t.sessionId == sessionId)
        .firstOrNull;
    if (existing != null) {
      activate(existing.id);
    } else {
      final tab = WorkspaceTab(
        id: const Uuid().v4(),
        type: TabType.chat,
        sessionId: sessionId,
      );
      // Insert after the last chat tab to keep chat tabs contiguous-ish.
      final lastChat = tabs.lastIndexOf(
        tabs.lastWhere(
          (t) => t.type == TabType.chat,
          orElse: () => tabs.first,
        ),
      );
      tabs.insert(lastChat < 0 ? tabs.length : lastChat + 1, tab);
      activate(tab.id);
    }
  }

  /// File-tree double-click: focus the tab if open, else open a new one.
  void openFile(String filePath) {
    final existing = tabs
        .where((t) => t.type == TabType.file && t.filePath == filePath)
        .firstOrNull;
    if (existing != null) {
      activate(existing.id);
      return;
    }
    final tab = WorkspaceTab(
      id: const Uuid().v4(),
      type: TabType.file,
      filePath: filePath,
    );
    tabs.add(tab);
    activeTabId = tab.id;
    notifyListeners();
  }

  /// Switch tabs. Chat-tab switches away from the live session interrupt the
  /// running turn, so they go through a confirmation when [AppState.running].
  void activate(String tabId) {
    final tab = tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null || tabId == activeTabId) return;
    if (tab.type == TabType.chat &&
        app.running &&
        tab.sessionId != app.activeSessionId) {
      pendingSwitchTabId = tabId;
      notifyListeners();
      return;
    }
    _doActivate(tab);
  }

  void _doActivate(WorkspaceTab tab) {
    pendingSwitchTabId = null;
    activeTabId = tab.id;
    _syncChatSession(tab);
    notifyListeners();
  }

  /// Point the engine at the tab's session. A chat tab with no session id is
  /// a pristine "New chat" — activating it starts fresh rather than resuming.
  void _syncChatSession(WorkspaceTab tab) {
    if (tab.type != TabType.chat) return;
    if (tab.sessionId == app.activeSessionId) return;
    if (tab.sessionId == null) {
      app.newChat();
      tab.sessionId = app.activeSessionId;
    } else {
      app.openSession(tab.sessionId!);
    }
  }

  void confirmPendingSwitch() {
    final tabId = pendingSwitchTabId;
    if (tabId == null) return;
    final tab = tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab != null) _doActivate(tab);
  }

  void cancelPendingSwitch() {
    pendingSwitchTabId = null;
    notifyListeners();
  }

  /// Ctrl+W. Closing a running chat tab would kill the turn → confirm first.
  void close(String tabId) {
    final tab = tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null) return;
    if (tab.type == TabType.chat && app.running && tabId == activeTabId) {
      pendingSwitchTabId = tabId; // dialog copy says "close & interrupt"
      notifyListeners();
      return;
    }
    _remove(tabId);
  }

  void _remove(String tabId) {
    final index = tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;
    tabs.removeAt(index);
    if (tabs.isEmpty) {
      // Last tab closed → fresh chat (new session id, cleared log), not a
      // "null" tab that still views the old session's content.
      pendingSwitchTabId = null;
      app.newChat();
      final tab = WorkspaceTab(
        id: const Uuid().v4(),
        type: TabType.chat,
        sessionId: app.activeSessionId,
      );
      tabs.add(tab);
      activeTabId = tab.id;
      notifyListeners();
      return;
    }
    if (tabId == activeTabId) {
      activeTabId = tabs[index.clamp(0, tabs.length - 1)].id;
      _syncChatSession(active!);
    }
    notifyListeners();
  }

  /// Ctrl+Tab / Ctrl+Shift+Tab.
  void cycle(int delta) {
    if (tabs.length < 2) return;
    final index = tabs.indexWhere((t) => t.id == activeTabId);
    final next = (index + delta) % tabs.length;
    activate(tabs[next < 0 ? next + tabs.length : next].id);
  }

  /// Drag-and-drop reorder from the tab bar (onReorderItem semantics:
  /// newIndex is already adjusted for the removed item).
  void reorderItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= tabs.length) return;
    newIndex = newIndex.clamp(0, tabs.length);
    if (oldIndex == newIndex) return;
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex.clamp(0, tabs.length), tab);
    notifyListeners();
  }
}
