# Entity Tracker

Single-user Flutter app for tracking entities (people, ideas, solutions, products, or any user-defined category). Data lives as plain Markdown files in a user-chosen vault folder — readable and editable by Obsidian or any text editor. No auth, no cloud, no backend.

## What it does

- Track entities across user-defined categories
- Each entity has: notes ("Why it matters"), links ("Sources"), tags, score, and related entities
- Entity detail has a display mode (read-only) and an edit mode (explicit Save/Cancel)
- Entities are linked to each other via Obsidian-style wikilinks — forming a navigable graph
- Entities can be grouped into boards (independent of categories; many-to-many)
- Entities can be added to boards from inside the board detail screen
- Board members can be sorted by date, score, name, or category
- Score (0–10, step 0.1) is optional per entity
- Tags are reusable and created inline with autocomplete
- Categories are created, renamed, and deleted from the home screen
- Search by name; filter by category; sort by date or score
- Templates management: create, edit, and delete entity templates from within the app (raw Markdown editor)
- On first launch: choose a vault folder (Obsidian vault or any folder)
- All data persists as `.md` files; fully readable in Obsidian

## Architecture

No state management libraries. Pure `setState`. No repository pattern.

```
lib/
  main.dart                           — async vault-path check at startup; _StoragePermissionGate (Android All Files Access, re-checks on resume); routes to VaultSetupScreen or HomeScreen
  models/entity.dart                  — Entity {id, name, categoryId, notes, links, tags, score, createdAt, updatedAt, rawSections} + copyWith()
  models/category.dart                — Category {id, name}
  models/entity_link.dart             — EntityLink {id, from, to, type}
  models/board.dart                   — Board {id, name}
  models/board_entity.dart            — BoardEntity {boardId, entityId} (join table; derived at load time from board .md files)
  services/vault_service.dart         — vault path persistence (SharedPreferences); entitiesPath/boardsPath/templatesPath helpers; ensureVaultDirectories (creates all three dirs + seeds default templates)
  services/markdown_storage_service.dart — canonical storage layer; loadData/saveData; dynamic section parser (_parseSections); section-aware patching (_patchEntityContent); template loading; AppData typedef; static ID/link helpers
  screens/vault_setup_screen.dart     — shown on first launch; folder picker → creates Interesting/Entities + Interesting/Boards + Interesting/Templates → saves path
  screens/home_screen.dart            — BottomNavigationBar shell: Entities tab + Boards tab (IndexedStack); owns full board CRUD inline; AppBar has Templates icon
  screens/entity_screen.dart          — display mode (read-only) / edit mode (deferred save with Cancel); name, category, tags, score, boards, notes, links, related
  screens/board_detail_screen.dart    — entities in a board; 6 sort options; FAB to add entities; self-contained
  screens/templates_screen.dart       — list of templates in Interesting/Templates/; create (FAB), edit (tap), delete; self-contained
  screens/template_editor_screen.dart — full-screen raw Markdown editor for a single template file; Save/discard-guard
  screens/boards_screen.dart          — DEAD CODE: standalone boards list, superseded by Boards tab in home_screen.dart; kept for reference only
```

## Vault folder layout

The app operates exclusively inside:

```
<vault>/
  Interesting/
    Entities/        ← one .md file per entity
    Boards/          ← one .md file per board
    Templates/       ← one .md file per template; seeded on first launch; user-editable
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

The parser discovers sections **dynamically** — `## Why Interesting`, `## Related`, and `## Sources` are semantic names the app owns, but any other `##` section the user adds (e.g. `## Background`) is preserved verbatim through every save. The app only patches sections it owns; everything else is left untouched.

### Board file: `<BoardName>.md`

```markdown
# Flat Hierarchy Solution

- [[David Deutsch]]
- [[Browser]]
- [[Untidiness]]
```

### Template file: `<TemplateName>.md`

Templates live in `Interesting/Templates/`. They are normal Markdown files identified by `template: true` in their frontmatter. The `{{title}}` placeholder is replaced with the entity name on creation.

```markdown
---
category: People
template: true
---
# {{title}}

## Why Interesting

## Related

## Sources
```

Four defaults are seeded on first launch: `default.md`, `person.md`, `product.md`, `idea.md`. Users can edit, delete, or create new templates from within the app. Template-to-category mapping: `slugify(categoryName).md` — e.g. category "People" → `people.md`.

### Field rules

- `alias` — immutable slug (maps to `Entity.id`); generated from name at creation; never regenerated on rename
- `category` — display string in frontmatter (e.g. "People"); `entity.categoryId = slugify(category)`
- `score` — omitted if null; float 0.0–10.0 to one decimal
- `created_at` / `updated_at` — ISO 8601 UTC strings in frontmatter; stored as Unix ms in memory
- `tags` — list in frontmatter; union recomputed on every save (for autocomplete)
- `## Related` wikilinks — canonical source for entity-to-entity links; bidirectional (both entity files list each other); deduplicated on load via `linkExists`
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
5. Resolve `## Related` wikilinks → `EntityLink` list (bidirectional dedup via `linkExists`)
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

All three ID generators delegate to `_generateId(name, existing, fallback)`.

## Navigation and state-passing patterns

**HomeScreen** is a `BottomNavigationBar` shell with two tabs via `IndexedStack`:
- Tab 0 (Entities): entity list, category filter, add bar, search, sort
- Tab 1 (Boards): board list with full CRUD — inline, no separate screen push

HomeScreen navigates via push to:
- `EntityScreen` — from entity list tap; passes full six-list set by reference
- `BoardDetailScreen` — from board tap in Boards tab; self-contained
- `TemplatesScreen` — from AppBar templates icon; self-contained (reads/writes template files directly, no MarkdownStorageService)

**Pass-by-reference (EntityScreen):** `HomeScreen` passes its own live lists (`_entities`, `_entityLinks`, etc.) directly to `EntityScreen`. `EntityScreen` mutates them in place (`allEntities[idx] = _entity`) on save, so the home list is already updated when it pops. `HomeScreen` still calls `_reloadData()` on pop for safety.

**Self-contained (BoardDetailScreen, TemplatesScreen):** Each screen owns its data — loads directly in `initState` and reloads after any child navigation returns.

`EntityScreen` can be pushed from either context (HomeScreen or BoardDetailScreen); it always receives the full six-list set by reference.

**BoardsScreen** is no longer used. Board CRUD logic lives inside `_HomeScreenState` (home_screen.dart).

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
flutter run          # requires Windows Developer Mode if running on Windows desktop
flutter run -d android
```

First launch shows a vault folder picker. Select any folder (e.g. your Obsidian vault root). The app creates `Interesting/Entities/`, `Interesting/Boards/`, and `Interesting/Templates/` inside it, and seeds four default templates.

**Android:** Requires "All Files Access" (`MANAGE_EXTERNAL_STORAGE`) on Android 11+. On first launch a permission gate screen appears — tap "Open Settings", enable All Files Access for this app, then return. The gate re-checks on every resume; once granted, vault reads and writes work on external storage.

## Dependencies

- `path_provider: ^2.1.5` — app documents directory (JSON migration check)
- `file_picker: ^8.1.2` — vault folder picker (first launch)
- `yaml: ^3.1.2` — YAML frontmatter parsing
- `shared_preferences: ^2.5.0` — persist vault folder path across app restarts
- `path: ^1.9.0` — cross-platform path manipulation
- `permission_handler: ^11.3.0` — Android MANAGE_EXTERNAL_STORAGE gate (All Files Access)
- `dart:io` + `dart:convert` — file read/write and JSON (migration only)
