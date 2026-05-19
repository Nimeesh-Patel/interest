# Entity Tracker

Single-user Flutter app for tracking entities (people, ideas, solutions, products, or any user-defined category). Data lives as plain Markdown files in a user-chosen vault folder — readable and editable by Obsidian or any text editor. No auth, no cloud, no backend.

## What it does

- Track entities across user-defined categories
- Each entity has: notes ("Why it matters"), links ("Sources"), tags, score, and related entities
- Entity detail has a display mode (read-only) and an edit mode (explicit Save/Cancel)
- Entities are linked to each other via Obsidian-style wikilinks — forming a navigable graph
- Entities can be grouped into boards (independent of categories; many-to-many)
- Board members can be sorted by date, score, name (A→Z / Z→A), or category
- Score (0–10, step 0.1) is optional per entity
- Tags are reusable and created inline with autocomplete
- Categories are created, renamed, and deleted from the home screen
- Search by name; filter by category; sort by date, score, or name (A→Z / Z→A)
- Templates management: create, edit, and delete entity templates from within the app (raw Markdown editor)
- On first launch: choose a vault folder (Obsidian vault or any folder)
- All data persists as `.md` files; fully readable in Obsidian
- **Android home-screen widget** in three sizes (1×1, 2×1, 2×2): instant entity capture without opening the app — title + optional quick note → Markdown file written directly to vault
- **Letterboxd RSS ingestion**: import watched films from a Letterboxd RSS feed into the vault as first-class `Movies` entities; manual trigger from Settings; deduplicates by TMDB ID then normalized title
- **Grokipedia External Knowledge**: on any entity screen, automatically searches Grokipedia by entity name; shows matched article title with "Open Article" (browser) and collapsible inline summary card; degrades gracefully to "No article found" on failure; never modifies Markdown files
- **Anki bidirectional sync**: Markdown cards in `Interesting/Anki/` sync bidirectionally with Anki via AnkiConnect; Basic and Cloze note types; last-modified-wins conflict resolution; manual sync only; safe deletion via `.trash/`; see [docs/anki.md](docs/anki.md)
- **Markdown-native ToDo layer**: hierarchical task blocks in `Interesting/Tasks/`; standard `- [ ]` / `- [x]` syntax; nested subtasks and inline notes via Markdown indentation; collapsible task trees; inline task/note editing; per-task sibling task add; task-file rename; `[[wikilinks]]` preserved; no YAML frontmatter — fully Obsidian-compatible; see [docs/tasks.md](docs/tasks.md)

## Architecture

No state management libraries. Pure `setState`. No repository pattern.

