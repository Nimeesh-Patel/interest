# Entity Tracker

## What this system is

A filesystem-native semantic knowledge environment. All data lives as plain Markdown in a user-chosen vault. The application is a **projection layer** over that vault — it reads, patches, and navigates Markdown without owning it. Vault files are readable by any text editor, Obsidian-compatible, and will outlive the app.

This is not a CRUD app with Markdown export. Markdown is the **canonical storage medium**. The entire system state can be reconstructed from the vault. Nothing is persisted outside it except the vault path itself.

The architecture consistently rejects two alternatives: (1) treating Markdown as a rendering surface for data stored elsewhere, and (2) treating the app as the canonical owner that syncs outward to files. Both alternatives create dual-truth corruption. The vault-as-database invariant prevents this.

---

## Vault layout

```
<vault>/
  Interesting/
    Entities/   — one .md file per entity; semantic graph lives here
    Lists/      — one .md file per list (flat item collection)
    Templates/  — category templates; seeded on first launch; user-editable
    Anki/       — one .md file per Anki card
      .trash/   — soft-deleted cards
    Tasks/      — one .md file per task topic; pure Markdown, no frontmatter
    Books/      — one .md file per book; convergence point for multiple enrichment sources
    Articles/   — one .md file per RSS-imported article
    System/     — vault-native configuration (integrations.md)
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
| List | `slugify(name)` | Not preserved across rename |
| Task file | None | — |

### Patch-not-rebuild

Existing entity files are always patched in-place (`_patchEntityContent()`), never regenerated from template. Rebuilding from scratch would silently destroy user `##` sections on every save. The template is applied once at creation; never again.

### Books as convergence objects

Books are the most complex ownership case. Multiple independent systems (Readwise, Hardcover, ReadEra, the user) enrich the same Markdown file. Field ownership is strictly partitioned. No system touches another system's fields. `BookStorageService.patchFields()` is the only write primitive.

### Epistemic artifacts and resurfacing

Notes outside `Interesting/` are understood as **problem-oriented epistemic artifacts** — evolving documents that encode problem-situations, conjectures, and partial resolutions. The `***` horizontal rule in a note body is treated as a semantic separator between these two sides. The resurfacing viewer projects these pairs into a lightweight front/back viewer without modifying the notes. This is a read-only semantic projection over the user's broader vault.

---

## Subsystem map

| Subsystem | Directory | Role |
|---|---|---|
| Entities + graph | `Interesting/Entities/` | Core semantic graph; canonical node objects |
| Lists | `Interesting/Lists/` | Flat item collections; membership inferred by wikilink |
| Tasks | `Interesting/Tasks/` | Ephemeral working lists; no identity anchor |
| Anki | `Interesting/Anki/` | Bidirectional semantic sync with Anki; soft-delete |
| Books | `Interesting/Books/` | Convergence objects enriched by Readwise, Hardcover, ReadEra |
| Readwise | → Books | Highlight ingestion; patches Readwise-owned fields only |
| Hardcover | → Books | Bidirectional reading-state sync; patches HC-owned fields only |
| ReadEra | → Books | Highlight import from `.bak`; patches ReadEra section only |
| RSS | `Interesting/Articles/`, `Interesting/Entities/` | Feed ingestion; adapter-dispatched by source type |
| Resurface | vault-wide (read-only) | Semantic resurfacing projection over `***`-separated notes |
| Templates | `Interesting/Templates/` | One-time entity instantiation templates |
| Android widget | native | Reads vault path from SharedPreferences; creates entities |
| Grokipedia | read-only projection | External article display inline in entity screen; never writes |

Full subsystem detail: [docs/entities.md](docs/entities.md), [docs/books.md](docs/books.md), [docs/anki.md](docs/anki.md), [docs/tasks.md](docs/tasks.md), [docs/readwise.md](docs/readwise.md), [docs/readera.md](docs/readera.md), [docs/resurface.md](docs/resurface.md).

---

## Architecture

```
lib/
  main.dart                — permission gate + routing
  core/                    — vault path (SharedPreferences) + directory bootstrap
                             + IntegrationsConfigService (vault-native integration config)
  shared/markdown/         — pure Markdown parsing (md_utils) + filesystem I/O (md_io)
  shared/widgets/          — 6 reusable UI primitives
  shared/constants/        — app-wide constants (app_spacing.dart)
  features/
    entities/              — core storage (MarkdownStorageService), Entity, EntityScreen
    lists/                 — ListModel, ListStorageService, ListDetailScreen
    tasks/                 — TaskBlock tree, TaskStorageService
    anki/                  — AnkiCard, three services (connect/storage/sync), two screens
    books/                 — Book model, BookStorageService, HardcoverService/SyncService
    readwise/              — ReadwiseService, ReadwiseScreen (enriches Books/)
    rss/                   — RssFetchService, adapters (letterboxd/substack/generic),
                             ArticleStorageService, RssIngestionService, RssScreen
    readera/               — ReaderaParser (.bak ZIP+JSON), ReaderaIngestionService
    resurface/             — ResurfaceService (vault scan), ResurfaceScreen (viewer)
    templates/, settings/  — self-contained, no MarkdownStorageService dependency
  screens/home_screen.dart — BottomNavigationBar shell (owns state for all four tabs)
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
