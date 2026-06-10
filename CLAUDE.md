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
| Modifying Recent Notes in the deck list | `lib/features/resurface/screens/resurface_screen.dart` (`_buildDeckList`) |
| Modifying the Quick Add Sheet | `lib/shared/widgets/quick_add_sheet.dart` |
| Modifying UI tokens, typography, or color palette | [docs/ui.md](docs/ui.md), then `app_theme.dart` + `app_text_styles.dart` |
| Modifying the Sources Inbox | `lib/screens/sources_screen.dart` |

---

## Architectural invariants

These five rules define the system's identity. Violating any changes what it fundamentally is.

**1. Markdown is the database.**
No SQLite, no parallel JSON persistence alongside `.md` files. WHY: dual-truth corrupts silently — when two stores diverge, there is no canonical answer.

**2. An entity is a note with `collection:`.**
Discovery keys on the `collection:` frontmatter key alone (`EntityFileParser.isEntityFrontmatter`). `alias`, `category`, and body shape are orthogonal to entity-ness. WHY: `category:` is a Problem-Note property (the Anki deck); keying entity discovery on it conflated the two sets and caused the June 2026 corruption. Enforcement: `isEntityFrontmatter` in `entity_file_parser.dart`, used by every scan in `markdown_storage_service.dart`.