```
lib/
  main.dart                             — async vault-path check; _StoragePermissionGate (Android All Files Access, re-checks on resume); routes to VaultSetupScreen or HomeScreen

  core/
    vault_service.dart                  — vault path in SharedPreferences (key: 'vault_path'); path helpers (entitiesPath/boardsPath/templatesPath/ankiPath/ankiTrashPath/tasksPath); ensureVaultDirectories (creates dirs + seeds 5 default templates)
    vault_setup_screen.dart             — first-launch folder picker; saves path; navigates to HomeScreen

  shared/
    markdown/
      md_utils.dart                     — pure text utilities (no I/O): splitFrontmatter, parseSectionsH2, parseSectionsH1 (anki), extractH1, extractWikilinks, parseSectionAsWikilinks, parseSectionAsList, slugify, sanitizeFilename, generateUniqueId, msToIso, parseIsoToMs
      md_io.dart                        — filesystem helpers: listMdFiles, readFrontmatter, readAllMdContents
    widgets/
      input_dialog.dart                 — showInputDialog() — reusable text-input AlertDialog; manages its own controller
      confirm_dialog.dart               — showConfirmDialog() — reusable confirmation AlertDialog; returns bool
      bottom_sheet_menu.dart            — showBottomSheetMenu() + BottomSheetMenuItem — action sheet
      section_header.dart               — SectionHeader widget — bold title + gap + optional trailing widget
      empty_state.dart                  — EmptyState widget — centered icon + message text
      wikilink_text.dart                — WikilinkText widget — RichText with blue [[wikilink]] spans; strikethrough support

  features/
    entities/
      models/
        entity.dart                     — Entity {id, name, categoryId, notes, links, tags, score, createdAt, updatedAt, rawSections, watchedDate?, letterboxdUrl?, tmdbId?} + copyWith()
        category.dart                   — Category {id, name}
        entity_link.dart                — EntityLink {id, from, to, type}
      services/
        markdown_storage_service.dart   — canonical storage layer; loadData/saveData; dynamic section parser (_parseSections); section-aware patching (_patchEntityContent); template loading; AppData typedef; static ID/link/sort helpers
        letterboxd_service.dart         — Letterboxd RSS ingestion; fetchAndImport(); getRssUrl/setRssUrl (SharedPreferences key: 'letterboxd_rss_url'); ImportResult {created, updated, skipped, error?}; dedup by tmdbId then normalized title; writes .md directly to Entities/
        grokipedia_service.dart         — external knowledge; GrokipediaArticle {title, slug, snippet?}; findArticle/fetchPageSummary; all-static; all-catch-null
      screens/
        entity_screen.dart              — display mode (read-only) / edit mode (deferred save with Cancel); name, category, tags, score, boards, notes, links, related; display mode includes External Knowledge section (Grokipedia, non-blocking initState)

    boards/
      models/
        board.dart                      — Board {id, name}
        board_entity.dart               — BoardEntity {boardId, entityId} (join table; derived at load time from board .md wikilinks)
      screens/
        board_detail_screen.dart        — entities in a board; 7 sort options; FAB to add entities; self-contained

    tasks/
      models/
        task.dart                       — TaskFile {filePath, name, totalTasks, completedTasks, progress}; summary only — tasks are never reified as in-memory objects
        task_block.dart                 — TaskNode abstract; TaskHeaderNode {lineIndex, headingLevel, text}; TaskProseNode {lineIndex, raw}; TaskBlock {text, completed, indentSpaces, startLine, noteLineIndices[], children[], endLine (computed)}; in-memory only; see docs/tasks.md
      services/
        task_storage_service.dart       — task file I/O in Interesting/Tasks/; all-static, all-catch; flat ops: loadTaskFiles/loadLines/toggleTask/addTask/deleteTask/updateTaskText/createTaskFile/deleteTaskFile/renameTaskFile; hierarchical ops: parseNodes(lines) (pure, no I/O), addNote/addSubtask/deleteBlock/updateBlockText/updateLine; see docs/tasks.md
      screens/
        task_file_screen.dart           — per-file task view; recursive tree renderer (depth * 24px indent); collapse/expand per block; inline task/note editing; ⊕ per-task subtask add; ··· per-task more-actions sheet (Add note / Add sibling / Delete); AppBar rename via showInputDialog; [[wikilinks]] via WikilinkText; see docs/tasks.md

    anki/
      models/
        anki_card.dart                  — AnkiCard {ankiId?, filePath, noteType, deck, tags, updatedAt, front, back, text, extraSections} + copyWith(); AnkiNoteType enum (basic, cloze)
      services/
        anki_connect_service.dart       — AnkiConnect HTTP client; configurable URL (SharedPreferences key: 'anki_connect_url', default localhost:8765); actions: testConnection/deckNames/addNote/updateNote/changeDeck/notesInfo/findNotes; all-static; all-catch-null; see docs/anki.md
        anki_storage_service.dart       — Anki card .md I/O in Interesting/Anki/; H1-based section parser; loadCards/saveCard/createNewCard/updateAnkiId/trashCard/createFromAnki; section-aware patch; .trash/ support; see docs/anki.md
        anki_sync_service.dart          — bidirectional sync orchestrator; AnkiSyncResult {createdInAnki, updatedInAnki, createdMarkdown, updatedMarkdown, trashed, skipped, error?}; last-modified-wins 5s tolerance; batch-50 notesInfo; see docs/anki.md
      screens/
        anki_screen.dart                — card browser; AppBar Sync → AnkiSyncService.sync() → SnackBar; FAB → AnkiCardEditorScreen; see docs/anki.md
        anki_card_editor_screen.dart    — Basic/Cloze editor; deck Autocomplete from deckNames(); discard guard (PopScope); Save → AnkiStorageService; see docs/anki.md

    settings/
      screens/
        settings_screen.dart            — Letterboxd RSS URL + Sync Now; AnkiConnect URL + Test Connection; all in SharedPreferences; self-contained

    templates/
      screens/
        templates_screen.dart           — list templates in Interesting/Templates/; create (FAB), edit (tap), delete; self-contained
        template_editor_screen.dart     — full-screen raw Markdown editor for a single template file; Save/discard-guard

  screens/
    home_screen.dart                    — orchestrator; stays at lib/screens/ (imports all feature screens); BottomNavigationBar shell: Entities + Boards + ToDos tabs (IndexedStack); owns board CRUD and task-file CRUD inline; AppBar has Anki + Settings + Templates icons

android/app/src/main/
  kotlin/com/nimee/people_tracker/
    MainActivity.kt                     — FlutterActivity subclass (boilerplate)
    QuickCaptureWidget.kt               — abstract AppWidgetProvider base; onUpdate() wires tap → QuickCaptureActivity via PendingIntent
    QuickCaptureWidget1x1.kt            — 1×1 concrete subclass (40×40dp); "+" centered
    QuickCaptureWidget2x1.kt            — 2×1 concrete subclass (110×40dp); "+" + prompt text
    QuickCaptureWidget2x2.kt            — 2×2 concrete subclass (110×110dp); label + prompt, centred
    QuickCaptureActivity.kt             — dialog-style Activity; reads vault path from FlutterSharedPreferences; slugifies title → alias; loads default.md template body; builds Markdown; writes entity .md file; shows Toast; no app launch
  res/
    xml/                                — quick_capture_widget_{1x1,2x1,2x2}.xml — AppWidget provider metadata (minWidth, minHeight, initialLayout)
    layout/                             — quick_capture_widget_{1x1,2x1,2x2}.xml — widget face layouts; quick_capture_activity.xml — title/note input form
    values/strings.xml                  — widget/activity string resources
    values/styles.xml                   — QuickCaptureTheme (Theme.Material.Light.Dialog.MinWidth, no title bar)
```

