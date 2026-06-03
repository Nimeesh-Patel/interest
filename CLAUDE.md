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
| Modifying AnkiDroid sync | [docs/ankidroid.md](docs/ankidroid.md), then `AnkiDroidService` |
| Modifying resurfacing extraction, deck metadata, viewer, search, or note editing | [docs/resurface.md](docs/resurface.md), then `ResurfaceService` / `NoteEditScreen` |
| Modifying the Projects subsystem | [docs/projects.md](docs/projects.md), then `ProjectStorageService` |
| Modifying integration config storage | CLAUDE.md § Configuration ownership, then `IntegrationsConfigService` |
| Adding a new sort option | CLAUDE.md § Sorting, then `MarkdownStorageService.sortEntities()` |
| Adding a new screen | [docs/mobile_ux.md](docs/mobile_ux.md) |
| Touching shared Markdown utilities | `lib/shared/markdown/md_utils.dart` (pure, no I/O) |
| Understanding save/cancel/snapshot semantics | CLAUDE.md § Save semantics, then `entity_screen.dart` |
| Modifying the Home dashboard (card peek, Worth Revisiting, recent notes) | `lib/features/home/screens/home_dashboard_screen.dart` |
| Modifying the Quick Add Sheet | `lib/shared/widgets/quick_add_sheet.dart` |
| Modifying UI tokens, typography, or color palette | [docs/ui.md](docs/ui.md), then `app_theme.dart` + `app_text_styles.dart` |
| Modifying the Sources Inbox | `lib/screens/sources_screen.dart` |

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

All services are **all-static, all-catch-null, never throw**. Errors surface via return values (`String?` error, `ImportResult.error`, or `null`) — never exceptions. This applies to: `TaskStorageService`, `BookStorageService`, `ReadwiseService`, `HardcoverService`, `RssFetchService`, `RssFeedStorageService`, `RssIngestionService`, `ArticleStorageService`, `IntegrationsConfigService`, `ReaderaParser`, `ReaderaIngestionService`, `ResurfaceService`, `AnkiDroidService`, `ProjectStorageService`.

## Save semantics

- **Deferred save for core entity fields** (name, category, tags, score, notes, links) — `_saveEdit()` commits all pending changes. WHY: Cancel/Done must restore or commit the pre-edit snapshot atomically.
- **Inline note/title editing** (no explicit edit-mode toggle): tapping a note bullet or the entity title marks the screen dirty (`_markDirty()` takes a snapshot on first change, sets `_hasUnsavedChanges = true`). The AppBar shows a `check` icon only when `_hasUnsavedChanges == true`; tapping it calls `_saveEdit()`. When `_hasUnsavedChanges == false`, the AppBar shows the `edit` icon (full edit body for category/score/tags) and `more_vert`.
- **Immediate save for shared mutations** (`_createEntityLink`, `_deleteEntityLink`). WHY: they mutate shared state the entity snapshot doesn't cover.
- `saveData()` snapshots all entity lists before the async gap to prevent partial-save races.
- `updated_at` stamped on every mutation: entities in `_save()`.

## Write paths

Each canonical storage service owns exactly one directory. Nothing writes outside its directory.

| Storage layer | Directory |
|---|---|
| `MarkdownStorageService` | vault root (user entities; vault-wide `category:` scan) |
| `LetterboxdAdapter` | vault root (RSS movies; bypasses `MarkdownStorageService`) |
| `TaskStorageService` | `Interesting/Tasks/` (legacy; new files no longer created here) |
| `ProjectStorageService` | `Interesting/Projects/` (new files); also migrates from `Lists/` + `Tasks/` |
| `BookStorageService` | `Interesting/Books/` ← `ReadwiseService`, `HardcoverSyncService`, `ReaderaIngestionService` write only via this |
| `ArticleStorageService` | `Interesting/Articles/` ← `SubstackAdapter`, `GenericAdapter` write only via this |
| `IntegrationsConfigService` | `Interesting/System/` — vault-native integration config (`integrations.md`) |
| `XBookmarkStorageService` | vault root (`VaultService.bookmarksPath`) |
| `ResurfaceService` | **None** — read-only vault scan; never writes |
| `ReviewLogService` | `Interesting/System/review_log.md` — review state; sole writer |
| `TemplatesScreen` / `TemplateEditorScreen` | `Interesting/Templates/` — direct screen writes; no storage service intermediary |
| `NoteEditScreen` | any vault `.md` file passed as `filePath` — writes only to that exact path; no storage service intermediary |

