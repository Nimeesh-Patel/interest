Focus on creating better and better abstractions, such that the implementation keeps becoming more elegant and hard-to-vary. And also encode error-correcting institutions and mechanisms into the code.

# Project

Filesystem-native semantic knowledge layer. All data lives as Markdown files in a user-chosen vault. The app patches files it co-owns; it does not rebuild or replace them. Full architectural rationale: [README.md](README.md). This file states constraints, their enforcement points, and why they exist — organized for agents making code changes.

## Architectural invariants

These five rules define the system's identity. Violating any of them changes what the system fundamentally is.

**1. Markdown is the database.**
No SQLite, no parallel JSON persistence alongside `.md` files. WHY: dual-truth corrupts silently — when two stores diverge, there is no canonical answer.

**2. `alias` is immutable after creation.**
`entity.id == alias` for all EntityLinks. Never regenerate on rename. WHY: filenames change on rename; alias is the stable graph identity — regenerating it orphans every link. Enforcement: `_saveEdit()` in `entity_screen.dart`.

**3. Patch-not-rebuild.**
Existing entity files are always patched via `_patchEntityContent()`, never regenerated from template. WHY: rebuilding from entity data destroys user's custom `##` sections on every save. Enforcement: `markdown_storage_service.dart`.

**4. Semantic section registry is the app/user boundary.**
Only keys in `_semanticSections` (`Why Interesting`, `Related`, `Sources`) are rewritten on save. Do not add hardcoded section names outside this map. WHY: any name outside the map bypasses the user-territory contract and risks erasing user prose. Enforcement: `_semanticSections` const in `markdown_storage_service.dart`.

**5. Full-body wikilink scan.**
`extractWikilinks(body)` scans the whole Markdown body, not just `## Related`. WHY: narrowing the scan makes graph edges location-dependent — moving a link between sections would silently drop a graph edge. Enforcement: `_parseEntityFile` in `markdown_storage_service.dart`.

## Save semantics

- **No auto-save for core entity fields** (name, category, tags, score, notes, links). Save is deferred to the explicit Save button via `_saveEdit()`. WHY: Cancel must restore the pre-edit snapshot atomically; any auto-save during editing makes the pre-edit state unrecoverable.
- **Immediate save for join-table mutations** (`_createEntityLink`, `_deleteEntityLink`) and list mutations (`_addToList`, `_removeFromList`). WHY: they mutate shared lists the entity snapshot does not cover.
- `saveData()` snapshots all entity lists before the async gap to prevent partial-save races.
- `updated_at` stamped on every entity mutation inside `_save()` in `entity_screen.dart`.
- Anki card `updated_at` stamped inside `AnkiStorageService.saveCard()` and `createNewCard()`.

## Write paths

Each service owns exactly one directory. No service writes outside its directory.

| Service | Writes to |
|---|---|
| `MarkdownStorageService.saveData()` | `Interesting/Entities/` |
| `ListStorageService` | `Interesting/Lists/` |
| `LetterboxdService` | `Interesting/Entities/` (bypasses `saveData()`; see README § Subsystems) |
| `AnkiStorageService` | `Interesting/Anki/` + `Interesting/Anki/.trash/` |
| `TaskStorageService` | `Interesting/Tasks/` |
| `BookStorageService` | `Interesting/Books/` — canonical book file I/O |
| `ReadwiseService` | `Interesting/Books/` via `BookStorageService` only |
| `HardcoverSyncService` | `Interesting/Books/` via `BookStorageService` only |
| `VaultService.ensureVaultDirectories()` | creates all subdirs + seeds templates on first launch |

## Identity anchors

- **Entity**: `alias` (frontmatter) = `entity.id`. Immutable after creation.
- **Anki card**: `anki_id` (frontmatter). Immutable after first sync to Anki. Soft-delete only — a hard-deleted card re-synced would be recreated from Anki with a new id, breaking the identity chain.
- **List**: `slugify(list.name)` derived at load time. Not identity-bearing across renames.
- **Task file**: no identity anchor. Hard-delete permitted. Cannot participate in the `EntityLink` graph.

## Shared utilities — do not duplicate

- **All Markdown parsing** lives in `lib/shared/markdown/md_utils.dart` (pure, no I/O): frontmatter splitting, section parsing, wikilink extraction, slugify, sanitizeFilename, timestamp helpers. Never reimplement in services or screens.
- **All reusable dialogs and UI primitives** live in `lib/shared/widgets/`: `showInputDialog()`, `showConfirmDialog()`, `showBottomSheetMenu()`, `SectionHeader`, `EmptyState`, `WikilinkText`. Never inline `AlertDialog+TextField` or `showModalBottomSheet` patterns.
- **Spacing constants** live in `lib/shared/constants/app_spacing.dart`: `kFabListBottomPad` (88.0 — bottom padding for lists behind a FAB), `kScreenHPad` (16.0 — standard horizontal body padding). Use these instead of magic numbers.
- **All canonical book file I/O** goes through `lib/features/books/services/book_storage_service.dart`: identity reconciliation, `patchFields()`, `createBook()`. Never write to `Interesting/Books/` directly from `ReadwiseService` or `HardcoverSyncService`.

## Subsystem constraints

**Anki** — `anki_id` immutable; soft-delete only (`.trash/`); sync manual only (no background polling); review metadata (intervals, ease, due dates) never written to Markdown; `AnkiConnectService` all-static, all-catch-null, never throws. Full details: [docs/anki.md](docs/anki.md).

