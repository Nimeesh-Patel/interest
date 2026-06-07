# Interest

## What this system is

A problem-centric semantic traversal environment. All data lives as plain Markdown in a user-chosen vault. The application is a **projection layer** over that vault — it reads, patches, and navigates Markdown without owning it. Vault files are readable by any text editor, Obsidian-compatible, and will outlive the app.

This is not a CRUD app with Markdown export. Markdown is the **canonical storage medium**. The entire system state can be reconstructed from the vault. Nothing is persisted outside it except the vault path itself.

The architecture consistently rejects two alternatives: (1) treating Markdown as a rendering surface for data stored elsewhere, and (2) treating the app as the canonical owner that syncs outward to files. Both alternatives create dual-truth corruption. The vault-as-database invariant prevents this.

---

## Vault layout

```
<vault>/
  *.md                 — Entities, movies (Letterboxd), and bookmarks at vault root
  Interesting/
    Entities/          — created on first launch; entities may live here or at vault root
    Projects/          — one .md file per project (canonical)
    Lists/             — legacy migration source only; no new files created here
    Templates/         — category templates; seeded on first launch; user-editable
    Tasks/             — legacy migration source only; no new files created here
    Books/             — one .md file per book; convergence point for multiple enrichment sources
    Articles/          — one .md file per RSS-imported article
    System/            — vault-native configuration (integrations.md, review_log.md)
```

All subdirectories are created on first launch (`VaultService.ensureVaultDirectories`). The `Interesting/` tree is the app's semantic territory. Everything else in the vault is the user's — raw notes, journal entries, epistemic artifacts. The resurfacing viewer scans this broader territory.

---

## Semantic architecture

### Canonical ownership vs. projection

The app **co-owns** certain files (entity files, book files) and **reads** others (the rest of the vault for resurfacing). Within co-owned files the app owns only a fixed set of frontmatter keys; the entire note body — prose, `***` front/back, `[[wikilinks]]`, the user's `##` sections — is preserved verbatim on every save.

Projections are computed at read time and never persisted:

| Projection | Derived from | Written back? |
|---|---|---|
| Entity graph (edges) | `extractWikilinks(body)` over all entity files | No |
| Collections | distinct `collection:` frontmatter values | No |
| Tags | all `tags` values, deduplicated | No |
| List membership | wikilink scan within list files | No |
| Resurfacing cards | `***` separator in vault notes | No |

### Identity and stability

Every semantic object has an identity anchor that survives renames and file moves:

| Type | Anchor | Mutability |
|---|---|---|
| Entity | `collection:` membership; identity = note name (filename); `alias:` optional | filename can change |
| Problem note (AnkiDroid) | `anki_note_id` (frontmatter) | Written on first sync; stable |
| Book | `alias` (frontmatter) | Stable |
| Article | `alias` + GUID dedup key | Stable |
| Task file | None | — |

### Frontmatter-not-body

Entity writes patch only the app-owned frontmatter keys; the note body is never rewritten by the entity layer. The body is edited as plain Markdown via `NoteEditScreen`. This is the structural guarantee that an entity save can never destroy note content — including a Problem Note's `***` front/back when a note is both.

### Books as convergence objects

Books are the most complex ownership case. Multiple independent systems (Readwise, Hardcover, ReadEra, the user) enrich the same Markdown file. Field ownership is strictly partitioned. No system touches another system's fields. `BookStorageService.patchFields()` is the only write primitive.

### Epistemic artifacts and resurfacing

Notes outside `Interesting/` are understood as **problem-oriented epistemic artifacts** — evolving documents that encode problem-situations, conjectures, and partial resolutions. The `***` horizontal rule in a note body is treated as a semantic separator between these two sides. The resurfacing viewer (tab 1 — Notes) projects these pairs into a front/back card viewer with IBM Plex Serif typography. An **All Notes hero** card at the top of the deck list surfaces the total card count; a **Browse Notes** section below lists all vault notes regardless of card status. The **Home dashboard** (tab 0) surfaces the first prioritised card's question as a peek, and a "Worth Revisiting" section of entities weighted by score and recency. Notes are searchable by filename and body text. The inline note editor writes changes directly back to vault files, preserving frontmatter verbatim.

---

## Subsystem map

| Subsystem | Directory | Role |
|---|---|---|
| Home dashboard | `lib/features/home/` | Daily entry point (tab 0); card-peek hero, Worth Revisiting entities, recent notes, persistent Quick Add FAB |
| Entities + graph | `Interesting/Entities/` | Core semantic graph; canonical node objects |
| Projects | `Interesting/Projects/` | Flexible semantic workspaces; unified from Lists + Tasks |
| Notes / Resurface | vault-wide | Deck viewer for `***`-separated notes (tab 1); activation model; graph-score + time-decay sort; full-text search; inline note editor; IBM Plex Serif card rendering; All Notes hero + Browse Notes list |
| AnkiDroid | Sources screen | Push problem notes to AnkiDroid via ContentProvider; `anki_note_id` written back to frontmatter |
| Books | `Interesting/Books/` | Convergence objects enriched by Readwise, Hardcover, ReadEra |
| Readwise | → Books | Highlight ingestion; patches Readwise-owned fields only |
| Hardcover | → Books | Bidirectional reading-state sync; accessed via Sources screen |
| ReadEra | → Books | Highlight import from `.bak`; patches ReadEra section only |
| RSS | `Interesting/Articles/`, `Interesting/Entities/` | Feed ingestion; adapter-dispatched by source type |
| Templates | `Interesting/Templates/` | One-time entity instantiation templates |
| Sources screen | pushed from AppBar | Inbox-style hub: Hardcover, Articles, Readwise, Bookmarks, Obsidian, AnkiDroid rows; "Sync all" button |
| Android widget | native | Reads vault path from SharedPreferences; creates entities |
| Grokipedia | read-only projection | External article display inline in entity screen; never writes |
| Bookmarks | vault root | X bookmark ingestion via share sheet; nitter→syndication→oEmbed→degraded fetch chain; `***` Resurface separator in every note |

