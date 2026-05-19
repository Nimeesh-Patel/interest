# Project

Flutter mobile app — Markdown-first, Obsidian-compatible entity tracker. See README.md for full architecture, data model, navigation patterns, and run instructions.

## Key constraints — must not be violated

- No state management libraries (`setState` only)
- No database — Markdown files in `<vault>/Interesting/Entities/` and `<vault>/Interesting/Boards/` are the source of truth
- No parallel JSON state persistence — `saveData()` writes `.md` files only
- No auth, no cloud, no backend. Network calls: (1) `LetterboxdService.fetchAndImport()` — user-triggered HTTP GET to Letterboxd RSS URL; (2) `GrokipediaService` — non-blocking HTTP GETs triggered by entity screen open; (3) `AnkiConnectService` — user-triggered HTTP POSTs to local AnkiConnect. All fail silently on any error. No background polling, no auth.
- `entity.id` = `alias` in YAML frontmatter — immutable after creation; never regenerate on rename
- `board.id` = `slugify(board.name)` — derived at load time; stable within a session
- `updated_at` must be stamped on every entity mutation — done inside `_save()` in `entity_screen.dart`
- Deleting an entity must also remove its entity links and board memberships — done in `_deleteEntity` in `home_screen.dart`; `saveData()` re-writes board files without the deleted entity
- Deleting a board must also remove its board entity entries — done in `_deleteBoard` in `home_screen.dart`; board `.md` file is deleted by orphan cleanup in `saveData()`
- In `entity_screen.dart`, core field mutations (name, category, tags, score, notes, links) do **not** call `_save()` individually — save is deferred to the explicit Save button via `_saveEdit()`. Only join-table mutations (`_addToBoard`, `_removeFromBoard`, `_createEntityLink`, `_deleteEntityLink`) call `_save()` immediately. Do not add auto-save calls to core field methods.
- `Entity.copyWith()` exists for deep copy — use it when snapshotting entity state (edit mode enter/cancel in `entity_screen.dart`)
- `AppData` typedef lives in `markdown_storage_service.dart` — import from there, not a separate file
- Vault path is stored in SharedPreferences via `VaultService` — never hardcode a path
- `_StoragePermissionGate` in `main.dart` must remain the outermost widget in `EntityTrackerApp.build`; it gates all screens on Android storage permission and re-checks on app resume
- `_semanticSections` const map in `markdown_storage_service.dart` defines which `##` sections the app owns (`Why Interesting`, `Related`, `Sources`). Only these are rewritten on save. All other `##` sections in an entity file are user territory — preserve them verbatim. Do not add new hardcoded section names outside this map.
- Wikilink extraction scans the **entire Markdown body** (`_extractWikilinks(body)`) — not just `## Related`. This means `[[wikilinks]]` in any prose section generate graph edges. `## Related` is only the curated list written back on save; inline wikilinks remain in their prose section untouched. Do not narrow this back to section-scoped extraction.
- All entity-list sorting routes through `MarkdownStorageService.sortEntities(entities, sortOrder)`. Sort keys: `latest`, `oldest`, `high_score`, `low_score`, `alpha` (A→Z case-insensitive), `alpha_rev` (Z→A). Add new sort options there first, then add `DropdownMenuItem` entries in the relevant screens. Entity/board pickers are pre-sorted A→Z inline (not via `sortEntities`).
- Templates are used for initial file creation only — once a file exists, it is patched, never regenerated from the template again
- Template files live in `Interesting/Templates/`; they are identified by `template: true` in frontmatter; `{{title}}` is the only supported placeholder
- `default.md` is seeded with `category: Default` (not "General"). The other seeded templates: `person.md` → People, `product.md` → Products, `idea.md` → Ideas, `movie.md` → Movies. The movie template uses `## Thoughts` / `## Related` / `## Sources` (not `## Why Interesting`).
- `Entity` has three optional nullable movie-specific fields: `watchedDate` (String?), `letterboxdUrl` (String?), `tmdbId` (String?). These are parsed by `_parseEntityFile` and written by `_buildFrontmatter` when non-null — they survive all app saves. Do not add new category-specific fields without updating both `_parseEntityFile` and `_buildFrontmatter`.
- `LetterboxdService` writes movie `.md` files directly to `Interesting/Entities/` — it bypasses `saveData()`. This is intentional: it needs full control over `## Thoughts` content at creation time. After import, `HomeScreen._reloadData()` picks up the new files via `loadData()`. Do not refactor this to go through `saveData()` without resolving the Thoughts injection problem.

## Android widget constraints

- Widget reads vault path from Android `FlutterSharedPreferences` (key: `flutter.vault_path`) — this is how Flutter's `shared_preferences` plugin stores data on Android. Do NOT use VaultService or any Flutter API from widget code.
- Widget always writes `category: Default` in frontmatter — no category selection in the widget
- Widget builds frontmatter from scratch (alias, category, timestamps); it uses `default.md` only for the body sections structure (frontmatter stripped before use)
- Widget filename convention: `safeFileName(title) = title.replace([/\\:*?"<>|], '_') + ".md"` — matches Dart `saveData()` which uses entity name as filename
- Widget `alias` = `slugify(title)` with `-2`, `-3` collision suffix checked against existing files in the entities dir
- `QuickCaptureWidget.kt` is abstract — never register it directly in the manifest. Only the three concrete subclasses (`QuickCaptureWidget1x1`, `QuickCaptureWidget2x1`, `QuickCaptureWidget2x2`) are registered as receivers.
- Do not add more widget sizes without adding a corresponding concrete subclass, widget info XML, layout XML, and manifest receiver entry.

## Anki subsystem constraints