## Vault folder layout

```
<vault>/
  Interesting/
    Entities/        ← one .md file per entity
    Boards/          ← one .md file per board
    Templates/       ← one .md file per template; seeded on first launch; user-editable
    Anki/            ← one .md file per Anki card (Basic or Cloze)
      .trash/        ← soft-deleted cards; never auto-purged
    Tasks/           ← one .md file per task topic; pure Markdown, no frontmatter
```

All other files in the vault are ignored.

## Data

### Entity file: `<EntityName>.md`

```markdown
---
alias: david-deutsch
category: People
score: 10.0
tags:
  - epistemology
  - physics
created_at: 2026-05-07T12:00:00.000Z
updated_at: 2026-05-07T12:00:00.000Z
---
# David Deutsch

## Why Interesting

- Developed constructor theory and extended Popperian epistemology.

## Related

- [[Karl Popper]]
- [[Alan Turing]]

## Sources

- https://en.wikipedia.org/wiki/David_Deutsch
```

The parser discovers sections **dynamically** — `## Why Interesting`, `## Related`, and `## Sources` are semantic names the app owns, but any other `##` section the user adds (e.g. `## Background`, `## Thoughts`) is preserved verbatim through every save. The app only patches sections it owns; everything else is left untouched.

### Movie entity file: `<FilmTitle>.md`

Movie entities are written by `LetterboxdService` and behave like all other entities (searchable, linkable, board-compatible). They use the `Movies` category and carry additional frontmatter fields:

