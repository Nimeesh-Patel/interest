# Entity Tracker

A filesystem-native semantic knowledge layer: all data lives as plain Markdown files in a user-chosen vault folder. The app is a projection over that vault — it reads, patches, and navigates Markdown without owning it. Compatible with Obsidian; readable by any text editor. Single-user Android app. No database, no cloud, no auth.

## Vault layout

```
<vault>/
  Interesting/
    Entities/     — one .md file per entity
    Boards/       — one .md file per board (wikilink list of members)
    Templates/    — category templates; seeded on first launch; user-editable
    Anki/         — one .md file per Anki card
      .trash/     — soft-deleted cards
    Tasks/        — one .md file per task topic; pure Markdown, no frontmatter
    Books/        — one .md file per Readwise book (highlights from that book)
```

All subdirectories are created on first launch (`VaultService.ensureVaultDirectories`). All other files in the vault are ignored.

## Semantic storage model

### Identity

Every entity has an immutable `alias` in its YAML frontmatter — the entity's stable id, used in all EntityLinks and board memberships. Filenames change on rename; the alias never does. Without this invariant, every rename would silently orphan all wikilinks and board memberships pointing to the renamed entity.

### The patch-not-rebuild contract

When the app saves an entity, it **patches** the existing file — it does not rebuild it from scratch. Patching means:
- Frontmatter is rebuilt from current entity data
- App-owned semantic sections are rewritten from current entity data
- Every other `##` section the user wrote is preserved character-for-character

If the app rebuilt the whole file from entity data, it would silently erase any prose the user had written outside the app's semantic sections on every save. The patch contract makes the app a safe cohabitant of the user's Markdown.

New entities: a category template is instantiated once at creation (`{{title}}` → name), then patched on every subsequent save. Re-templating is never done — it would destroy user sections.

### Semantic sections

The app owns three sections, defined in `_semanticSections` in `markdown_storage_service.dart`:

```dart
const Map<String, SectionType> _semanticSections = {
  'Why Interesting': SectionType.list,
  'Related':         SectionType.wikilinks,
  'Sources':         SectionType.list,
};
```

Only these are rewritten on save. Any other `##` section is user territory.

Wikilinks (`[[EntityName]]`) are scanned from the **entire Markdown body** — not just `## Related`. A link in any prose section creates the same graph edge as one in `## Related`. `## Related` is the curated list written back on save; links in other sections are preserved verbatim and still wire the graph.

### AppData and save semantics

Six entity types load on startup (entities, categories, tags, entity links, boards, board entities) and stay in-memory. `saveData()` fires after every mutation. Core entity fields defer to the explicit Save button — required so Cancel can restore the pre-edit snapshot atomically. Join-table mutations (board memberships, entity links) save immediately because they mutate shared lists the snapshot does not cover.

File formats, frontmatter field reference, service methods, and EntityScreen interaction model: [docs/entities.md](docs/entities.md).

## Architecture

```
lib/
  main.dart                — permission gate + routing
  core/                    — vault path (SharedPreferences) + directory bootstrap
  shared/markdown/         — pure Markdown parsing (md_utils) + filesystem I/O (md_io)
  shared/widgets/          — 6 reusable UI primitives
  shared/constants/        — app-wide constants (app_spacing.dart)
  features/
    entities/              — core storage (MarkdownStorageService), Entity, EntityScreen
    boards/                — Board model, BoardDetailScreen (membership derived at load time)
    tasks/                 — TaskBlock tree, TaskStorageService (no frontmatter, hard-delete)
    anki/                  — AnkiCard, three services (connect/storage/sync), two screens
    books/                 — Book model, BookStorageService, HardcoverService/SyncService, HardcoverScreen
    readwise/              — ReadwiseBook/Highlight models, ReadwiseService (enriches Books/), ReadwiseScreen
    templates/, settings/  — self-contained, no MarkdownStorageService dependency
  screens/home_screen.dart — BottomNavigationBar shell (owns state for all three tabs)
```

## Subsystems

**Entities + graph.** Each entity is a node in a semantic graph. Categories are not stored separately — they are derived from distinct `category` frontmatter values at load time. Board membership lives in the board's `.md` file as a wikilink list, not in entity frontmatter. This localizes mutations: changing a board's membership requires rewriting only the board file, not every member entity. Full details: [docs/entities.md](docs/entities.md).

