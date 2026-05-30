# Entity Tracker

## What this system is

A filesystem-native semantic knowledge environment. All data lives as plain Markdown in a user-chosen vault. The application is a **projection layer** over that vault — it reads, patches, and navigates Markdown without owning it. Vault files are readable by any text editor, Obsidian-compatible, and will outlive the app.

This is not a CRUD app with Markdown export. Markdown is the **canonical storage medium**. The entire system state can be reconstructed from the vault. Nothing is persisted outside it except the vault path itself.

The architecture consistently rejects two alternatives: (1) treating Markdown as a rendering surface for data stored elsewhere, and (2) treating the app as the canonical owner that syncs outward to files. Both alternatives create dual-truth corruption. The vault-as-database invariant prevents this.

---

## Vault layout

```
<vault>/
  *.md                 — Bookmarks (one .md file per bookmark, written by XBookmarkStorageService)
  Interesting/
    Entities/          — one .md file per entity; semantic graph lives here
    Projects/          — one .md file per project (canonical)
    Lists/             — legacy migration source only; no new files created here
    Templates/         — category templates; seeded on first launch; user-editable
    Anki/              — one .md file per Anki card
      .trash/          — soft-deleted cards
    Tasks/             — legacy migration source only; no new files created here
    Books/             — one .md file per book; convergence point for multiple enrichment sources
    Articles/          — one .md file per RSS-imported article
    System/            — vault-native configuration (integrations.md, review_log.md)
```

All subdirectories are created on first launch (`VaultService.ensureVaultDirectories`). The `Interesting/` tree is the app's semantic territory. Everything else in the vault is the user's — raw notes, journal entries, epistemic artifacts. The resurfacing viewer scans this broader territory.

---

## Semantic architecture

### Canonical ownership vs. projection

The app **co-owns** certain files (entity files, Anki card files, book files) and **reads** others (the rest of the vault for resurfacing). Within co-owned files, ownership is further partitioned: only the keys in `_semanticSections` are rewritten on save; every other `##` section the user writes is preserved verbatim.

Projections are computed at read time and never persisted:

| Projection | Derived from | Written back? |
|---|---|---|
| Entity graph (edges) | `extractWikilinks(body)` over all entity files | No |
| Categories | distinct `category` frontmatter values | No |
| Tags | all `tags` values, deduplicated | No |
| List membership | wikilink scan within list files | No |
| Resurfacing cards | `***` separator in vault notes | No |

### Identity and stability

Every semantic object has an identity anchor that survives renames and file moves:

| Type | Anchor | Mutability |
|---|---|---|
| Entity | `alias` (frontmatter) | Immutable after creation |
| Anki card | `anki_id` (frontmatter) | Immutable after first sync |
| Book | `alias` (frontmatter) | Stable |
| Article | `alias` + GUID dedup key | Stable |
| Task file | None | — |

### Patch-not-rebuild

Existing entity files are always patched in-place (`_patchEntityContent()`), never regenerated from template. Rebuilding from scratch would silently destroy user `##` sections on every save. The template is applied once at creation; never again.

### Books as convergence objects

Books are the most complex ownership case. Multiple independent systems (Readwise, Hardcover, ReadEra, the user) enrich the same Markdown file. Field ownership is strictly partitioned. No system touches another system's fields. `BookStorageService.patchFields()` is the only write primitive.

### Epistemic artifacts and resurfacing

Notes outside `Interesting/` are understood as **problem-oriented epistemic artifacts** — evolving documents that encode problem-situations, conjectures, and partial resolutions. The `***` horizontal rule in a note body is treated as a semantic separator between these two sides. The resurfacing viewer projects these pairs into a lightweight front/back viewer. Notes are also searchable by filename and body text. The inline note editor writes changes directly back to vault files, preserving frontmatter verbatim.

---

## Subsystem map