```markdown
---
alias: interstellar
category: Movies
score: 10.0
watched_date: 2014-11-05
letterboxd_url: https://letterboxd.com/user/film/interstellar/
tmdb_id: 157336
created_at: 2026-05-09T...Z
updated_at: 2026-05-09T...Z
---
# Interstellar

## Thoughts

An extraordinary vision of time and gravity.

## Related

- [[Christopher Nolan]]

## Sources

- https://letterboxd.com/user/film/interstellar/
```

`## Thoughts` is **not** in `_semanticSections` — it is user territory. The importer writes initial review content there; the app preserves it verbatim on every subsequent save. The three movie-specific frontmatter fields (`watched_date`, `letterboxd_url`, `tmdb_id`) are optional on all entities and are parsed by `_parseEntityFile` and written by `_buildFrontmatter` when non-null.

### Board file: `<BoardName>.md`

```markdown
# Flat Hierarchy Solution

- [[David Deutsch]]
- [[Browser]]
- [[Untidiness]]
```

### Template file: `<TemplateName>.md`

Templates live in `Interesting/Templates/`. They are identified by `template: true` in their frontmatter. The `{{title}}` placeholder is replaced with the entity name on creation.

```markdown
---
category: Default
template: true
---
# {{title}}

## Why Interesting

## Related

## Sources
```

Five defaults are seeded on first launch: `default.md` (Default), `person.md` (People), `product.md` (Products), `idea.md` (Ideas), `movie.md` (Movies). Users can edit, delete, or create new templates from within the app. Template-to-category mapping: `slugify(categoryName).md` — e.g. category "People" → `people.md`. The widget always uses `default.md`. The movie template uses `## Thoughts` / `## Related` / `## Sources` (no `## Why Interesting`).

### Default category

Widget-created entities always use `category: Default`. This is a normal category — it appears in the category filter and entity list alongside any other category. It is not a temporary inbox; entities in Default are full first-class entities.

### Field rules

- `alias` — immutable slug (maps to `Entity.id`); generated from name at creation; never regenerated on rename
- `category` — display string in frontmatter (e.g. "People"); `entity.categoryId = slugify(category)`
- `score` — omitted if null; float 0.0–10.0 to one decimal
- `watched_date` — optional; "yyyy-MM-dd" string; written only when non-null (movie entities)
- `letterboxd_url` — optional; Letterboxd log URL; written only when non-null
- `tmdb_id` — optional; TMDB integer as string; primary dedup key for Letterboxd import
- `created_at` / `updated_at` — ISO 8601 UTC strings in frontmatter; stored as Unix ms in memory
- `tags` — list in frontmatter; union recomputed on every save (for autocomplete)
- Entity wikilinks — `[[Name]]` patterns found anywhere in the Markdown body (all `##` sections + preamble) are extracted on load and resolved to `EntityLink` objects; `## Related` is the curated subset written back on save; inline wikilinks in other sections create the same graph edges but are preserved verbatim in their prose section
- Board membership — derived at load time from board `.md` wikilinks; NOT stored in entity frontmatter
- Filename — `<entity.name>.md` (sanitized); can change on rename; `alias` is the stable identity
- Categories — derived from distinct `category` values across entity frontmatters; no separate file
- Unknown sections — any `##` section not in the semantic registry is preserved verbatim on every save

### Migration

- On first load with an empty vault: if `entities.json` exists in app documents dir, auto-migrates all data to Markdown files and renames the JSON file to `entities.json.migrated`

## Storage pattern

`AppData` is a Dart record (defined in `markdown_storage_service.dart`):

```dart
typedef AppData = ({
  List<Entity> entities,
  List<Category> categories,
  List<String> tags,
  List<EntityLink> entityLinks,
  List<Board> boards,
  List<BoardEntity> boardEntities,
});
```

Load once at app start. Every mutation → fire-and-forget `saveData(...)`. `saveData` snapshots all lists before the async gap to avoid races. All I/O is try/catch — never crashes the app.