**Tasks.** Task files are ephemeral working lists, not knowledge nodes. They have no `alias` and cannot participate in the entity graph. Deletion is hard (no trash) because there is no identity to preserve. The in-memory `TaskBlock` tree is a parsed projection; Markdown files remain canonical. `parseNodes()` is pure and stateless — it must be called on freshly loaded lines, never cached across reloads. Full details: [docs/tasks.md](docs/tasks.md).

**Anki.** The one bidirectional integration. Markdown owns semantic content (front/back/text, tags, deck); Anki owns review scheduling (intervals, ease, due dates — never written to Markdown). `anki_id` is the immutable identity anchor, analogous to entity `alias`. Deletion is soft (`.trash/`) because a hard-deleted card re-synced would be recreated from Anki with a new `anki_id`, breaking the identity chain permanently. Full details: [docs/anki.md](docs/anki.md).

**Letterboxd.** Ingestion-only: RSS → Movie entities written directly to `Interesting/Entities/`, bypassing `saveData()`. The bypass is intentional — `saveData()` rebuilds semantic sections from the in-memory entity model, which doesn't include `## Thoughts` at import time; routing through `saveData()` would erase the imported review content immediately after writing it.

**Grokipedia.** Read-only projection: the app searches for an article matching the entity name and displays it inline. Nothing is written to the vault. All network calls are all-catch-null; any failure degrades gracefully to "No article found."

**Android widget.** A native Android Activity (no Flutter engine at runtime). It reads the vault path directly from `FlutterSharedPreferences` using the `flutter.vault_path` key — the prefix Flutter's shared_preferences plugin uses — because VaultService and all Flutter APIs are unavailable outside the Flutter engine. Always writes `category: Default`.

**Books (canonical semantic objects).** `Interesting/Books/` holds one `.md` file per book. Each file is a convergence point: Readwise enriches it with highlights, Hardcover enriches it with reading state and metadata, and the user enriches it with prose. No external system owns the file — they patch it. `BookStorageService` is the single I/O layer; `alias` provides stable identity. Full details: [docs/books.md](docs/books.md).

**Readwise.** Highlight ingestion: Readwise API → `Interesting/Books/` via `BookStorageService`. Appends `^rw{id}` highlight blocks to `## Highlights`; patches only Readwise-owned frontmatter fields (`readwise_id`, `num_highlights`, `last_highlight_at`). Re-importing appends only new highlights. Token stored in SharedPreferences (`readwise_access_token`). No auto-sync. Full details: [docs/readwise.md](docs/readwise.md).

**Hardcover.** Bidirectional sync: Hardcover GraphQL API ↔ `Interesting/Books/` via `BookStorageService`. Explicit sync only (no background). Pass 1 (Hardcover → Markdown): patches `hardcover_id`, `status`, `rating`, `started_at`, `finished_at`; creates new book files for unmatched entries. Pass 2 (Markdown → Hardcover): pushes local status/rating changes back via `update_user_book` mutation. Identity reconciliation links books arriving from both Readwise and Hardcover to the same file. Token stored in SharedPreferences (`hardcover_api_token`). Full details: [docs/books.md](docs/books.md).

**Obsidian launch ergonomics.** A single AppBar action (`Icons.sync` in `home_screen.dart`) that launches the Obsidian app via `launchUrl(Uri.parse('obsidian://'), mode: LaunchMode.externalApplication)`. Purpose: Obsidian Sync only activates when Obsidian is foregrounded; this eliminates the manual switch after editing. The app itself remains sync-agnostic — it fires the URI and returns. Snackbar on failure (app not installed). No sync logic, no background launch, no state monitoring.

## Running

```
flutter pub get
flutter run -d android
```

First launch shows a vault folder picker. Select any folder (e.g. your Obsidian vault root). The app creates all `Interesting/` subdirectories and seeds five default templates.

**Android:** Requires "All Files Access" (`MANAGE_EXTERNAL_STORAGE`) on Android 11+. A permission gate screen appears on first launch; the gate re-checks on every app resume.

## Dependencies

- `path_provider` — app documents dir (JSON migration check)
- `file_picker` — vault folder picker (first launch)
- `yaml` — YAML frontmatter parsing
- `shared_preferences` — vault path and settings persistence
- `path` — cross-platform path manipulation
- `permission_handler` — Android All Files Access gate
- `http` — Letterboxd RSS, AnkiConnect, Grokipedia, Readwise API (all user-triggered or non-blocking; no background polling)
- `xml` — RSS/XML parsing (Letterboxd)
- `url_launcher` — opens Grokipedia article URLs in external browser; launches Obsidian via `obsidian://` URI scheme