Full subsystem detail: [docs/entities.md](docs/entities.md), [docs/books.md](docs/books.md), [docs/ankidroid.md](docs/ankidroid.md), [docs/projects.md](docs/projects.md), [docs/readwise.md](docs/readwise.md), [docs/readera.md](docs/readera.md), [docs/resurface.md](docs/resurface.md), [docs/bookmarks.md](docs/bookmarks.md).

---

## Architecture

```
lib/
  main.dart                — permission gate + routing
  core/                    — vault path (SharedPreferences) + directory bootstrap
                             + IntegrationsConfigService (vault-native integration config)
  shared/markdown/         — pure Markdown parsing + YAML frontmatter builder (md_utils) + filesystem I/O (md_io)
                             + vault_scanner.dart (stream-based .md file scanner with folder exclusions)
  shared/widgets/          — reusable UI primitives: SectionHeader, EmptyState, WikilinkText,
                             showInputDialog, showConfirmDialog, showBottomSheetMenu, showQuickAddSheet
  shared/constants/        — app_spacing.dart, app_theme.dart (AppColors + ThemeData),
                             app_text_styles.dart (AppTextStyles — IBM Plex Sans/Serif named getters)
  features/
    home/                  — HomeDashboardScreen (tab 0): card-peek hero, Worth Revisiting, recent notes,
                             persistent Quick Add FAB; loads from ResurfaceService + MarkdownStorageService
    entities/              — core storage (MarkdownStorageService), Entity, EntityScreen (inline note edit,
                             always-visible + Add note / + Link, Done AppBar button on unsaved changes);
                             services/entity_file_parser.dart (parse entity .md → Entity),
                             services/entity_file_writer.dart (patch/rebuild entity .md),
                             controllers/entity_list_controller.dart (filter/sort/search state)
    projects/              — ProjectFile, ProjectStorageService, ProjectsScreen; two detail screens:
                             TaskFileScreen (todo-style) + ProjectListDetailScreen (list-style)
    tasks/                 — TaskBlock tree, TaskStorageService (block mutations only), TaskFileScreen (shared with projects)
    books/                 — Book model, BookStorageService, HardcoverService/SyncService
    readwise/              — ReadwiseService, ReadwiseScreen (enriches Books/)
    rss/                   — RssFetchService, adapters (letterboxd/substack/generic),
                             ArticleStorageService, RssIngestionService, RssScreen
    readera/               — ReaderaParser (.bak ZIP+JSON), ReaderaIngestionService
    resurface/             — ResurfaceService (vault scan), ResurfaceNote + ProblemNote models,
                             AnkiDroidService (MethodChannel bridge; syncVault()),
                             services/ankidroid_sync_controller.dart (orchestrates load + sync),
                             ReviewLogService (review_log.md owner), GraphScoringService (BFS + decay),
                             controllers/card_viewer_controller.dart (queue, position, TraversalSession),
                             ResurfaceScreen (All Notes hero + deck list + Browse Notes + card viewer),
                             screens/_backlinks_section.dart (backlinks widget for note detail),
                             NoteDetailScreen (note body viewer),
                             NoteEditScreen (note editor; writes vault files)
    templates/, settings/  — self-contained, no MarkdownStorageService dependency
  screens/home_screen.dart    — BottomNavigationBar shell (four tabs: Home, Notes, Entities, Projects);
                                AppBar: sensors → Sources, popup → Settings / Templates
  screens/sources_screen.dart — Sources Inbox (Hardcover, Articles, Readwise, Bookmarks, Obsidian, AnkiDroid rows;
                                 Sync all button)
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

- `google_fonts` — IBM Plex Sans (UI) and IBM Plex Serif (card front/back) via Google Fonts CDN
- `path_provider` — app documents directory (legacy JSON→Markdown migration)
- `file_picker` — vault folder picker
- `yaml` — YAML frontmatter parsing
- `shared_preferences` — vault path and settings persistence (bootstrap only)
- `path` — cross-platform path manipulation
- `permission_handler` — Android All Files Access gate
- `http` — network requests (Grokipedia, Readwise, Hardcover, RSS; all user-triggered)
- `xml` — RSS/XML parsing
- `url_launcher` — Grokipedia article links; Obsidian `obsidian://` URI
- `archive` — ZIP decoding for ReadEra `.bak` backup import