### Section type registry

Defined as a top-level const in `markdown_storage_service.dart`:

```dart
const Map<String, SectionType> _semanticSections = {
  'Why Interesting': SectionType.list,
  'Related':         SectionType.wikilinks,
  'Sources':         SectionType.list,
};
```

Only these sections are rewritten by the app on save. Every other `##` section is user territory and is preserved character-for-character.

**`loadData()` flow:**
1. Get vault path from `VaultService` (SharedPreferences)
2. Run JSON migration if vault is empty and `entities.json` exists
3. Scan `Interesting/Entities/*.md` → parse YAML frontmatter + body → `Entity` objects
   - Body parsed via `_parseSections()` → dynamic `Map<String, String>` of all sections
   - `rawSections` stored on `Entity` for use during subsequent save
4. Derive `Category` list from distinct `category` frontmatter values
5. Extract all `[[wikilinks]]` from entire Markdown body (full-body scan, not just `## Related`) → resolve to `EntityLink` list (dedup via `linkExists`)
6. Scan `Interesting/Boards/*.md` → parse H1/filename + wikilinks → `Board` + `BoardEntity` lists
7. Return `AppData`

**`saveData()` flow:**
1. Get vault path; snapshot all lists
2. For each entity:
   - If a file already exists for this alias: **patch** it — update frontmatter + semantic sections in-place, preserve unknown sections
   - If no file exists (new entity): load category template from `Interesting/Templates/`, instantiate it (`{{title}}` → name), then patch; fall back to minimal hardcoded structure if no template
   - Detect renames (alias lookup) → delete old file
3. Cleanup: delete entity files whose `alias` is no longer in the entities list
4. For each board: write `<name>.md` with H1 + member wikilinks
5. Cleanup: delete board files not written in this save

### Static helpers on MarkdownStorageService

- `linkExists(a, b, links)` — checks both directions
- `getRelatedEntities(entityId, links, entities)` — returns all connected entities
- `generateLinkId(from, to)` — returns `"${from}--${to}"`
- `boardEntryExists(boardId, entityId, entries)` — dedup check before inserting
- `generateEntityId(name, existing)` — slug + collision suffix
- `generateCategoryId(name, existing)` — same
- `generateBoardId(name, existing)` — same
- `sortEntities(entities, sortOrder)` — returns sorted copy; orders: `latest`, `oldest`, `high_score`, `low_score`, `alpha` (A→Z, case-insensitive), `alpha_rev` (Z→A); nulls sorted as worst for score; unknown order falls back to `latest`

All three ID generators delegate to `_generateId(name, existing, fallback)`.

## Android home-screen widget

Three widget sizes appear separately in the Android widget picker. All three open `QuickCaptureActivity`, which is a dialog-style Activity (no navigation stack).

**Widget capture flow:**
1. User taps widget → `QuickCaptureActivity` opens as a floating dialog; keyboard shows immediately on title field
2. User types title (required) + optional quick note → taps Save
3. Activity reads vault path from `FlutterSharedPreferences` (key: `flutter.vault_path`)
4. Slugifies title → `alias`; checks for filename collisions (`-2`, `-3` suffix)
5. Loads `Interesting/Templates/default.md` body (strips frontmatter); falls back to hardcoded structure if missing
6. Replaces `{{title}}`; inserts note as `- {note}` under `## Why Interesting` if provided
7. Builds frontmatter from scratch: `alias`, `category: Default`, `created_at`, `updated_at`
8. Writes `{title}.md` (sanitized) to `Interesting/Entities/`; shows Toast; closes
9. App picks up the new file naturally on next `loadData()`

**SharedPreferences bridge:** Flutter's `shared_preferences` plugin stores data in Android's `FlutterSharedPreferences` file with a `flutter.` key prefix. The widget reads `flutter.vault_path` directly — no Flutter runtime needed.

**Widget sizes:**