| Subsystem | Directory | Role |
|---|---|---|
| Entities + graph | `Interesting/Entities/` | Core semantic graph; canonical node objects |
| Projects | `Interesting/Projects/` | Flexible semantic workspaces; unified from Lists + Tasks |
| Notes / Resurface | vault-wide | Deck viewer for `***`-separated notes; activation model promotes linked non-`***` notes into the same queue after their `***` neighbour is reviewed; configurable BFS degree range (min/max hops); graph-score + time-decay sort priority; full-text search; inline note editor (structured/plain/raw modes); `deck:` frontmatter groups notes; `[[wikilinks]]` render as tappable links and navigate vault-wide by filename match |
| Anki | `Interesting/Anki/` | Bidirectional semantic sync with Anki; soft-delete |
| Books | `Interesting/Books/` | Convergence objects enriched by Readwise, Hardcover, ReadEra |
| Readwise | → Books | Highlight ingestion; patches Readwise-owned fields only |
| Hardcover | → Books | Bidirectional reading-state sync; accessed via Sources screen |
| ReadEra | → Books | Highlight import from `.bak`; patches ReadEra section only |
| RSS | `Interesting/Articles/`, `Interesting/Entities/` | Feed ingestion; adapter-dispatched by source type |
| Templates | `Interesting/Templates/` | One-time entity instantiation templates |
| Sources screen | AppBar action | Hub for Hardcover, RSS, Readwise, Bookmarks |
| Android widget | native | Reads vault path from SharedPreferences; creates entities |
| Grokipedia | read-only projection | External article display inline in entity screen; never writes |
| Bookmarks | vault root | X bookmark ingestion via share sheet; nitter→syndication→oEmbed→degraded fetch chain; `***` Resurface separator in every note; one .md file per bookmark |

Full subsystem detail: [docs/entities.md](docs/entities.md), [docs/books.md](docs/books.md), [docs/anki.md](docs/anki.md), [docs/projects.md](docs/projects.md), [docs/readwise.md](docs/readwise.md), [docs/readera.md](docs/readera.md), [docs/resurface.md](docs/resurface.md), [docs/bookmarks.md](docs/bookmarks.md).

---

## Architecture

```
lib/
  main.dart                — permission gate + routing
  core/                    — vault path (SharedPreferences) + directory bootstrap
                             + IntegrationsConfigService (vault-native integration config)
  shared/markdown/         — pure Markdown parsing + YAML frontmatter builder (md_utils) + filesystem I/O (md_io)
  shared/widgets/          — 6 reusable UI primitives
  shared/constants/        — app-wide constants (app_spacing.dart, app_theme.dart)
  features/
    entities/              — core storage (MarkdownStorageService), Entity, EntityScreen
    projects/              — ProjectFile, ProjectStorageService, ProjectsScreen; two detail screens:
                             TaskFileScreen (todo-style) + ProjectListDetailScreen (list-style)
    tasks/                 — TaskBlock tree, TaskStorageService (block mutations only), TaskFileScreen (shared with projects)
    anki/                  — AnkiCard, three services (connect/storage/sync), two screens
    books/                 — Book model, BookStorageService, HardcoverService/SyncService
    readwise/              — ReadwiseService, ReadwiseScreen (enriches Books/)
    rss/                   — RssFetchService, adapters (letterboxd/substack/generic),
                             ArticleStorageService, RssIngestionService, RssScreen
    readera/               — ReaderaParser (.bak ZIP+JSON), ReaderaIngestionService
    resurface/             — ResurfaceService (vault scan), ResurfaceNote + ResurfaceCard models,
                             ReviewLogService (review_log.md owner), GraphScoringService (BFS + decay),
                             ResurfaceScreen (deck list + search + mixed viewer, Notes tab),
                             NoteDetailScreen (note body viewer),
                             NoteEditScreen (note editor; writes vault files)
    templates/, settings/  — self-contained, no MarkdownStorageService dependency
  screens/home_screen.dart    — BottomNavigationBar shell (three tabs: Notes, Entities, Projects)
  screens/sources_screen.dart — AppBar-launched hub for content sources (Hardcover, RSS, Readwise, Bookmarks)
```

---

## Running

```
flutter pub get
flutter run -d android
```

First launch shows a vault folder picker. The app creates all `Interesting/` subdirectories and seeds five default templates.

**Android:** Requires "All Files Access" (`MANAGE_EXTERNAL_STORAGE`) on Android 11+. A permission gate appears on first launch; re-checked on every app resume.

---

## Dependencies

- `path_provider` — app documents directory (legacy JSON→Markdown migration)
- `file_picker` — vault folder picker
- `yaml` — YAML frontmatter parsing
- `shared_preferences` — vault path and settings persistence (bootstrap only)
- `path` — cross-platform path manipulation
- `permission_handler` — Android All Files Access gate
- `http` — network requests (AnkiConnect, Grokipedia, Readwise, Hardcover, RSS; all user-triggered)
- `xml` — RSS/XML parsing
- `url_launcher` — Grokipedia article links; Obsidian `obsidian://` URI
- `archive` — ZIP decoding for ReadEra `.bak` backup import
