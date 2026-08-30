# Session Monitoring Dashboard — Implementation Task List

Executable task breakdown of `ux_designer_imp/chat_monitoring.md`. Work top-to-bottom. Each task has files, steps, and a manual verify check. Mark progress by editing this file (`[x]`).

Conventions (same as `implementation-tasks.md`):
- `lib/engine/**` is pure Dart — no Flutter imports.
- UI state = Provider + ChangeNotifier; granular rebuilds, notify only on structural changes.
- Colors/spacing from `lib/theme/app_theme.dart` (`AppColors`); gold accents (`accent`) for primary, `tool` teal for system status, `ok`/`err` for status badges.
- Tests deferred — manual verify only.

Dashboard layout being built (from spec §2):

```
Canvas header toggle: [ 💬 Chat Stream | 📊 Session Dashboard ]
Zone 1: 4 KPI cards        (total calls, tokens/context, connected systems, duration/latency)
Zone 2: per-system cards   (MCP servers + system/CLI, read ⬇ / write ⬆ metrics)
Zone 3: inspector table    (filter bar + rows + expandable payload views)
```

---

## Phase 1 — Telemetry data layer (pure Dart)

- [x] **T1.1 Execution event model**
  Files: `lib/engine/models.dart` (extend)
  New type `ToolExecutionEvent`: id, timestamp, source (`system:cli`, `system:file`, `mcp:<server>`), tool name, operation class enum (`read` / `write` / `execute`), status (`ok` / `error`), summary line, request payload (JSON string), response payload / stdout+stderr, durationMs. JSON (de)serialization for session persistence.
  Verify: round-trip encode/decode by inspection or later tests.

- [x] **T1.2 Event capture hook**
  Files: `lib/engine/agent.dart` (or wherever `ToolCall → ToolResult` resolves — grep `ToolResult` for the seam)
  After each tool execution (both built-in `lib/engine/tools/**` and MCP `lib/engine/mcp/**`), emit a `ToolExecutionEvent`. Classify operation: read (fetch/list/search/grep/read), write (create/update/publish/write/sync), execute (bash/CLI). Build the human summary from tool name + key args/result counts. Errors produce status `error` with the error text as response.
  Verify: run a session with a grep + a bash call + one MCP call; each appears as an event.

- [x] **T1.3 Telemetry store**
  Files: `lib/state/telemetry_store.dart`
  `TelemetryStore extends ChangeNotifier`: append-only event list, computed getters — totals (pass/fail), token/context usage (from existing usage fields in `Message`/session state), per-source aggregates (reads/writes per system, distinct MCP servers used), elapsed time + avg duration. Reset per session; persist via `session_store.dart` if trivial.
  Verify: `flutter analyze` clean; store updates fire notifyListeners once per event.

## Phase 2 — Dashboard view

- [x] **T2.1 Canvas header toggle**
  Files: `lib/widgets/chat/chat_pane.dart` (header), new `lib/widgets/dashboard/session_dashboard.dart`
  Add `[ 💬 Chat Stream | 📊 Dashboard ]` toggle in the chat canvas header. Toggles between existing chat stream and the dashboard widget; state lives in `TabState`/`AppState` (local to tab). Dashboard view does not subscribe to streaming-text notifications.
  Verify: toggle back and forth; chat scroll position/streaming unaffected.

- [x] **T2.2 Zone 1 — KPI cards**
  Files: `lib/widgets/dashboard/kpi_cards.dart`
  Four cards from `TelemetryStore` getters: Total Executions (X · N pass / M fail), Token & Context (count + linear fill bar), Connected Systems (n MCP + CLI), Duration & Latency (total runtime, avg ms/call). Elevated card surface on `panel`, gold `accent` highlights, teal `tool` for system status.
  Verify: cards update after each tool call without full-chat rebuild.

- [x] **T2.3 Zone 2 — per-system cards**
  Files: `lib/widgets/dashboard/system_cards.dart`
  One card per source in the telemetry aggregates (HubSpot-style CRM, WordPress CMS, Local System/CLI — driven by actual MCP server names, not hardcoded). Read metric (blue/dim accent ⬇) and write metric (green `ok` ⬆) from per-source read/write counts. Horizontally scrollable `Row` if overflow.
  Verify: a session touching 2 MCP servers + system tools shows 3 cards with correct counts.

- [x] **T2.4 Zone 3 — inspector table**
  Files: `lib/widgets/dashboard/execution_table.dart`
  Filter bar: category pills (All / System-CLI / MCP), status filter (All / Errors only), search input on tool name + summary. Table rows: status badge (`200 OK` soft green, `500 ERR` soft red, `Exit 0` gray), timestamp `HH:mm:ss`, source, operation-class badge (READ/WRITE/EXECUTE), summary, expand chevron. Newest first.
  Verify: filters + search combine correctly on a mixed session.

- [x] **T2.5 Expanded payload views**
  Files: `lib/widgets/dashboard/payload_views.dart`
  Expand a row → detail region under it. MCP/API events: side-by-side request/response JSON viewer (mono font, collapsible tree or preformatted pretty-printed JSON). System/CLI events: dark terminal container with the exact command, then `stdout` / `stderr` sections.
  Verify: one MCP row and one bash row expand with the right renderer; long output scrolls, doesn't break row layout.

## Phase 3 — Polish

- [ ] **T3.1 Empty & loading states, responsiveness**
  Files: dashboard widgets
  Empty state ("No executions yet this session") for all three zones; KPI cards show `—` placeholders; dashboard usable at narrow widths (cards wrap 2×2); long summaries ellipsize in table, full text in expanded view.
  Verify: fresh session shows empty state; resize window through breakpoints.

- [ ] **T3.2 Full manual pass**
  Run a real session mixing bash, file read/write, and ≥1 MCP server. Toggle to dashboard mid-session and after completion. Confirm KPIs, per-system counts, table rows, and both expanded views all match what actually happened in the chat stream.
