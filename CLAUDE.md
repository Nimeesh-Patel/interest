# Project

Flutter mobile app — Markdown-first, Obsidian-compatible entity tracker. See README.md for full architecture, data model, navigation patterns, and run instructions.

## Key constraints — must not be violated

- No state management libraries (`setState` only)
- No database — Markdown files in `<vault>/Interesting/Entities/` and `<vault>/Interesting/Boards/` are the source of truth
- No parallel JSON state persistence — `saveData()` writes `.md` files only
- No auth, no cloud, no backend. Network access is limited to `LetterboxdService.fetchAndImport()` — one user-triggered HTTP GET to a Letterboxd RSS URL. No background polling, no auth, no other network calls.
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

## Current screen map

```
Flutter screens:
main.dart                    — _StoragePermissionGate wraps every route; blocks on Android MANAGE_EXTERNAL_STORAGE before showing VaultSetupScreen or HomeScreen
vault_setup_screen.dart      — first launch only; folder picker → creates Interesting/Entities + Interesting/Boards + Interesting/Templates (seeds default templates) → navigates to HomeScreen
home_screen.dart             — BottomNavigationBar shell (Entities tab + Boards tab via IndexedStack); owns board CRUD inline; AppBar has Settings icon (settings_outlined) + Templates icon (description_outlined); _openSettings() calls _reloadData() on pop; sort options: latest, oldest, high_score, low_score, alpha (A→Z), alpha_rev (Z→A)
settings_screen.dart         — Letterboxd RSS URL text field (SharedPreferences key: 'letterboxd_rss_url'); Sync Now button → LetterboxdService.fetchAndImport(); shows result ("N created, N updated, N skipped") or error inline; self-contained
entity_screen.dart           — display mode / edit mode; deferred save pattern; see README for detail
board_detail_screen.dart     — board members; sort (7 options: latest, oldest, high_score, low_score, alpha, alpha_rev, category); entity picker pre-sorted A→Z; FAB to add entities; self-contained
templates_screen.dart        — lists Interesting/Templates/*.md; create (FAB + name dialog), edit (tap → editor), delete (trailing icon); self-contained; reads/writes files directly, no MarkdownStorageService
template_editor_screen.dart  — full-screen raw Markdown editor for a single template file; Save button (active only when dirty); back gesture shows discard-guard dialog if dirty
boards_screen.dart           — DEAD CODE: superseded by Boards tab in home_screen.dart; do not navigate to it

Android native (no Flutter runtime required):
QuickCaptureWidget.kt        — abstract AppWidgetProvider base; onUpdate() sets PendingIntent on widget_root view → opens QuickCaptureActivity
QuickCaptureWidget1x1.kt     — 1×1 subclass; layoutResId = R.layout.quick_capture_widget_1x1
QuickCaptureWidget2x1.kt     — 2×1 subclass; layoutResId = R.layout.quick_capture_widget_2x1
QuickCaptureWidget2x2.kt     — 2×2 subclass; layoutResId = R.layout.quick_capture_widget_2x2
QuickCaptureActivity.kt      — dialog-style Activity (QuickCaptureTheme); title + note inputs; save() reads FlutterSharedPreferences → builds Markdown → writes file → Toast → finish()
```

## Current service map

```
Flutter services:
vault_service.dart              — getVaultPath/setVaultPath (SharedPreferences key: 'vault_path'); entitiesPath/boardsPath/templatesPath; ensureVaultDirectories (creates all three dirs + seeds 5 default templates: default, person, product, idea, movie)
markdown_storage_service.dart   — loadData/saveData (reads/writes .md files); AppData typedef; _semanticSections registry; _parseSections() dynamic parser; _patchEntityContent() section-aware save; _buildNewEntityContent() template instantiation; all static helpers (linkExists, generateEntityId, sortEntities, etc.); parses and writes watchedDate/letterboxdUrl/tmdbId in frontmatter; wikilink extraction uses full Markdown body scan (_extractWikilinks(body)), not just ## Related
letterboxd_service.dart         — getRssUrl/setRssUrl (SharedPreferences key: 'letterboxd_rss_url'); fetchAndImport(rssUrl) → ImportResult; _buildMovieIndex() dedup lookup (tmdbId → path, normalizedTitle → path, Movies only); _buildMovieMarkdown() creates new files; _updateMovieFile() patches existing (updates frontmatter, injects Thoughts only if currently empty); bypasses saveData(), writes .md directly

Android native (Kotlin, no service class — logic lives in QuickCaptureActivity.kt):
getVaultPath()           — reads FlutterSharedPreferences / flutter.vault_path
slugify(name)            — mirrors Dart _generateId: lowercase, spaces→hyphens, strip non-[a-z0-9-]
uniqueId(base, dir)      — checks file existence; appends -2, -3, etc.
loadTemplateBody(path)   — reads default.md; strips --- frontmatter block; returns body only
buildMarkdown(...)       — assembles frontmatter from scratch + template body + optional note injection
```

## Markdown file formats (canonical source of truth)

Entity (`Interesting/Entities/<EntityName>.md`):
- YAML frontmatter: alias (stable id), category (display string), score, tags, created_at, updated_at (ISO 8601); plus optional movie fields: watched_date, letterboxd_url, tmdb_id (omitted when null)
- H1 heading = entity name
- `## Why Interesting` section = notes (list items) — app-owned, patched on save
- `## Related` section = the curated wikilink list written back by saveData; on load, ALL `[[wikilinks]]` found anywhere in the body contribute to EntityLink objects (full-body scan via `_extractWikilinks(body)` unioned with `## Related`); dedup via `linkExists`; inline wikilinks in prose sections are preserved verbatim and also generate graph edges
- `## Sources` section = links (list items) — app-owned, patched on save
- `## Thoughts` section — user territory (not in _semanticSections); used by movie template and written by LetterboxdService; preserved verbatim on every app save
- Any other `##` sections = user territory, preserved verbatim through every save

Movie entity (`Interesting/Entities/<FilmTitle>.md`) — written by LetterboxdService, not saveData:
- Frontmatter includes watched_date, letterboxd_url, tmdb_id when available
- Sections: `## Thoughts` (review prose, user-owned), `## Related`, `## Sources`
- Deduplication: tmdb_id match first, then normalized title match within Movies category
- Update policy: frontmatter fields updated on re-sync; Thoughts injected only if currently empty (never overwrites user edits)

Board (`Interesting/Boards/<BoardName>.md`):
- H1 heading = board name (no frontmatter)
- Body wikilinks `[[EntityName]]` = board members → BoardEntity objects

Template (`Interesting/Templates/<name>.md`):
- YAML frontmatter: category (display string), `template: true`
- Body is arbitrary Markdown with `{{title}}` placeholder for the entity name
- Used once at entity creation; the resulting entity file is then patched independently

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