| Class | Size | minWidth × minHeight | Visual |
|-------|------|----------------------|--------|
| `QuickCaptureWidget1x1` | 1×1 | 40dp × 40dp | centered `+` |
| `QuickCaptureWidget2x1` | 2×1 | 110dp × 40dp | `+` + "Tap to capture…" |
| `QuickCaptureWidget2x2` | 2×2 | 110dp × 110dp | "Interesting" label + prompt |

`QuickCaptureWidget` (abstract base) owns all `onUpdate` logic. Each concrete subclass declares only `layoutResId`.

## Grokipedia integration

Optional, non-destructive external knowledge layer. No vault data is written or modified at any point.

**Flow:**
1. `EntityScreen.initState()` fires `_fetchGrokipedia()` as a non-blocking async call
2. `GrokipediaService.findArticle(entity.name)` — `GET https://grokipedia.com/api/full-text-search?query={name}&limit=5` → first result's `{title, slug, snippet?}` or `null`
3. Display mode "External Knowledge" section shows: matched article title + "Open Article" button + "Summary" toggle
4. "Open Article" → `url_launcher` opens `https://grokipedia.com/page/{slug}` in external browser (no native Grokipedia app exists)
5. "Summary" expand → shows `snippet` from search result if present; otherwise fetches `GET https://grokipedia.com/api/page?slug={slug}&includeContent=true` → `data['page']['content']` truncated to 600 chars
6. Any failure (network, timeout, 4xx, malformed JSON) → `GrokipediaService` returns `null` → shows "No Grokipedia article found." — no crash, no blocked UI

**Boundaries:** no caching, no vault writes, no background polling, no article-to-notes injection.

## Tasks subsystem

Hierarchical Markdown-native task layer. Full implementation details: **[docs/tasks.md](docs/tasks.md)**.

Files in `Interesting/Tasks/` — one per topic, no YAML frontmatter. Task syntax: `- [ ]` / `- [x]`. Indented `- [ ]` are subtasks; indented prose after a task are inline notes. Files are parsed into a `TaskNode` tree in memory (`TaskBlock` with `children[]` and `noteLineIndices[]`); Markdown files remain canonical — the tree is a parsed projection only.

**UI:** ToDos tab lists task files as cards with `LinearProgressIndicator`. Tap → `TaskFileScreen` (hierarchical tree view, collapsible, inline editing, ⊕ per-task subtask add, ··· per-task more-actions sheet for note/sibling/delete). Long-press → bottom sheet (Rename / Delete). AppBar `+` → create dialog.

**Boundaries:** no task IDs; no due dates, reminders, priorities, or sync; wikilinks preserved but not wired into `EntityLink` graph.

## Anki integration

Bidirectional sync between `Interesting/Anki/*.md` and Anki notes via AnkiConnect. Manual sync only (Sync button in AnkiScreen). Supports Basic and Cloze note types. `anki_id` in frontmatter is the stable identity anchor. Review metadata (intervals, ease, due dates) is never written to Markdown — only semantic content (front/back/text, tags, deck) syncs.

**Requires one-time setup:** Desktop Anki + AnkiConnect add-on (code `2055492159`) + bind address set to `0.0.0.0` in AnkiConnect config. Phone and desktop must be on the same WiFi. Configure the desktop's LAN IP in Settings → AnkiConnect URL.

Full details: **[docs/anki.md](docs/anki.md)** — setup walkthrough, file format, services, sync algorithm, conflict resolution.

## Navigation and state-passing patterns

**HomeScreen** is a `BottomNavigationBar` shell with three tabs via `IndexedStack`:
- Tab 0 (Entities): entity list, category filter, add bar, search, sort
- Tab 1 (Boards): board list with full CRUD — inline, no separate screen push
- Tab 2 (ToDos): task file list with progress bars; full CRUD inline; tap → `TaskFileScreen`

