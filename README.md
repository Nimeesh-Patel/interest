# Entity Tracker

A filesystem-native semantic knowledge layer: all data lives as plain Markdown files in a user-chosen vault. The app is a projection over that vault — it reads, patches, and navigates Markdown without owning it. Compatible with Obsidian; readable by any text editor. Single-user Android app. No database, no cloud, no auth.

## Vault layout

```
<vault>/
  Interesting/
    Entities/   — one .md file per entity
    Lists/      — one .md file per list (flat item collection; items are arbitrary text/wikilinks)
    Templates/  — category templates; seeded on first launch; user-editable
    Anki/       — one .md file per Anki card
      .trash/   — soft-deleted cards
    Tasks/      — one .md file per task topic; pure Markdown, no frontmatter
    Books/      — one .md file per book
    Articles/   — one .md file per RSS-imported article
    System/     — vault-native configuration (integrations.md)
```

All subdirectories are created on first launch (`VaultService.ensureVaultDirectories`). All other files in the vault are ignored.

## Semantic storage model

**Identity.** Every entity has an immutable `alias` in its YAML frontmatter — the stable id used in all EntityLinks. Filenames change on rename; the alias never does.

**Patch-not-rebuild.** On save, the app patches the existing file: frontmatter and app-owned sections are rewritten from current data; every other `##` section the user wrote is preserved verbatim. Rebuilding from scratch would silently erase user prose on every save. New entities are instantiated from a category template once (at creation) and patched thereafter.

**Semantic sections.** The app owns three sections — `Why Interesting`, `Related`, `Sources` — defined in `_semanticSections` in `markdown_storage_service.dart`. Only these are rewritten on save; any other `##` section is user territory. Wikilinks are scanned from the entire Markdown body, not just `## Related` — a link anywhere creates the same graph edge.

**Save semantics.** Entities, categories, tags, and entity links load on startup and stay in-memory. Core entity fields defer to the explicit Save button so Cancel can restore the pre-edit snapshot atomically. EntityLink mutations save immediately because they mutate shared state the snapshot doesn't cover.

File formats, frontmatter fields, and EntityScreen interaction model: [docs/entities.md](docs/entities.md).

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
    lists/                 — ListModel, ListStorageService, ListDetailScreen
    tasks/                 — TaskBlock tree, TaskStorageService
    anki/                  — AnkiCard, three services (connect/storage/sync), two screens
    books/                 — Book model, BookStorageService, HardcoverService/SyncService, HardcoverScreen
    readwise/              — ReadwiseService, ReadwiseScreen (enriches Books/)
    rss/                   — RssFetchService, adapters (letterboxd/substack/generic),
                             ArticleStorageService, RssIngestionService, RssScreen
    readera/               — ReaderaParser (.bak ZIP+JSON), ReaderaIngestionService
    templates/, settings/  — self-contained, no MarkdownStorageService dependency
  screens/home_screen.dart — BottomNavigationBar shell (owns state for all four tabs)
```

## Subsystems

**Entities + graph.** Each entity is a node in a semantic graph. Categories are derived from distinct `category` frontmatter values at load time — not stored separately. List membership is inferred by wikilink scan, not a join table. Full details: [docs/entities.md](docs/entities.md).

**Lists.** Flat `- item` collections in `Interesting/Lists/`. Safe to rebuild on every save because list files have no user prose sections. Drag reorder mutates file order; file order is semantic order.

**Tasks.** Ephemeral working lists with no identity anchor — hard-delete, no graph participation. The `TaskBlock` tree is a parsed projection; files remain canonical. Completing a root block moves it to end-of-file. Full details: [docs/tasks.md](docs/tasks.md).

**Anki.** The one bidirectional integration. Markdown owns semantic content (front/back/text, tags, deck); Anki owns scheduling (intervals, ease, due dates — never written to Markdown). Deletion is soft (`.trash/`) because a hard-deleted card re-synced from Anki would receive a new `anki_id`, breaking the identity chain permanently. Full details: [docs/anki.md](docs/anki.md).

**Books.** Each file in `Interesting/Books/` is a convergence point: Readwise enriches it with highlights, Hardcover enriches it with reading state, the user enriches it with prose. No external system owns the file — they all patch it. `BookStorageService` is the single I/O layer; field ownership is strictly partitioned. Full details: [docs/books.md](docs/books.md).

**Readwise.** Ingestion-only: Readwise API → `Interesting/Books/` via `BookStorageService`. Appends `^rw{id}` highlight blocks; re-import appends only new highlights. Full details: [docs/readwise.md](docs/readwise.md).

**Hardcover.** Bidirectional sync against the Hardcover GraphQL API. Pass 1 (HC→MD): patches status, rating, dates; creates files for new books. Pass 2 (MD→HC): pushes local changes back. Identity reconciliation links books arriving from both Readwise and Hardcover to the same file. Full details: [docs/books.md](docs/books.md).

**RSS ingestion.** Feed-agnostic semantic ingestion: `RssFetchService` (HTTP+XML → `List<RssEntry>`) → source-specific `RssAdapter` → storage. `LetterboxdAdapter` projects movies into `Interesting/Entities/`; `SubstackAdapter`/`GenericAdapter` project articles into `Interesting/Articles/` via `ArticleStorageService`. Feed configs in `Interesting/System/integrations.md` via `IntegrationsConfigService`. Managed via Settings → RSS Feeds.

**ReadEra ingestion.** Import-only enrichment source for canonical book objects. Parses a ReadEra `.bak` backup file (ZIP archive containing `library.json`), extracts highlights/citations, and merges them into existing `Interesting/Books/*.md` files via `BookStorageService.appendReaderaHighlights()`. Dedup anchor: `^re{uuid}`. No API, no config. Triggered manually via Settings → ReadEra → "Import from .bak".

**Grokipedia.** Read-only projection: searches for an article matching the entity name, displays it inline. Nothing is ever written to the vault.

**Android widget.** Native Android Activity (no Flutter engine at runtime). Reads `flutter.vault_path` directly from `FlutterSharedPreferences` — the `flutter.` prefix is what Flutter's shared_preferences plugin writes. Always writes `category: Default`.

**Obsidian launch.** A single AppBar action fires `obsidian://` via `url_launcher` and returns. Purpose: Obsidian Sync only activates when Obsidian is foregrounded. No sync logic, no background behavior, no state.

## Running

```
flutter pub get
flutter run -d android
```

First launch shows a vault folder picker. The app creates all `Interesting/` subdirectories and seeds five default templates.

**Android:** Requires "All Files Access" (`MANAGE_EXTERNAL_STORAGE`) on Android 11+. A permission gate appears on first launch; re-checked on every app resume.

## Dependencies

- `path_provider` — app documents directory (legacy JSON→Markdown migration)
- `file_picker` — vault folder picker
- `yaml` — YAML frontmatter parsing
- `shared_preferences` — vault path and settings persistence
- `path` — cross-platform path manipulation
- `permission_handler` — Android All Files Access gate
- `http` — network requests (AnkiConnect, Grokipedia, Readwise, Hardcover, RSS feeds; all user-triggered, no background polling)
- `xml` — RSS/XML parsing
- `url_launcher` — Grokipedia article links; Obsidian `obsidian://` URI
- `archive` — ZIP decoding for ReadEra `.bak` backup import
