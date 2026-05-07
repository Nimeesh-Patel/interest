# Entity Tracker

Single-user Flutter app for tracking entities (people, ideas, solutions, products, or any user-defined category) locally. No auth, no cloud, no backend.

## What it does

- Track entities across user-defined categories
- Each entity has: notes ("Why it matters"), links ("Sources"), tags, score, and related entities
- Entity detail has a display mode (read-only) and an edit mode (explicit Save/Cancel)
- Entities can be linked to each other — forming a navigable graph
- Entities can be grouped into boards (independent of categories; many-to-many)
- Entities can be added to boards from inside the board detail screen
- Board members can be sorted by date, score, name, or category
- Score (0–10, step 0.1) is optional per entity
- Tags are reusable and created inline with autocomplete
- Categories are created, renamed, and deleted from the home screen
- Search by name; filter by category; sort by date or score
- Export all data as JSON, Markdown, or TXT
- Import JSON data — merge with existing or replace all
- All data persists locally in a single JSON file

## Architecture

No state management libraries. Pure `setState`. No repository pattern.

```
lib/
  main.dart                           — entry point, MaterialApp
  models/entity.dart                  — Entity {id, name, categoryId, notes, links, tags, score, createdAt, updatedAt} + copyWith()
  models/category.dart                — Category {id, name}
  models/entity_link.dart             — EntityLink {id, from, to, type}
  models/board.dart                   — Board {id, name}
  models/board_entity.dart            — BoardEntity {boardId, entityId} (join table)
  services/storage_service.dart       — load/save entities.json; ID generators; static helpers
  screens/home_screen.dart            — BottomNavigationBar shell: Entities tab + Boards tab (IndexedStack); owns full board CRUD inline
  screens/entity_screen.dart          — display mode (read-only) / edit mode (deferred save with Cancel); name, category, tags, score, boards, notes, links, related
  screens/board_detail_screen.dart    — entities in a board; 6 sort options; FAB to add entities; self-contained
  screens/export_screen.dart          — export JSON/MD/TXT + import JSON (merge or replace); self-contained
  screens/boards_screen.dart          — DEAD CODE: standalone boards list, superseded by Boards tab in home_screen.dart; kept for reference only
```

## Data

Single file: `entities.json` in `getApplicationDocumentsDirectory()`.

```json
{
  "entities": [
    {
      "id": "john-doe",
      "name": "John Doe",
      "category_id": "people",
      "notes": ["string"],
      "links": ["url string"],
      "tags": ["active"],
      "score": 7.5,
      "created_at": 1234567890000,
      "updated_at": 1234567890000
    }
  ],
  "categories": [
    { "id": "people", "name": "People" }
  ],
  "tags": ["active", "exploring"],
  "entity_links": [
    {
      "id": "john-doe--jane-doe",
      "from": "john-doe",
      "to": "jane-doe",
      "type": "related"
    }
  ],
  "boards": [
    { "id": "favourites", "name": "Favourites" }
  ],
  "board_entities": [
    { "board_id": "favourites", "entity_id": "john-doe" }
  ]
}
```

### Field rules

- `id`, `category.id`, `board.id` — immutable slugs generated at creation (collision-safe via `_generateId`). Never regenerated on rename.
- `score` — `null` if not set; float 0.0–10.0 stored to one decimal.
- `created_at` / `updated_at` — Unix ms. `updated_at` is stamped on every entity save inside `_save()` in `entity_screen.dart`.
- `tags` (top-level) — union of all entity tags, recomputed on every save. Used only for autocomplete; not the source of truth.
- `entity_links` — bidirectional in the UI (queried in both directions). `id` is `"${from}--${to}"`. Duplicate prevention enforced before creation.
- `board_entities` — join table; dedup enforced before insertion via `boardEntryExists`. Entries are removed when the entity or board is deleted.

## Storage pattern

`AppData` is a Dart record:

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

### Static helpers on StorageService

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
- `ExportScreen` — from AppBar share icon; self-contained

**Pass-by-reference (EntityScreen):** `HomeScreen` passes its own live lists (`_entities`, `_entityLinks`, etc.) directly to `EntityScreen`. `EntityScreen` mutates them in place (`allEntities[idx] = _entity`) on save, so the home list is already updated when it pops. `HomeScreen` still calls `_reloadData()` on pop for safety.

**Self-contained (BoardDetailScreen, ExportScreen):** Each screen owns its data — calls `loadData()` in `initState` and `_reloadData()` after any child navigation returns. This avoids threading the full state graph through sub-hierarchies.

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

### Migration

If `entities.json` is absent but `people.json` (old format) exists, `loadData()` auto-migrates:
- Creates a "People" category
- Converts each person to an entity (`categoryId = "people"`, old `status` field → tag)
- Writes `entities.json` and leaves `people.json` untouched
- Populates `boards` and `boardEntities` as empty lists

## Running

```
flutter pub get
flutter run          # requires Windows Developer Mode if running on Windows desktop
flutter run -d android
```

To inspect saved data on Android:
```
adb shell run-as com.nimee.people_tracker cat files/entities.json
```

## Dependencies

- `path_provider: ^2.1.5` — app documents directory (export/import file paths)
- `file_picker: ^8.1.2` — native file picker for JSON import
- `dart:io` + `dart:convert` — file read/write and JSON