HomeScreen navigates via push to:
- `EntityScreen` — from entity list tap; passes full six-list set by reference
- `BoardDetailScreen` — from board tap in Boards tab; self-contained
- `TaskFileScreen` — from task file tap in ToDos tab; self-contained (no entity lists needed)
- `AnkiScreen` — from AppBar Anki icon; self-contained
- `TemplatesScreen` — from AppBar templates icon; self-contained (reads/writes template files directly, no MarkdownStorageService)
- `SettingsScreen` — from AppBar settings icon; self-contained; `_reloadData()` called on pop to pick up any newly imported entities

**Pass-by-reference (EntityScreen):** `HomeScreen` passes its own live lists (`_entities`, `_entityLinks`, etc.) directly to `EntityScreen`. `EntityScreen` mutates them in place (`allEntities[idx] = _entity`) on save, so the home list is already updated when it pops. `HomeScreen` still calls `_reloadData()` on pop for safety.

**Self-contained (BoardDetailScreen, TemplatesScreen):** Each screen owns its data — loads directly in `initState` and reloads after any child navigation returns.

`EntityScreen` can be pushed from either context (HomeScreen or BoardDetailScreen); it always receives the full six-list set by reference.

## Entity display/edit mode

`EntityScreen` has two modes controlled by `_isEditMode`:

**Display mode** (default): read-only ListView. Name is a large bold heading. Category, tags, score, boards are shown as text/chips with no controls. Notes are paragraphs. Sources are blue underlined text. Related entities are tappable (navigate to their own EntityScreen) but have no unlink button. AppBar shows an Edit icon.

**Edit mode** (after tapping Edit): all editable widgets appear. Name becomes a text field at the top of the body. AppBar shows Save and Cancel.
- **Save**: commits name from `_nameController`, stamps `updatedAt`, writes to disk via `_save()`, exits edit mode.
- **Cancel**: restores `_entity` from `_editSnapshot` (a `copyWith()` snapshot taken on entering edit mode), restores `allEntities[idx]`, exits edit mode without saving.

**Deferred vs immediate save in edit mode:**
- **Deferred** (only persisted on explicit Save): name, category, tags, score, notes, links
- **Immediate** (saved right away, not undone by Cancel): board memberships and entity links — they mutate `widget.allBoardEntities` / `widget.allEntityLinks` (join tables), which the entity snapshot does not cover

## Running

```
flutter pub get
flutter run -d android
```

First launch shows a vault folder picker. Select any folder (e.g. your Obsidian vault root). The app creates `Interesting/Entities/`, `Interesting/Boards/`, `Interesting/Templates/`, `Interesting/Anki/`, and `Interesting/Tasks/` inside it, and seeds five default templates (including `movie.md` for the Movies category).

**Android:** Requires "All Files Access" (`MANAGE_EXTERNAL_STORAGE`) on Android 11+. On first launch a permission gate screen appears — tap "Open Settings", enable All Files Access for this app, then return. The gate re-checks on every resume; once granted, vault reads and writes work on external storage. The widget also requires this permission (same app context).

## Dependencies

- `path_provider: ^2.1.5` — app documents directory (JSON migration check)
- `file_picker: ^8.1.2` — vault folder picker (first launch)
- `yaml: ^3.1.2` — YAML frontmatter parsing
- `shared_preferences: ^2.5.0` — persist vault folder path and Letterboxd RSS URL across app restarts
- `path: ^1.9.0` — cross-platform path manipulation
- `permission_handler: ^11.3.0` — Android MANAGE_EXTERNAL_STORAGE gate (All Files Access)
- `http: ^1.2.0` — RSS feed fetching in LetterboxdService; AnkiConnect HTTP calls in AnkiConnectService; Grokipedia HTTP calls in GrokipediaService (all user-triggered or non-blocking; no background polling)
- `xml: ^6.5.0` — RSS/XML parsing in LetterboxdService
- `dart:io` + `dart:convert` — file read/write and JSON (migration only)
- `url_launcher: ^6.2.0` — opens Grokipedia article URLs in external browser (Grokipedia integration)