## Identity anchors

| Type | Anchor | Mutability | Delete |
|---|---|---|---|
| Entity | `alias` (frontmatter) | Immutable after creation | Hard |
| Problem note (AnkiDroid) | `anki_note_id` (frontmatter) | Written on first sync; stable | Hard |
| Book | `alias` (frontmatter) | Stable | Hard |
| Article | `alias` (frontmatter); GUID as dedup key | Stable | Hard |
| Task file | None | — | Hard |


## Shared utilities — do not duplicate

- **Markdown parsing and YAML serialization** — `lib/shared/markdown/md_utils.dart` (pure, no I/O): frontmatter splitting, section parsing, wikilink extraction, `slugify`, `sanitizeFilename`, timestamp helpers, `buildFrontmatterBlock(fields, knownOrder)` (canonical YAML frontmatter builder — pass a field map and an ordered key list; handles scalar quoting, YAML lists, and unknown-key overflow). Never reimplement in services or screens.
- **UI primitives** — `lib/shared/widgets/`: `showInputDialog()`, `showConfirmDialog()`, `showBottomSheetMenu()`, `showQuickAddSheet()`, `SectionHeader`, `EmptyState`, `WikilinkText`. Never inline `AlertDialog+TextField` or raw `showModalBottomSheet` patterns.
- **Quick Add Sheet** — `lib/shared/widgets/quick_add_sheet.dart`: `showQuickAddSheet(context, entities:, categories:, tags:, allEntityLinks:, storage:, onCreated:)`. Persists last-used category in `SharedPreferences` key `last_used_category`. Call this wherever an "add entity" FAB appears.
- **Text styles** — `lib/shared/constants/app_text_styles.dart`: `AppTextStyles` class with static `TextStyle` getters for every named role (IBM Plex Sans body/UI, IBM Plex Serif for card front/back). Never hardcode `GoogleFonts.ibmPlexSans(...)` or `GoogleFonts.ibmPlexSerif(...)` inline — use the getter.
- **Colors** — `lib/shared/constants/app_theme.dart` `AppColors`: all color constants including `borderMid` (#282828) for card borders. Do not use hex literals inline.
- **Spacing** — `lib/shared/constants/app_spacing.dart`: `kFabListBottomPad` (88.0), `kScreenHPad` (16.0). No magic numbers.

## Configuration ownership

Integration configuration lives in `Interesting/System/integrations.md` (vault-canonical), managed by `IntegrationsConfigService` in `lib/core/`. SharedPreferences is bootstrap/cache only:

| Key | Location | Rationale |
|---|---|---|
| `vault_path` | SharedPreferences | Must be known before vault is accessible |
| Readwise token | `integrations.md` | Portable; syncs via Obsidian Sync |
| Hardcover token | `integrations.md` | Portable; syncs via Obsidian Sync |
| RSS feed configs | `integrations.md` | Portable; syncs via Obsidian Sync |
| Resurface excluded folders | `integrations.md` (`## Resurface`) | Portable; syncs via Obsidian Sync |

Migration from SharedPreferences runs once on first `_loadData()` (idempotent: skipped if file already exists). All token/config methods on `ReadwiseService`, `HardcoverService`, and `RssFeedStorageService` require `vaultPath` — consistent with other storage services.

## Subsystem constraints

**AnkiDroid** — one-way push only (vault → AnkiDroid); only `anki_note_id` written back to frontmatter; deck from `category:` field (default "Problem Notes"); review history never written to Markdown. Full details: [docs/ankidroid.md](docs/ankidroid.md).

**Projects** — unified semantic workspaces replacing Lists + Todos. New project files land in `Interesting/Projects/`. On first `ProjectStorageService.loadAll()`, existing files in `Lists/` and `Tasks/` are migrated to `Projects/` (best-effort, idempotent). Detail screen is always `TaskFileScreen`. No due dates, priorities, or scheduling. Full details: [docs/projects.md](docs/projects.md).

**Tasks (parser)** — `TaskStorageService.parseNodes()` is shared by both the legacy Tasks subsystem and `ProjectsScreen`. No YAML frontmatter; `parseNodes()` is pure (call only after `loadLines()`); `_collapsed` is session-only, never persist; `deleteBlock` hard-deletes with no trash; completing a root block calls `toggleBlockAndReorder`, which moves it to end-of-file; root blocks drag-reorderable via `reorderRootBlocks`. Do not add due dates, reminders, or notifications. Full details: [docs/tasks.md](docs/tasks.md).

**Grokipedia** — never writes to vault; no caching; state (`_grokArticle`, `_grokSearched`, `_grokSummaryExpanded`, `_grokSummaryFetching`, `_grokFetchedSummary`) lives only in `_EntityScreenState`.

**Books** — canonical semantic containers enriched by multiple independent sources. Schema: `type: book`, `alias`, `authors`, `hardcover_id`, `readwise_id`, `isbn`; books do NOT participate in entity graph yet; lazy migration from `type: book_highlights` on first load; field ownership strictly partitioned (Readwise owns `readwise_id`/`num_highlights`/`last_highlight_at`; Hardcover owns `hardcover_id`/`status`/`rating`/`started_at`/`finished_at`); `BookStorageService.patchFields()` is the minimal-patch primitive — all enrichment writes call through it. `appendReaderaHighlights()` is the ReadEra highlight append primitive. Full details: [docs/books.md](docs/books.md).

**Readwise** — token in `integrations.md` via `IntegrationsConfigService`; patches only Readwise-owned fields; re-import appends only new `^rw{id}` highlight blocks, never overwrites. Full details: [docs/readwise.md](docs/readwise.md).

**ReadEra** — import-only; parses `.bak` (ZIP archive containing `library.json`); merges highlights into canonical `Books/*.md` via `BookStorageService.appendReaderaHighlights()`; dedup anchor `^re{uuid}` in `## Highlights (ReadEra)` section; reconciles by title slug (no ISBN in ReadEra exports); no vault config required. Full details: [docs/readera.md](docs/readera.md).

**Hardcover** — bidirectional sync via GraphQL; explicit sync only via `HardcoverSyncService.sync()` (no background); two-pass: HC→MD then MD→HC; identity reconciliation prevents duplicate files. `HardcoverScreen` is a tab (not a pushed route); `HardcoverScreenState` is public so `HomeScreen` can drive sync and search via `GlobalKey`. Token in `integrations.md` via `IntegrationsConfigService`. Critical API quirks (me-as-List, cached_contributors-as-scalar, no isbn_13): [docs/books.md § API quirks](docs/books.md).

**RSS ingestion** — architecture: `RssFetchService` (HTTP+XML → `List<RssEntry>`) → `RssAdapter` → storage, dispatched by `RssIngestionService`. Adapters: `LetterboxdAdapter` (→ vault root; bypasses `MarkdownStorageService`), `SubstackAdapter`/`GenericAdapter` (→ `Interesting/Articles/` via `ArticleStorageService`). Feed configs in `Interesting/System/integrations.md` via `IntegrationsConfigService`. Identity dedup: guid > normalized URL > normalized title. Explicit sync only. To add a source type: add to `RssFeedType`, implement `RssAdapter`, wire in `RssIngestionService._adapterFor()`.

**Resurface / Notes** — `ResurfaceService` is read-only (never writes); `NoteEditScreen` writes directly to the vault file path it receives (see Write paths). Scans vault via `getAllNotes()` for all `.md` files; `isProblemNote: true` when a `***` horizontal-rule separator is found outside code fences; `_problemNotes` (type `List<ProblemNote>`) is derived from `_allNotes` at load time (single scan, two projections). `splitFrontmatter()` strips YAML before scanning so frontmatter `---` delimiters are invisible to the extractor. Excluded folders configured in `integrations.md` via `IntegrationsConfigService` (default: `Interesting`, `.obsidian`, `Templates`, `Attachments`). The `***` separator is chosen over `---` to avoid visual ambiguity with YAML frontmatter delimiters. Deck metadata: optional `deck:` frontmatter field (scalar or YAML list); parsed via `parseDeckMetadata()` in `md_utils.dart`; deck filter is session-state only — never persisted. Inline search matches filename and body text across all vault notes (not just problem notes); session-state only. `NoteEditScreen` preserves frontmatter verbatim; structured mode writes `front\n\n***\n\nback`; plain mode writes body as-is; full edit writes raw file. **Deck list layout:** All Notes hero card (surface, `borderMid` border, problem note count) → named DECKS section → BROWSE NOTES section (all `_allNotes`, not just problem notes). Card viewer renders front/back in IBM Plex Serif. Do NOT add scheduling, review history, due dates, FSRS, deck databases, or any persistent card state. Do NOT add note creation. Full details: [docs/resurface.md](docs/resurface.md).

**Review log** — `ReviewLogService` is the sole writer of `Interesting/System/review_log.md`; stores per-note boost/activation state and graph scores as nested YAML (a `settings:` map and a `reviews:` list). Read by `GraphScoringService` and `ResurfaceScreenState`. Uses a manual YAML serializer (not `buildFrontmatterBlock`) because the nested structure the flat builder cannot express. Do NOT migrate `_serialize()` to `buildFrontmatterBlock`. Do NOT add other writers.

**Bookmarks** — write via `XBookmarkStorageService` → vault root; fetch pipeline: nitter (3 hardcoded instances) → syndication API → oEmbed → degraded; `_cleanBody` strips oEmbed attribution tails; `truncated: true` in frontmatter when full text unavailable (oEmbed fallback or all failed); note body uses `***` Resurface separator with empty front side; filenames preserve spaces and capitalisation (no slugify); `XBookmarkService.fetchMetadata` never throws. No screen, no scheduler, no re-fetch. Full details: [docs/bookmarks.md](docs/bookmarks.md).

**Home dashboard** — `HomeDashboardScreen` is tab 0 in the 4-tab shell. Loads data from `ResurfaceService.getAllNotes()` (for problem note count, first problem note's front, recent notes) and from the entities passed in as constructor parameters. **Card peek hero** shows the top-priority problem note's front text (IBM Plex Serif 17px) from `GraphScoringService.sortByPriority()`. **Worth Revisiting** sorts entities by `(score × 0.4) + (daysSinceUpdated × 0.6)`, capped at 3 rows. **Persistent FAB** opens `showQuickAddSheet`. The screen is stateful; `HomeDashboardScreenState.reload()` is called externally after entity mutations to refresh the Worth Revisiting list. Do NOT add per-user statistics, streaks, or scheduling logic here.

**Navigation shell** — `home_screen.dart` is a 4-tab `BottomNavigationBar` shell (0=Home, 1=Notes, 2=Entities, 3=Projects). Tab titles and AppBar actions are computed per-tab. FAB shows on tab 2 (Entities → Quick Add Sheet) and tab 3 (Projects → new project). Double-tapping tab 1 calls `ResurfaceScreenState.resetStack()`.

**Sources Inbox** — `sources_screen.dart` is the full sources hub, pushed from the `sensors` AppBar icon. Six rows: Hardcover, Articles, Readwise, Bookmarks, Obsidian, AnkiDroid. "Sync all" button triggers per-source sync where available. Obsidian row fires `obsidian://` URI. No state, no lifecycle hooks.

**Obsidian launch** — moved from AppBar action to Sources Inbox row. Fires `obsidian://` URI, returns. No sync logic, no state, no lifecycle hooks.

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