- `anki_id` in card frontmatter is the stable cross-system identity — immutable after first write; never regenerate on rename or file move
- `AnkiConnectService` is all-static; every code path must `catch (_) { return null; }` — same pattern as `GrokipediaService`; never throws
- `AnkiStorageService` writes directly to `Interesting/Anki/` — does NOT call `saveData()`; same as `LetterboxdService` writing to `Interesting/Entities/`
- Semantic sections for Basic: `Front`, `Back` (H1 `#`, not H2 `##`). For Cloze: `Text`. All other `#`/`##` sections are user territory — preserved verbatim on every save
- Deletion is always soft: move to `Interesting/Anki/.trash/` via `trashCard()`; never hard-delete
- Sync is manual only (triggered by Sync button in AnkiScreen) — no filesystem watchers, no background polling, no auto-sync
- Never write Anki review metadata (intervals, ease, due dates, review history) into Markdown — only semantic content (front/back/text, tags, deck) syncs
- `VaultService.ankiPath(vaultPath)` and `ankiTrashPath(vaultPath)` take a `String` arg — same signature as `entitiesPath()` / `boardsPath()` / `templatesPath()`
- `updated_at` in card frontmatter must be stamped on every mutation — done inside `AnkiStorageService.saveCard()` and `createNewCard()`
- Conflict resolution: compare `card.updatedAt.millisecondsSinceEpoch` vs `ankiNote['mod'] * 1000`; 5-second tolerance; winner overwrites the other side
- `AnkiSyncService.sync()` fetches Anki note details in batches of 50 via `notesInfo` — do not fetch all at once
- AnkiConnect URL stored in SharedPreferences (key: `'anki_connect_url'`); default `'http://localhost:8765'`; on Android the user must set the desktop's LAN IP
- Full subsystem docs (file format, sync algorithm, UI): [docs/anki.md](docs/anki.md)

## Tasks subsystem constraints

Full implementation docs: [docs/tasks.md](docs/tasks.md).

- Task files live in `Interesting/Tasks/`; **no YAML frontmatter** — pure Markdown. `VaultService.tasksPath(vaultPath)` returns the path.
- Task syntax: `- [ ] text` / `- [x] text`. Regex: `^\s*-\s+\[([ xX])\]\s+(.+)$`. Subtasks use 2-space indent multiples. Do not deviate.
- Storage model: one `.md` file per topic, many tasks per file.
- `TaskStorageService` is all-static; every public method wraps in `try/catch`, never throws.
- All mutations: `readAsLines() → mutate → writeAsString(join('\n'))`. Never regenerate whole file.
- `parseNodes(lines)` is **pure** (no I/O) — only call after `loadLines()`; never from `loadTaskFiles()`.
- `deleteBlock` uses `removeRange(startLine, endLine + 1)` — always removes the full subtree atomically.
- `TaskBlock.endLine` is computed from the live subtree — do not cache across reloads.
- `_collapsed` expansion state in `_TaskFileScreenState` is **session-only** — never persist to Markdown or SharedPreferences.
- `TaskFileScreen` receives `filePath`, `title`, and optional `onRenamed(newPath, newTitle)` callback — still self-contained (no entity lists).
- `HomeScreen` owns `_taskFiles` state and task-file CRUD: `_showCreateTaskFile`, `_showDeleteTaskFileConfirm`, `_showTaskFileOptions`, `_showRenameTaskFile`, `_reloadTaskFiles`.
- Deletions are hard-delete (no trash). Task files have no `alias` and are not identity-bearing.
- Do NOT integrate task wikilinks into the `EntityLink` graph — task files have no `alias`.
- Do NOT add due dates, reminders, recurring tasks, priorities, notifications, drag-to-reorder, or calendar integration.

## Grokipedia integration constraints

- `GrokipediaService` is stateless (all-static); base `https://grokipedia.com`; search: `/api/full-text-search?query=…&limit=5`; page: `/api/page?slug=…&includeContent=true`
- Never writes to vault or Markdown files — external knowledge only; user adds notes manually if they want to persist anything
- Every code path in `GrokipediaService` must catch all exceptions and return `null` — the `catch (_) { return null; }` pattern is intentional and must be preserved
- `url_launcher` opens `https://grokipedia.com/page/{slug}` in external browser — no native Grokipedia app exists (PWA only); do not add "Open in App" without verifying a real URL scheme exists
- Grokipedia state (`_grokArticle`, `_grokSearched`, `_grokSummaryExpanded`, `_grokSummaryFetching`, `_grokFetchedSummary`) lives only in `_EntityScreenState` — no persistence, no propagation to other screens
- Do not cache results, inject article content into notes, or auto-populate any Markdown field

# Approach

## Philosophy:
1. Reject blind empiricism and use only explanatory arguments to draw conclusions.
2. Treat my ideas as conjectures in an evolving theory.

## Idea:
- Edison said: research is one per cent inspiration and ninety-nine per cent perspiration.

## Implementation of idea:

Step 1: Based on what knowledge, understanding, and explanations I have provided you, do the role of *perspiration*:

- Draw out implications as much as you can
- Make inexplicit, implicit, and unconscious assumptions explicit
- Compute consequences across the entire web of other ideas

Step 2: During step 1, if something seems to come in conflict in the knowledge you have:

- state conflicts clearly as precise problems or questions
- *do not!* give any advice

Step 3: I'll do the inspiration and knowledge creation part to solve those problems which arise in Step 2. Take input from me.

Loop Step 1 to Step 3
## Roles & Process
Work iteratively:

- you: perspiration!
- me: inspiration & knowledge creation (and perspiration when required)

## Style:
keep the answers hard-to-vary and avoid redundancy and ramblings

## Background Knowledge
I follow Karl Popper and David Deutsch in epistemology, physics, politics, and related things.