**3. The app patches frontmatter, never the body.**
Entity writes go through `EntityFileWriter.patchFrontmatter` (owned keys only: `collection`, `tags`, `score`, `updated_at`) or `buildNewEntity`; the existing body is preserved byte-for-byte. No code path rewrites an entity body. WHY: rebuilding bodies destroyed user content (including a Problem Note's `***` front/back). The body — prose, `***`, `[[wikilinks]]`, user `##` sections — is the user's; it is edited only via `NoteEditScreen`. Enforcement: `entity_file_writer.dart`.

**4. Problem Note and Entity are orthogonal sets.**
Problem Note ⟺ `***` in body (Anki-syncable; deck = `category:`, default `Default`). Entity ⟺ `collection:` in frontmatter. A note may be both. WHY: conflating them is exactly what corrupted notes in June 2026. Enforcement: `splitFrontBack` (`ResurfaceService`) and `isEntityFrontmatter` (`EntityFileParser`) are independent predicates — never gate one on the other.

**5. Full-body wikilink scan.**
`extractWikilinks(body)` scans the whole Markdown body. WHY: narrowing the scan makes link relationships location-dependent — moving a `[[link]]` between sections silently drops it. Enforcement: `ResurfaceService.getBacklinks` (the backlinks panel) and `EntityFileParser.parseEntityFile`. There is no stored or in-memory edge list — "what links here" is computed live by `BacklinksSection`.

## Service standard

All services are **all-static, all-catch-null, never throw**. Errors surface via return values (`String?` error, `ImportResult.error`, or `null`) — never exceptions. This applies to: `TaskStorageService`, `BookStorageService`, `ReadwiseService`, `HardcoverService`, `RssFetchService`, `RssFeedStorageService`, `RssIngestionService`, `ArticleStorageService`, `IntegrationsConfigService`, `ReaderaParser`, `ReaderaIngestionService`, `ResurfaceService`, `AnkiDroidService`, `ProjectStorageService`.

## Save semantics

- **Per-file writes only.** Each mutation touches exactly one entity file; there is no bulk "save all" path (that pattern caused the June 2026 corruption).
- **Frontmatter edit** (collection, tags, score) in `EntityScreen` edit mode → `_saveEdit()` → `MarkdownStorageService.saveEntity(entity)`, which patches that one file's frontmatter and preserves its body. `Cancel` restores the pre-edit snapshot in memory (no I/O).
- **Body edit** is delegated to `NoteEditScreen` (launched from `EntityScreen`), which writes the file directly. The app never edits an entity body through the entity layer.
- **New entity**: `saveEntity` creates a file with **only `collection:` frontmatter** and an **empty body** — no imposed `# Name`, no body structure, **no timestamps** — at vault root, then sets `Entity.sourcePath`. An entity needs nothing but a `collection:` key. **Delete**: `deleteEntity` removes that one file. **Collection rename**: `renameCollection` patches each member file, then reloads.
- The app neither requires nor stamps `created_at`/`updated_at`; if a note already has them they are preserved, never added.
- **Connections are backlinks, not a stored graph**: `[[wikilinks]]` in a body render as tappable links (forward) and `BacklinksSection` lists notes that link here (incoming). Both are computed live — no UI to create a link, no persisted edge list.

## Write paths

Each canonical storage service owns exactly one directory. Nothing writes outside its directory.

| Storage layer | Directory |
|---|---|
| `MarkdownStorageService` | vault root (entities = notes with `collection:`; per-file frontmatter patch via `saveEntity`, body never rewritten; see [docs/entities.md](docs/entities.md) § Entity discovery) |
| `LetterboxdAdapter` | `Interesting/Articles/` via `ArticleStorageService` |
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
| Entity | `collection:` presence = membership; graph identity = note name (filename); `alias:` optional, used as `id` when present else filename slug | filename can change | Hard (delete the file) |
| Problem note (AnkiDroid) | `anki_note_id` (frontmatter) | Written on first sync; stable | Hard |
| Book | `alias` (frontmatter) | Stable | Hard |
| Article | `alias` (frontmatter); GUID as dedup key | Stable | Hard |
| Task file | None | — | Hard |


## Shared utilities — do not duplicate

- **Markdown parsing and YAML serialization** — `lib/shared/markdown/md_utils.dart` (pure, no I/O): frontmatter splitting, section parsing, wikilink extraction, `slugify`, `sanitizeFilename`, timestamp helpers, `buildFrontmatterBlock(fields, knownOrder)` (canonical YAML frontmatter builder — pass a field map and an ordered key list; handles scalar quoting, YAML lists, and unknown-key overflow). Never reimplement in services or screens.
- **Note identity** — `noteKey(filePathOrFilename)` in `md_utils.dart` (lowercase basename without extension) is the canonical note identity. Every traversal-log entry, graph node, and priority-map key uses it; lookups with ad-hoc `basenameWithoutExtension(...)` (case-preserved) against `noteKey`-keyed maps silently miss capitalized filenames — this exact bug occurred twice. Apply `noteKey` only to paths/filenames (it strips after the last dot), never to bare wikilink targets — lowercase those directly.
- **Vault iteration** — `VaultScanner.scan(basePath, excludedFolders:, recursive:)` in `lib/shared/markdown/vault_scanner.dart` is the sole `Directory.list` site; every `.md` scan (recursive vault scan or flat directory listing) goes through it. `lib/shared/markdown/md_io.dart` holds only `patchFrontmatterField` (surgical single-field frontmatter patch; used for `anki_note_id` write-back).
- **UI primitives** — `lib/shared/widgets/`: `showInputDialog()`, `showConfirmDialog()`, `showBottomSheetMenu()`, `showQuickAddSheet()`, `showSnack()`, `SectionHeader`, `EmptyState`, `LoadingState`, `InlineSpinner`, `ErrorRetryState`, `AppFab`, `SelectChip`, `ListRow`, `BusyButton`, `AccentButton`, `WikilinkText`. Enforcement: never inline `AlertDialog+TextField`, raw `showModalBottomSheet`, direct `ScaffoldMessenger.of(context).showSnackBar`, raw `FloatingActionButton`, `Center(child: CircularProgressIndicator())`, or a hand-built bottom-bordered tappable row — each has its primitive. Screen bodies have exactly three placeholder states: `LoadingState`, `EmptyState`, `ErrorRetryState`.
- **Date display** — `lib/shared/utils/date_format.dart`: `formatRelative(msEpoch)`, `formatMonthDay`, `formatMonthDayYear`. The month-abbreviation table lives only here.
- **Shared note view** — `lib/shared/widgets/note_markdown.dart` (`noteMarkdownBody` / `noteMarkdownStyle` / `onNoteLinkTap` — render Markdown with tappable `[[wikilinks]]`) and `backlinks_section.dart` (`BacklinksSection` — async "what links here" panel). Every note viewer (`EntityScreen`, `NoteDetailScreen`, `ResurfaceScreen`) builds on these; never reimplement Markdown/wikilink/backlink rendering. `NoteDetailScreen` is the special case that adds tap-to-reveal of the `***` back side.
- **Quick Add Sheet** — `lib/shared/widgets/quick_add_sheet.dart`: `showQuickAddSheet(context, entities:, collections:, storage:, onCreated:, initialCollection?)`. Has a **free-text Collection field** (existing collections shown as quick-fill chips) — any value creates/uses a collection, so the first collection is born here; nothing is hardcoded. Requires both a name and a collection. Creates the file via `storage.saveEntity`; persists last-used collection in `SharedPreferences` key `last_used_collection`.
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

**AnkiDroid** — one-way push only (vault → AnkiDroid); only `anki_note_id` written back to frontmatter; a Problem Note is any note with `***` in its body; deck from `category:` field (default `Default`); review history never written to Markdown. Full details: [docs/ankidroid.md](docs/ankidroid.md).

**Projects** — unified semantic workspaces replacing Lists + Todos. New project files land in `Interesting/Projects/`. On first `ProjectStorageService.loadAll()`, existing files in `Lists/` and `Tasks/` are migrated to `Projects/` (best-effort, idempotent). Detail screen is always `TaskFileScreen`. No due dates, priorities, or scheduling. Full details: [docs/projects.md](docs/projects.md).

**Tasks (parser)** — `TaskStorageService.parseNodes()` is shared by both the legacy Tasks subsystem and `ProjectsScreen`. No YAML frontmatter; `parseNodes()` is pure (call only after `loadLines()`); `_collapsed` is session-only, never persist; `deleteBlock` hard-deletes with no trash; completing a root block calls `toggleBlockAndReorder`, which moves it to end-of-file; root blocks drag-reorderable via `reorderRootBlocks`. Do not add due dates, reminders, or notifications. Full details: [docs/tasks.md](docs/tasks.md).

**Grokipedia** — never writes to vault; no caching; state (`_grokArticle`, `_grokSearched`, `_grokSummaryExpanded`, `_grokSummaryFetching`, `_grokFetchedSummary`) lives only in `_EntityScreenState`.

**Books** — canonical semantic containers enriched by multiple independent sources. Schema: `type: book`, `alias`, `authors`, `hardcover_id`, `readwise_id`, `isbn`; books do NOT participate in entity graph yet; lazy migration from `type: book_highlights` on first load; field ownership strictly partitioned (Readwise owns `readwise_id`/`num_highlights`/`last_highlight_at`; Hardcover owns `hardcover_id`/`status`/`rating`/`started_at`/`finished_at`); `BookStorageService.patchFields()` is the minimal-patch primitive — all enrichment writes call through it. `appendReaderaHighlights()` is the ReadEra highlight append primitive. Full details: [docs/books.md](docs/books.md).

**Readwise** — token in `integrations.md` via `IntegrationsConfigService`; patches only Readwise-owned fields; re-import appends only new `^rw{id}` highlight blocks, never overwrites. Full details: [docs/readwise.md](docs/readwise.md).

**ReadEra** — import-only; parses `.bak` (ZIP archive containing `library.json`); merges highlights into canonical `Books/*.md` via `BookStorageService.appendReaderaHighlights()`; dedup anchor `^re{uuid}` in `## Highlights (ReadEra)` section; reconciles by title slug (no ISBN in ReadEra exports); no vault config required. Full details: [docs/readera.md](docs/readera.md).

**Hardcover** — bidirectional sync via GraphQL; explicit sync only via `HardcoverSyncService.sync()` (no background); two-pass: HC→MD then MD→HC; identity reconciliation prevents duplicate files. `HardcoverScreen` is a tab (not a pushed route); `HardcoverScreenState` is public so `HomeScreen` can drive sync and search via `GlobalKey`. Token in `integrations.md` via `IntegrationsConfigService`. Critical API quirks (me-as-List, cached_contributors-as-scalar, no isbn_13): [docs/books.md § API quirks](docs/books.md).

**RSS ingestion** — architecture: `RssFetchService` (HTTP+XML → `List<RssEntry>`) → `RssAdapter` → storage, dispatched by `RssIngestionService`. Adapters: `LetterboxdAdapter` (→ vault root; bypasses `MarkdownStorageService`), `SubstackAdapter`/`GenericAdapter` (→ `Interesting/Articles/` via `ArticleStorageService`). Feed configs in `Interesting/System/integrations.md` via `IntegrationsConfigService`. Identity dedup: guid > normalized URL > normalized title. Explicit sync only. To add a source type: add to `RssFeedType`, implement `RssAdapter`, wire in `RssIngestionService._adapterFor()`.

**Resurface / Notes** — `ResurfaceService` is read-only (never writes); `NoteEditScreen` writes directly to the vault file path it receives (see Write paths). Scans vault via `getAllNotes()` for all `.md` files; `isProblemNote: true` when a `***` horizontal-rule separator is found outside code fences; `_problemNotes` (type `List<ProblemNote>`) is derived from `_allNotes` at load time (single scan, two projections). `splitFrontmatter()` strips YAML before scanning so frontmatter `---` delimiters are invisible to the extractor. Excluded folders configured in `integrations.md` via `IntegrationsConfigService` (default: `Interesting`, `.obsidian`, `Templates`, `Attachments`). The `***` separator is chosen over `---` to avoid visual ambiguity with YAML frontmatter delimiters. Deck metadata: optional `deck:` frontmatter field (scalar or YAML list); parsed via `parseDeckMetadata()` in `md_utils.dart`; deck filter is session-state only — never persisted. Inline search matches filename and body text across all vault notes (not just problem notes); session-state only. `NoteEditScreen` preserves frontmatter verbatim; structured mode writes `front\n\n***\n\nback`; plain mode writes body as-is; full edit writes raw file. **Deck list layout:** All Notes hero card (surface, `borderMid` border, problem note count) → named DECKS section → RECENT NOTES section (top-2 most recently modified vault notes, sorted by filesystem `stat.modified`). Card viewer renders front/back in IBM Plex Serif. Do NOT add scheduling, review history, due dates, FSRS, deck databases, or any persistent card state. Do NOT add note creation. Full details: [docs/resurface.md](docs/resurface.md). **Both-note routing (has `collection:` AND `***`):** `***` takes priority — opens in the card viewer; the `isProblemNote` check always runs before the entity check. Collection membership remains visible via `BacklinksSection` regardless of which viewer opens. `ResurfaceScreenState.openNoteByPath(filePath)` is the canonical router (problem note → card viewer; `collection:` only → `onOpenEntity` callback → EntityScreen via HomeScreen; plain note → NoteDetailScreen). Every open-note path — wikilink tap, search result, Recent Notes row, deep link, EntityScreen's `onOpenNoteByPath` callback — converges on its routing decision (`_routeNote`); `ResurfaceNote.hasCollection` (set from `isEntityFrontmatter` at parse time) carries the entity check so no path re-reads frontmatter or duplicates the predicate. `EntityScreen`'s in-memory wikilink fast path reads the target body and hands both-notes to `onOpenNoteByPath` before opening EntityScreen. **Sole exception:** the Collections tab list opens EntityScreen directly (it is the entity-browsing surface, not a router path) — without it, a both-note's `collection`/`tags`/`score` would have no structured editor.

**Review log** — `TraversalLogService` is the sole writer of `Interesting/System/review_log.md`; stores per-note boost/activation state and graph scores as nested YAML (a `settings:` map and a `reviews:` list). Read by `GraphScoringService` and `ResurfaceScreenState`. Uses a manual YAML serializer (not `buildFrontmatterBlock`) because the nested structure the flat builder cannot express. Do NOT migrate `_serialize()` to `buildFrontmatterBlock`. Do NOT add other writers. YAML keys (`last_reviewed`, `is_star`) are preserved for backward compatibility with existing vault files; the internal Dart field uses `lastTraversed`.

**Bookmarks** — write via `XBookmarkStorageService` → vault root; fetch pipeline: nitter (3 hardcoded instances) → syndication API → oEmbed → degraded; `_cleanBody` strips oEmbed attribution tails; `truncated: true` in frontmatter when full text unavailable (oEmbed fallback or all failed); note body uses `***` Resurface separator with empty front side; filenames preserve spaces and capitalisation (no slugify); `XBookmarkService.fetchMetadata` never throws. No screen, no scheduler, no re-fetch. Full details: [docs/bookmarks.md](docs/bookmarks.md).

**Navigation shell** — `home_screen.dart` is a 3-tab `BottomNavigationBar` shell (0=Notes, 1=Collections, 2=Projects). Tab 1 (label `COLLECTIONS`) is the renamed Entities tab — same code, user-facing pivot toward Collections; the internal model is still `Entity` (a note that is a member of a collection). Tab titles and AppBar actions are computed per-tab. FAB shows on tab 1 (Collections → Quick Add Sheet) and tab 2 (Projects → new project). Double-tapping tab 0 calls `ResurfaceScreenState.resetStack()`.

**Sources Inbox** — `sources_screen.dart` is the full sources hub, pushed from the `sensors` AppBar icon. Six rows: Hardcover, Articles, Readwise, Bookmarks, Obsidian, AnkiDroid. "Sync all" button triggers per-source sync where available. Obsidian row fires `obsidian://` URI. No state, no lifecycle hooks.

**Obsidian launch** — moved from AppBar action to Sources Inbox row. Fires `obsidian://` URI, returns. No sync logic, no state, no lifecycle hooks.

**Android widget** — reads `flutter.vault_path` directly from `FlutterSharedPreferences`; writes `collection: Quick Capture` (entity membership — Collections-tab visible) AND `category: Default` (AnkiDroid deck mapping) — both required, orthogonal; new notes land at vault root with the app's collision scheme (`Name 2.md`, `Name 3.md`, …); only three concrete subclasses registered as receivers.

**State management** — `setState` only. No `Provider`, `Riverpod`, `Bloc`.

**Sorting** — all entity list sorting routes through `MarkdownStorageService.sortEntities(entities, sortOrder)`. Add new sort options there first, then `DropdownMenuItem` entries in screens. Entity pickers are pre-sorted A→Z inline (not via `sortEntities`).

**Entity model** — `Entity` is a thin projection over a note's frontmatter: `id` (alias or filename slug), `name` (filename), `collection`, `tags`, `score`, `sourcePath` (plus in-memory `createdAt`/`updatedAt` for sort, defaulted to load time when the file omits them — never written back). It carries no body content — the body is read on demand from `sourcePath` and rendered via the shared `noteMarkdownBody`. The app owns only `EntityFileWriter._knownOrder` (`collection`, `alias`, `tags`, `score`); any other frontmatter key (`category`/deck, `anki_note_id`, `up`, user keys) is preserved untouched on save.

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