**Lists** — `ListStorageService` all-static, all-catch-null, never throws; writes to `Interesting/Lists/` only; items are arbitrary text strings (may contain `[[wikilinks]]`); item order in file = semantic order; `saveList` rebuilds the file from items (safe — list files have no user prose sections); entity membership inferred by wikilink scan, no join table. Do not add due dates, reminders, priorities, or subtasks to list items.

**Tasks** — no YAML frontmatter; `parseNodes()` is pure (call only after `loadLines()`, never from `loadTaskFiles()`); `_collapsed` is session-only, never persist to file or SharedPreferences; `deleteBlock` is hard-delete with no trash; task wikilinks are preserved verbatim but not wired into `EntityLink` graph; completing a root block calls `toggleBlockAndReorder` which moves it to end-of-file; root blocks support drag reorder via `reorderRootBlocks` (mutates file order); do not add due dates, reminders, priorities, or notifications. Full details: [docs/tasks.md](docs/tasks.md).

**Grokipedia** — all-static, all-catch-null; never writes to vault; no caching; state (`_grokArticle`, `_grokSearched`, `_grokSummaryExpanded`, `_grokSummaryFetching`, `_grokFetchedSummary`) lives only in `_EntityScreenState`.

**Books** — canonical semantic objects in `Interesting/Books/`; schema: `type: book`, `alias` (immutable), `authors` (list), plus identity anchors `hardcover_id` / `readwise_id` / `isbn` (isbn not populated by HC — see books.md § API quirks); `alias` is stable but books do NOT participate in entity graph yet; lazy migration from `type: book_highlights` on first load; field ownership is strictly partitioned (see [docs/books.md](docs/books.md)); `BookStorageService.patchFields()` is the minimal-patch primitive — all enrichment services call through it.

**Readwise** — `ReadwiseService` all-static, all-catch-null, never throws; token in SharedPreferences (key `readwise_access_token`); writes to `Interesting/Books/` only via `BookStorageService` (never directly); patches only Readwise-owned fields (`readwise_id`, `num_highlights`, `last_highlight_at`); re-import appends only new `^rw{id}` highlight blocks, never overwrites; no auto-sync, no background polling. Full details: [docs/readwise.md](docs/readwise.md).

**Hardcover** — `HardcoverService` all-static, all-catch-null, never throws; token in SharedPreferences (key `hardcover_api_token`); GraphQL endpoint `https://api.hardcover.app/v1/graphql`; auth `Bearer {token}`; explicit sync only via `HardcoverSyncService.sync()` (no background); patches only Hardcover-owned fields (`hardcover_id`, `status`, `rating`, `started_at`, `finished_at`); bidirectional: HC→MD in pass 1, MD→HC in pass 2; identity reconciliation prevents duplicate files. `testConnection` returns `String?` (null=ok); `fetchUserBooks` returns `(List<HardcoverBook>?, String?)` so sync errors are surfaced. `HardcoverScreen` is the middle tab of `HomeScreen` bottom nav (not a pushed route); its state class is public (`HardcoverScreenState`) so `HomeScreen` can drive sync and search via `GlobalKey`. Critical API quirks (me-as-List, cached_contributors-as-scalar, no isbn_13 on books type): [docs/books.md § API quirks](docs/books.md). Full details: [docs/books.md](docs/books.md).

**Obsidian launch ergonomics** — UI-only AppBar action in `home_screen.dart`; fires `obsidian://` URI via `url_launcher` and returns; no sync logic, no background behavior, no state. Do not add polling, sync detection, or lifecycle hooks.

**Android widget** — reads `flutter.vault_path` directly from `FlutterSharedPreferences` (no Flutter API available at runtime); always writes `category: Default`; uses `default.md` body structure only; only three concrete subclasses are registered as receivers (never the abstract base).

**State management** — `setState` only. No `Provider`, `Riverpod`, `Bloc`, or any state management library.

**Sorting** — all entity list sorting routes through `MarkdownStorageService.sortEntities(entities, sortOrder)`. Add new sort options there first, then add `DropdownMenuItem` entries in screens. Entity/board pickers are pre-sorted A→Z inline (not via `sortEntities`).

**Entity movie fields** — `Entity` has three optional movie-specific fields: `watchedDate`, `letterboxdUrl`, `tmdbId`. Adding new category-specific fields requires updating both `_parseEntityFile` and `_buildFrontmatter` in `markdown_storage_service.dart`.

## Mobile UX conventions

Full reference: [docs/mobile_ux.md](docs/mobile_ux.md). Enforcement rules:

- Every `Scaffold` body: wrap in `SafeArea(top: false)` (AppBar handles top; SafeArea handles gesture nav bar bottom)
- Every list behind a FAB: `padding: const EdgeInsets.only(bottom: kFabListBottomPad)`
- Scrollable search sheets (`isScrollControlled: true`): use `screenHeight * fraction` for SizedBox height, never fixed pixels
- Every `TextField`: declare `textInputAction` (`next` / `done` / `newline` / `send`)

## When to update documentation

Update `README.md` and `CLAUDE.md` when:
- A new subsystem or write path is added
- A key is added to `_semanticSections`
- An architectural invariant changes
- A new identity anchor pattern is introduced

Do not update for: UI layout changes, new sort options, dependency version bumps, or internal refactors that preserve external behavior.

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