Focus on creating progressively better abstractions: implementation should become more elegant and hard-to-vary over time. Encode error-correcting mechanisms into the code.

# Project

Filesystem-native semantic knowledge layer. All data lives as Markdown files in a user-chosen vault. The app patches files it co-owns; it does not rebuild or replace them. Architectural rationale: [README.md](README.md). This file states constraints and their enforcement points — organized for agents making code changes.

## Documentation philosophy

This file is a **constraint registry**, not a narrative. Keep it:
- **Precise over complete** — capture the constraint that prevents a mistake, not the full story.
- **Hard-to-vary** — a rule that can be rephrased arbitrarily has no explanatory power.
- **Current** — stale constraints erode trust in the rest.

`README.md` is the architectural story (what + why). `CLAUDE.md` is the enforcement layer (do/don't + where). `docs/*.md` holds full subsystem detail. Don't duplicate across layers.

**Update `README.md` and `CLAUDE.md` when:** a new write path appears, an architectural invariant changes, an identity anchor is added, or a service standard changes. Don't update for UI layout changes, sort options, or internal refactors that preserve external behavior.

---

## Traversal guide

Start here based on task class:

| Task | Read first |
|------|-----------|
| Adding or modifying a book enrichment source | [docs/books.md](docs/books.md), then `BookStorageService` |
| Understanding the book enrichment source pattern | [docs/readwise.md](docs/readwise.md) (Readwise), [docs/readera.md](docs/readera.md) (ReadEra) |
| Modifying entity files, graph, or categories | [docs/entities.md](docs/entities.md), then `MarkdownStorageService` |
| Modifying or adding an RSS adapter | CLAUDE.md § RSS ingestion, then `rss_adapter.dart` |
| Modifying Anki sync | [docs/anki.md](docs/anki.md), then `AnkiSyncService` |
| Modifying integration config storage | CLAUDE.md § Configuration ownership, then `IntegrationsConfigService` |
| Adding a new sort option | CLAUDE.md § Sorting, then `MarkdownStorageService.sortEntities()` |
| Adding a new screen | [docs/mobile_ux.md](docs/mobile_ux.md) |
| Touching shared Markdown utilities | `lib/shared/markdown/md_utils.dart` (pure, no I/O) |
| Understanding save/cancel/snapshot semantics | CLAUDE.md § Save semantics, then `entity_screen.dart` |

---

## Architectural invariants

These five rules define the system's identity. Violating any changes what it fundamentally is.

**1. Markdown is the database.**
No SQLite, no parallel JSON persistence alongside `.md` files. WHY: dual-truth corrupts silently — when two stores diverge, there is no canonical answer.

**2. `alias` is immutable after creation.**
`entity.id == alias` for all EntityLinks. Never regenerate on rename. WHY: filenames change; alias is the stable graph identity — regenerating it orphans every wikilink. Enforcement: `_saveEdit()` in `entity_screen.dart`.

**3. Patch-not-rebuild.**
Existing entity files are always patched via `_patchEntityContent()`, never regenerated from template. WHY: rebuilding destroys user's custom `##` sections on every save. Enforcement: `markdown_storage_service.dart`.

**4. Semantic section registry is the app/user boundary.**
Only keys in `_semanticSections` (`Why Interesting`, `Related`, `Sources`) are rewritten on save. Do not add hardcoded section names outside this map. WHY: any name outside the registry bypasses the user-territory contract and risks erasing user prose. Enforcement: `_semanticSections` const in `markdown_storage_service.dart`.

**5. Full-body wikilink scan.**
`extractWikilinks(body)` scans the whole Markdown body, not just `## Related`. WHY: narrowing the scan makes graph edges location-dependent — moving a link between sections silently drops an edge. Enforcement: `_parseEntityFile` in `markdown_storage_service.dart`.

## Service standard

All services are **all-static, all-catch-null, never throw**. Errors surface via return values (`String?` error, `ImportResult.error`, or `null`) — never exceptions. This applies to: `AnkiConnectService`, `ListStorageService`, `TaskStorageService`, `AnkiStorageService`, `BookStorageService`, `ReadwiseService`, `HardcoverService`, `RssFetchService`, `RssFeedStorageService`, `RssIngestionService`, `ArticleStorageService`, `IntegrationsConfigService`, `ReaderaParser`, `ReaderaIngestionService`.

## Save semantics

- **Deferred save for core entity fields** (name, category, tags, score, notes, links) — explicit Save button via `_saveEdit()`. WHY: Cancel must restore the pre-edit snapshot atomically.
- **Immediate save for shared mutations** (`_createEntityLink`, `_deleteEntityLink`, `_addToList`, `_removeFromList`). WHY: they mutate shared state the entity snapshot doesn't cover.
- `saveData()` snapshots all entity lists before the async gap to prevent partial-save races.
- `updated_at` stamped on every mutation: entities in `_save()`, Anki cards in `AnkiStorageService.saveCard()` and `createNewCard()`.

## Write paths

Each canonical storage service owns exactly one directory. Nothing writes outside its directory.

| Storage layer | Directory |
|---|---|
| `MarkdownStorageService` | `Interesting/Entities/` (user entities) |
| `LetterboxdAdapter` | `Interesting/Entities/` (RSS movies; bypasses `MarkdownStorageService`) |
| `ListStorageService` | `Interesting/Lists/` |
| `AnkiStorageService` | `Interesting/Anki/` + `.trash/` |
| `TaskStorageService` | `Interesting/Tasks/` |
| `BookStorageService` | `Interesting/Books/` ← `ReadwiseService`, `HardcoverSyncService`, `ReaderaIngestionService` write only via this |
| `ArticleStorageService` | `Interesting/Articles/` ← `SubstackAdapter`, `GenericAdapter` write only via this |
| `IntegrationsConfigService` | `Interesting/System/` — vault-native integration config (`integrations.md`) |

## Identity anchors

| Type | Anchor | Mutability | Delete |
|---|---|---|---|
| Entity | `alias` (frontmatter) | Immutable after creation | Hard |
| Anki card | `anki_id` (frontmatter) | Immutable after first Anki sync | Soft (`.trash/`) |
| Book | `alias` (frontmatter) | Stable | Hard |
| Article | `alias` (frontmatter); GUID as dedup key | Stable | Hard |
| List | `slugify(name)` derived at load | Not preserved across rename | Hard |
| Task file | None | — | Hard |

Anki soft-delete rationale: a hard-deleted card re-synced from Anki would receive a new `anki_id`, permanently breaking the identity chain.

## Shared utilities — do not duplicate

- **Markdown parsing** — `lib/shared/markdown/md_utils.dart` (pure, no I/O): frontmatter splitting, section parsing, wikilink extraction, `slugify`, `sanitizeFilename`, timestamp helpers. Never reimplement in services or screens.
- **UI primitives** — `lib/shared/widgets/`: `showInputDialog()`, `showConfirmDialog()`, `showBottomSheetMenu()`, `SectionHeader`, `EmptyState`, `WikilinkText`. Never inline `AlertDialog+TextField` or `showModalBottomSheet` patterns.
- **Spacing** — `lib/shared/constants/app_spacing.dart`: `kFabListBottomPad` (88.0), `kScreenHPad` (16.0). No magic numbers.

## Configuration ownership

Integration configuration lives in `Interesting/System/integrations.md` (vault-canonical), managed by `IntegrationsConfigService` in `lib/core/`. SharedPreferences is bootstrap/cache only:

| Key | Location | Rationale |
|---|---|---|
| `vault_path` | SharedPreferences | Must be known before vault is accessible |
| `anki_connect_url` | SharedPreferences | Device-specific LAN address; not portable |
| Readwise token | `integrations.md` | Portable; syncs via Obsidian Sync |
| Hardcover token | `integrations.md` | Portable; syncs via Obsidian Sync |
| RSS feed configs | `integrations.md` | Portable; syncs via Obsidian Sync |

Migration from SharedPreferences runs once on first `_loadData()` (idempotent: skipped if file already exists). All token/config methods on `ReadwiseService`, `HardcoverService`, and `RssFeedStorageService` require `vaultPath` — consistent with other storage services.

## Subsystem constraints

**Anki** — `anki_id` immutable (see identity anchors table); soft-delete only; review metadata (intervals, ease, due dates) never written to Markdown. Full details: [docs/anki.md](docs/anki.md).

**Lists** — `saveList` rebuilds the file from items (safe — list files have no user prose sections). Item order in file = semantic order. Entity membership inferred by wikilink scan, no join table. Do not add due dates, priorities, or subtasks to list items.

**Tasks** — no YAML frontmatter; `parseNodes()` is pure (call only after `loadLines()`, never from `loadTaskFiles()`); `_collapsed` is session-only, never persist; `deleteBlock` hard-deletes with no trash; completing a root block calls `toggleBlockAndReorder`, which moves it to end-of-file; root blocks drag-reorderable via `reorderRootBlocks`. Do not add due dates, reminders, or notifications. Full details: [docs/tasks.md](docs/tasks.md).

**Grokipedia** — never writes to vault; no caching; state (`_grokArticle`, `_grokSearched`, `_grokSummaryExpanded`, `_grokSummaryFetching`, `_grokFetchedSummary`) lives only in `_EntityScreenState`.

**Books** — canonical semantic containers enriched by multiple independent sources. Schema: `type: book`, `alias`, `authors`, `hardcover_id`, `readwise_id`, `isbn`; books do NOT participate in entity graph yet; lazy migration from `type: book_highlights` on first load; field ownership strictly partitioned (Readwise owns `readwise_id`/`num_highlights`/`last_highlight_at`; Hardcover owns `hardcover_id`/`status`/`rating`/`started_at`/`finished_at`); `BookStorageService.patchFields()` is the minimal-patch primitive — all enrichment writes call through it. `appendReaderaHighlights()` is the ReadEra highlight append primitive. Full details: [docs/books.md](docs/books.md).

**Readwise** — token in `integrations.md` via `IntegrationsConfigService`; patches only Readwise-owned fields; re-import appends only new `^rw{id}` highlight blocks, never overwrites. Full details: [docs/readwise.md](docs/readwise.md).

**ReadEra** — import-only; parses `.bak` (ZIP archive containing `library.json`); merges highlights into canonical `Books/*.md` via `BookStorageService.appendReaderaHighlights()`; dedup anchor `^re{uuid}` in `## Highlights (ReadEra)` section; reconciles by title slug (no ISBN in ReadEra exports); no vault config required. Full details: [docs/readera.md](docs/readera.md).

**Hardcover** — bidirectional sync via GraphQL; explicit sync only via `HardcoverSyncService.sync()` (no background); two-pass: HC→MD then MD→HC; identity reconciliation prevents duplicate files. `HardcoverScreen` is a tab (not a pushed route); `HardcoverScreenState` is public so `HomeScreen` can drive sync and search via `GlobalKey`. Token in `integrations.md` via `IntegrationsConfigService`. Critical API quirks (me-as-List, cached_contributors-as-scalar, no isbn_13): [docs/books.md § API quirks](docs/books.md).

**RSS ingestion** — architecture: `RssFetchService` (HTTP+XML → `List<RssEntry>`) → `RssAdapter` → storage, dispatched by `RssIngestionService`. Adapters: `LetterboxdAdapter` (→ `Interesting/Entities/`), `SubstackAdapter`/`GenericAdapter` (→ `Interesting/Articles/` via `ArticleStorageService`). Feed configs in `Interesting/System/integrations.md` via `IntegrationsConfigService`. Identity dedup: guid > normalized URL > normalized title. Explicit sync only. To add a source type: add to `RssFeedType`, implement `RssAdapter`, wire in `RssIngestionService._adapterFor()`.

**Obsidian launch** — UI-only AppBar action; fires `obsidian://` URI, returns. No sync logic, no state, no lifecycle hooks.

**Android widget** — reads `flutter.vault_path` directly from `FlutterSharedPreferences`; always writes `category: Default`; only three concrete subclasses registered as receivers.

**State management** — `setState` only. No `Provider`, `Riverpod`, `Bloc`.

**Sorting** — all entity list sorting routes through `MarkdownStorageService.sortEntities(entities, sortOrder)`. Add new sort options there first, then `DropdownMenuItem` entries in screens. Entity pickers are pre-sorted A→Z inline (not via `sortEntities`).

**Entity movie fields** — `Entity` has three optional movie-specific fields: `watchedDate`, `letterboxdUrl`, `tmdbId`. Adding category-specific fields requires updating both `_parseEntityFile` and `_buildFrontmatter` in `markdown_storage_service.dart`.

## Mobile UX conventions

Full reference: [docs/mobile_ux.md](docs/mobile_ux.md). Enforcement rules:

- Every `Scaffold` body: `SafeArea(top: false)` (AppBar handles top; SafeArea handles gesture nav bar bottom)
- Every list behind a FAB: `padding: const EdgeInsets.only(bottom: kFabListBottomPad)`
- Scrollable search sheets (`isScrollControlled: true`): `screenHeight * fraction` for height, never fixed pixels
- Every `TextField`: declare `textInputAction` (`next` / `done` / `newline` / `send`)

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
