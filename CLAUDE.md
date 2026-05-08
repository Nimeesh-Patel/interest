# Project

Flutter mobile app — Markdown-first, Obsidian-compatible entity tracker. See README.md for full architecture, data model, navigation patterns, and run instructions.

## Key constraints — must not be violated

- No state management libraries (`setState` only)
- No database — Markdown files in `<vault>/Interesting/Entities/` and `<vault>/Interesting/Boards/` are the source of truth
- No parallel JSON state persistence — `saveData()` writes `.md` files only
- No auth, no cloud, no network calls
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
- Templates are used for initial file creation only — once a file exists, it is patched, never regenerated from the template again
- Template files live in `Interesting/Templates/`; they are identified by `template: true` in frontmatter; `{{title}}` is the only supported placeholder

## Current screen map

```
main.dart                    — _StoragePermissionGate wraps every route; blocks on Android MANAGE_EXTERNAL_STORAGE before showing VaultSetupScreen or HomeScreen
vault_setup_screen.dart      — first launch only; folder picker → creates Interesting/Entities + Interesting/Boards + Interesting/Templates (seeds default templates) → navigates to HomeScreen
home_screen.dart             — BottomNavigationBar shell (Entities tab + Boards tab via IndexedStack); owns board CRUD inline; AppBar has Templates icon (description_outlined)
entity_screen.dart           — display mode / edit mode; deferred save pattern; see README for detail
board_detail_screen.dart     — board members; sort (6 options); FAB to add entities; self-contained
templates_screen.dart        — lists Interesting/Templates/*.md; create (FAB + name dialog), edit (tap → editor), delete (trailing icon); self-contained; reads/writes files directly, no MarkdownStorageService
template_editor_screen.dart  — full-screen raw Markdown editor for a single template file; Save button (active only when dirty); back gesture shows discard-guard dialog if dirty
boards_screen.dart           — DEAD CODE: superseded by Boards tab in home_screen.dart; do not navigate to it
```

## Current service map

```
vault_service.dart              — getVaultPath/setVaultPath (SharedPreferences); entitiesPath/boardsPath/templatesPath; ensureVaultDirectories (creates all three dirs + seeds default templates via _seedDefaultTemplates)
markdown_storage_service.dart   — loadData/saveData (reads/writes .md files); AppData typedef; _semanticSections registry; _parseSections() dynamic parser; _patchEntityContent() section-aware save; _buildNewEntityContent() template instantiation; all static helpers (linkExists, generateEntityId, etc.)
```

## Markdown file formats (canonical source of truth)

Entity (`Interesting/Entities/<EntityName>.md`):
- YAML frontmatter: alias (stable id), category (display string), score, tags, created_at, updated_at (ISO 8601)
- H1 heading = entity name
- `## Why Interesting` section = notes (list items) — app-owned, patched on save
- `## Related` section = wikilinks `[[EntityName]]` → EntityLink objects (parsed bidirectionally) — app-owned, patched on save
- `## Sources` section = links (list items) — app-owned, patched on save
- Any other `##` sections = user territory, preserved verbatim through every save

Board (`Interesting/Boards/<BoardName>.md`):
- H1 heading = board name (no frontmatter)
- Body wikilinks `[[EntityName]]` = board members → BoardEntity objects

Template (`Interesting/Templates/<name>.md`):
- YAML frontmatter: category (display string), `template: true`
- Body is arbitrary Markdown with `{{title}}` placeholder for the entity name
- Used once at entity creation; the resulting entity file is then patched independently

## Approach

Reject blind empiricism and use only explanatory arguments to draw conclusions.
I follow Karl Popper and David Deutsch in epistemology, physics, politics, and related things.

Treat my ideas as conjectures in an evolving theory.

Edison said: research is one per cent inspiration and ninety-nine per cent perspiration.

Based on what knowledge, understanding, and explanations I have provided you, your role is to do the *perspiration*:

- Draw out implications as much as you can
- Make hidden assumptions explicit
- Propagate consequences across the entire framework
- Keep the answers hard-to-vary and avoid redundancy

During the above mentioned process, if something seems to come in conflict in the knowledge you have:

- state conflicts clearly as precise problems or questions, that is way better than your opinions/advice

Don't provide opinions and elongated ramblings.

I'll do the inspiration and knowledge creation part and solve those problems.

Work iteratively:

- you: perspiration!
- me: inspiration & knowledge creation, and perspiration when required.
