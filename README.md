# Entity Tracker

Single-user Flutter app for tracking entities (people, ideas, solutions, products, or any user-defined category) locally. No auth, no cloud, no backend.

## What it does

- Track entities across user-defined categories
- Each entity has: notes ("Why it matters"), links ("Sources"), tags, score, and related entities
- Entities can be linked to each other — forming a navigable graph
- Entities can be grouped into boards (independent of categories; many-to-many)
- Score (0–10, step 0.1) is optional per entity
- Tags are reusable and created inline with autocomplete
- Categories are created, renamed, and deleted from the home screen
- Search by name; filter by category; sort by date or score
- Export all data as JSON, Markdown, or TXT
- All data persists locally in a single JSON file

## Architecture

No state management libraries. Pure `setState`. No repository pattern.

```
lib/
  main.dart                           — entry point, MaterialApp
  models/entity.dart                  — Entity {id, name, categoryId, notes, links, tags, score, createdAt, updatedAt}
  models/category.dart                — Category {id, name}
  models/entity_link.dart             — EntityLink {id, from, to, type}
  models/board.dart                   — Board {id, name}
  models/board_entity.dart            — BoardEntity {boardId, entityId} (join table)
  services/storage_service.dart       — load/save entities.json; ID generators; static helpers
  screens/home_screen.dart            — category filter, sort bar, inline add, entity list, nav to Boards/Export
  screens/entity_screen.dart          — detail: name, category, tags, score, boards, notes, links, related
  screens/boards_screen.dart          — list/create/rename/delete boards (self-contained)
  screens/board_detail_screen.dart    — entities in a board, tap → entity screen (self-contained)
  screens/export_screen.dart          — export JSON/MD/TXT to documents directory (self-contained)
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

- `id`, `category.id`, `board.id` — immutable slugs generated at creation (collision-safe via `_generateId`).
- `score` — `null` if not set; float 0.0–10.0 stored to one decimal.
- `created_at` / `updated_at` — Unix ms. `updated_at` is stamped on every entity save from `entity_screen.dart`.
- `tags` (top-level) — union of all entity tags, recomputed on every save. Used only for autocomplete; not the source of truth.
- `entity_links` — bidirectional in the UI (queried in both directions). `id` is `"${from}--${to}"`. Duplicate prevention enforced before creation.
- `board_entities` — join table; no deduplication needed in practice (enforced before insertion via `boardEntryExists`). Entries are removed when the entity or board is deleted.

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

Two patterns coexist:

**Pass-by-reference (EntityScreen):** `HomeScreen` passes its own live lists (`_entities`, `_entityLinks`, etc.) directly to `EntityScreen`. `EntityScreen` mutates them in place (`allEntities[idx] = _entity`), so the home list is already updated when it pops. `HomeScreen` still calls `_reloadData()` on pop for safety.

**Self-contained (BoardsScreen, BoardDetailScreen, ExportScreen):** Each screen owns its data — it calls `loadData()` in `initState` and `_reloadData()` after any child navigation. This avoids threading the full state graph through the boards navigation hierarchy.

`EntityScreen` can be pushed from either context; it always receives the full six-list set by reference.

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

- `path_provider: ^2.1.5` — only third-party dep
- `dart:io` + `dart:convert` — file read/write and JSON
