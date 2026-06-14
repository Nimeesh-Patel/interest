Focus on creating progressively better abstractions: implementation should become more elegant and hard-to-vary over time. Encode error-correcting mechanisms into the code.

# Project

Filesystem-native companion to an Obsidian vault. All data lives as Markdown files in a user-chosen vault. The app does three narrow things: **Collections** (notes grouped by `collection:`), **Projects** (todo workspaces), and a **one-way Anki sync** (push `***` problem notes to Anki, triggered by the `interest://sync-anki` deep link from the companion *Problem Notes* Obsidian plugin). Note viewing, editing, backlinks, and `[[wikilink]]` traversal live in **Obsidian**, not here. The app patches frontmatter on files it co-owns; it does not rebuild or replace bodies. Architectural rationale: [README.md](README.md). This file states constraints and their enforcement points.

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
| Modifying the Anki sync (either transport) | [docs/anki.md](docs/anki.md), then `AnkiSyncService` + the `AnkiTransport` impls (`lib/features/anki/`) |
| Modifying problem-note discovery (what gets synced) | `AnkiProblemNoteScanner` (`lib/features/anki/services/`) |
| Modifying the deep-link sync trigger | [docs/anki.md](docs/anki.md) § deep-link contract, then `MainActivity.kt` + `HomeScreen._syncAnkiFromDeeplink` |
| Modifying entity files or collections | [docs/entities.md](docs/entities.md), then `MarkdownStorageService` |
| Modifying Hardcover sync / book notes | README § Books, then `HardcoverSyncService` + `BookNoteStorage` (`lib/features/hardcover/`) |
| Modifying the Projects subsystem | [docs/projects.md](docs/projects.md), then `ProjectStorageService` |
| Modifying integration config storage | CLAUDE.md § Configuration ownership, then `IntegrationsConfigService` |
| Adding a new sort option | CLAUDE.md § Sorting, then `MarkdownStorageService.sortEntities()` |
| Adding a new screen | [docs/mobile_ux.md](docs/mobile_ux.md) |
| Touching shared Markdown utilities | `lib/shared/markdown/md_utils.dart` (pure, no I/O) |
| Understanding save/cancel/snapshot semantics | CLAUDE.md § Save semantics, then `entity_screen.dart` |
| Modifying the Quick Add Sheet | `lib/shared/widgets/quick_add_sheet.dart` |
| Modifying UI tokens, typography, or color palette | [docs/ui.md](docs/ui.md), then `app_theme.dart` + `app_text_styles.dart` |
| Modifying the Sources screen | `lib/screens/sources_screen.dart` |

---

## Architectural invariants

These rules define the system's identity. Violating any changes what it fundamentally is.

**1. Markdown is the database.**
No SQLite, no parallel JSON persistence alongside `.md` files. WHY: dual-truth corrupts silently — when two stores diverge, there is no canonical answer.

**2. An entity is a note with `collection:`.**
Discovery keys on the `collection:` frontmatter key alone (`EntityFileParser.isEntityFrontmatter`). `alias`, `category`, and body shape are orthogonal to entity-ness. WHY: `category:` is a Problem-Note property (the Anki deck); keying entity discovery on it conflated the two sets and caused the June 2026 corruption. Enforcement: `isEntityFrontmatter` in `entity_file_parser.dart`, used by every scan in `markdown_storage_service.dart`.

**3. The app patches frontmatter, never the body.**
Entity writes go through `EntityFileWriter.patchFrontmatter` (owned keys only: `collection`, `tags`, `score`) or `buildNewEntity`; book-note writes go through `BookNoteStorage` (`buildFrontmatterBlock` for new notes, `patchFrontmatterField` for updates); the Anki sync writes only `anki_note_id` via `patchFrontmatterField`. In every case the existing body is preserved byte-for-byte. **No code path rewrites a note body.** WHY: rebuilding bodies destroyed user content (including a Problem Note's `***` front/back). Enforcement: `entity_file_writer.dart`, `book_note_storage.dart`, `md_io.dart`.

**4. Problem Note and Entity are orthogonal sets.**
Problem Note ⟺ `***` in body (Anki-syncable; deck = `category:`, default `Default`). Entity ⟺ `collection:` in frontmatter. A note may be both. WHY: conflating them is exactly what corrupted notes in June 2026. Enforcement: `splitFrontBack` (`AnkiProblemNoteScanner`) and `isEntityFrontmatter` (`EntityFileParser`) are independent predicates — never gate one on the other.

**5. Full-body wikilink scan.**
`extractWikilinks(body)` / `rewriteWikilinksToHtml(body, …)` scan the whole Markdown body. WHY: narrowing the scan makes link relationships location-dependent — moving a `[[link]]` between sections silently drops it. Enforcement: `EntityFileParser.parseEntityFile` and `AnkiSyncService._markdownToAnkiHtml`. There is no stored or in-memory edge list.

## The vault-write safety invariant (Anki sync)

The Anki sync's **only** vault write is `AnkiSyncService._patchAnkiNoteId` → `patchFrontmatterField`, which writes the `anki_note_id` frontmatter key and preserves the body verbatim. No sync code opens or writes any note body. A prior version destroyed note bodies by rebuilding them on save; that must never be reintroduced. The sync stack (`lib/features/anki/`) is self-contained and depends on no viewer.

## Service standard

All services are **all-static, all-catch-null, never throw**. Errors surface via return values (`String?` error, a result object's `error`, or `null`) — never exceptions. This applies to: `MarkdownStorageService`, `TaskStorageService`, `ProjectStorageService`, `IntegrationsConfigService`, `AnkiProblemNoteScanner`, `AnkiSyncService`, `AnkiSyncController`, `HardcoverService`, `HardcoverSyncService`, `BookNoteStorage`. Sole sanctioned exception: `AnkiTransport` implementations may throw `AnkiSyncAbort` / `AnkiNoteFailure`, consumed only by `AnkiSyncService.syncVault` — they never escape it.

## Save semantics

- **Per-file writes only.** Each mutation touches exactly one file; there is no bulk "save all" path (that pattern caused the June 2026 corruption).
- **Frontmatter edit** (collection, tags, score) in `EntityScreen` edit mode → `_saveEdit()` → `MarkdownStorageService.saveEntity(entity)`, which patches that one file's frontmatter and preserves its body. `Cancel` restores the pre-edit snapshot in memory (no I/O).
- **There is no in-app note-body editor.** Body editing lives in Obsidian. `EntityScreen` renders the body read-only and offers "Open in Obsidian"; wikilink taps open Obsidian.
- **New entity**: `saveEntity` creates a file with **only `collection:` frontmatter** and an **empty body** — no imposed `# Name`, no timestamps — at vault root, then sets `Entity.sourcePath`. **Delete**: `deleteEntity` removes that one file. **Collection rename**: `renameCollection` patches each member file, then reloads.
- The app neither requires nor stamps `created_at`/`updated_at`; if a note already has them they are preserved, never added.

## Write paths

Each storage path co-owns specific files. Nothing rewrites a note body.

| Storage layer | Writes |
|---|---|
| `MarkdownStorageService` | vault-root entity notes (`collection:`); per-file frontmatter patch via `saveEntity`, body never rewritten |
| `BookNoteStorage` | vault-root book notes (`collection: Books`); new note via `buildFrontmatterBlock`, updates via `patchFrontmatterField` (frontmatter only) ← `HardcoverSyncService`, `HardcoverScreen` write only via this |
| `AnkiSyncService` | `anki_note_id` only, via `patchFrontmatterField` — the sole vault write of the sync (see safety invariant) |
| `ProjectStorageService` | `Interesting/Projects/` (new files); also migrates from `Lists/` + `Tasks/` |
| `TaskStorageService` | `Interesting/Tasks/` (legacy; new files no longer created here) |
| `IntegrationsConfigService` | `Interesting/System/integrations.md` — vault-native integration config |
| `TemplatesScreen` / `TemplateEditorScreen` | `Interesting/Templates/` — direct screen writes |

## Identity anchors

| Type | Anchor | Mutability | Delete |
|---|---|---|---|
| Entity | `collection:` presence = membership; identity = note name (filename); `alias:` optional, used as `id` when present else filename slug | filename can change | Hard (delete the file) |
| Problem note | `anki_note_id` (frontmatter) | Written on first sync; stable | Hard |
| Book | an entity with `collection: Books` + `hardcover_id` (dedup key); title-slug fallback for linking | filename can change | Hard |
| Task / Project file | None | — | Hard |

## Shared utilities — do not duplicate

- **Markdown parsing and YAML serialization** — `lib/shared/markdown/md_utils.dart` (pure, no I/O): frontmatter splitting, `splitFrontBack` (the `***` predicate), section parsing, wikilink extraction + `rewriteWikilinksToHtml`, `obsidianUri`/`obsidianUriForName`, `slugify`, `sanitizeFilename`, timestamp helpers, `buildFrontmatterBlock(fields, knownOrder)` (canonical YAML frontmatter builder). Never reimplement in services or screens.
- **Note identity** — `noteKey(filePathOrFilename)` in `md_utils.dart` (lowercase basename without extension) is the canonical note identity. Apply `noteKey` only to paths/filenames (it strips after the last dot), never to bare wikilink targets — lowercase those directly.
- **Vault iteration** — `VaultScanner.scan(basePath, excludedFolders:, recursive:)` in `lib/shared/markdown/vault_scanner.dart` is the sole `Directory.list` site; every `.md` scan goes through it. `lib/shared/markdown/md_io.dart` holds only `patchFrontmatterField` (surgical single-field frontmatter patch; the body-safe write primitive used for `anki_note_id` and book-note field updates).
- **UI primitives** — `lib/shared/widgets/`: `showInputDialog()`, `showConfirmDialog()`, `showBottomSheetMenu()`, `showQuickAddSheet()`, `showSnack()`, `SectionHeader`, `EmptyState`, `LoadingState`, `InlineSpinner`, `ErrorRetryState`, `AppFab`, `SelectChip`, `ListRow`, `BusyButton`, `AccentButton`, `WikilinkText`. Never inline `AlertDialog+TextField`, raw `showModalBottomSheet`, direct `ScaffoldMessenger…showSnackBar`, raw `FloatingActionButton`, `Center(child: CircularProgressIndicator())`, or a hand-built bottom-bordered tappable row. Screen bodies have exactly three placeholder states: `LoadingState`, `EmptyState`, `ErrorRetryState`.
- **Date display** — `lib/shared/utils/date_format.dart`: `formatRelative(msEpoch)`, `formatMonthDay`, `formatMonthDayYear`. The month-abbreviation table lives only here.
- **Shared note view** — `lib/shared/widgets/note_markdown.dart` (`noteMarkdownBody` / `noteMarkdownStyle` / `onNoteLinkTap` — render Markdown with tappable `[[wikilinks]]`). Used by `EntityScreen` (the only in-app note view). Wikilink taps route to Obsidian; there is no in-app backlinks panel or note-detail screen.
- **Quick Add Sheet** — `lib/shared/widgets/quick_add_sheet.dart`: `showQuickAddSheet(context, entities:, collections:, storage:, onCreated:, initialCollection?)`. Free-text Collection field (existing collections shown as chips); any value creates/uses a collection. Requires a name and a collection. Creates the file via `storage.saveEntity`; persists last-used collection in `SharedPreferences` key `last_used_collection`.
- **Text styles** — `lib/shared/constants/app_text_styles.dart`: `AppTextStyles` static getters for every named role (IBM Plex Sans/Serif). Never hardcode `GoogleFonts.ibmPlex…` inline.
- **Colors** — `lib/shared/constants/app_theme.dart` `AppColors`: all color constants including `borderMid` (#282828). No hex literals inline.
- **Spacing** — `lib/shared/constants/app_spacing.dart`: `kFabListBottomPad` (88.0), `kScreenHPad` (16.0). No magic numbers.

## Configuration ownership

Integration configuration lives in `Interesting/System/integrations.md` (vault-canonical), managed by `IntegrationsConfigService` in `lib/core/`. SharedPreferences is bootstrap/cache only:

| Key | Location | Rationale |
|---|---|---|
| `vault_path` | SharedPreferences | Must be known before vault is accessible |
| Hardcover token | `integrations.md` (`## Hardcover`) | Portable; syncs via Obsidian Sync |
| AnkiConnect URL override | `integrations.md` (`## AnkiConnect`) | Hand-edited only (no in-app editor); null = `http://127.0.0.1:8765` |
| Excluded folders (Anki scan scope) | `integrations.md` (`## Resurface`) | Portable. In-memory field is `IntegrationsConfig.excludedFolders`; the section name `## Resurface` is kept for backward compatibility with vaults written before the role change. |

Migration from SharedPreferences runs once on first load (idempotent: skipped if the file exists).

## Subsystem constraints

**Anki sync** — one-way push only (vault → Anki) over two transports: `AnkiDroidTransport` (MethodChannel → `AnkiBridge.kt` → ContentProvider, Android) and `AnkiConnectTransport` (HTTP → Anki desktop's AnkiConnect add-on, pure Dart). The whole stack is self-contained under `lib/features/anki/`. `AnkiProblemNoteScanner.scan()` finds the `***` notes to push (its own vault scan; honours the excluded-folders config and `exclude_resurface: true`) and yields slim `AnkiProblemNote`s. `AnkiSyncService` is the shared core — card rendering, `category:`→deck mapping (default `Default`, including the deck move on a category change), the `obsidian://` card-body wikilink rewrite, single-newline→`<br>` promotion (Anki HTML only), and the `anki_note_id` round-trip; transports translate the seven `AnkiTransport` operations and nothing else (`currentDeck`/`moveToDeck` no-op gracefully). Both transports require the model literally named `Basic`. Card-body `[[wikilinks]]` and the front's source link render as `obsidian://` (traversal lives in Obsidian). **Triggers:** the `interest://sync-anki` deep link and the Sources → AnkiDroid row (both AnkiDroid, foreground app), and the Sources → Anki desktop row (AnkiConnect). Full details: [docs/anki.md](docs/anki.md).

**Deep-link sync (Android)** — `interest://sync-anki` (fired by the Problem Notes plugin) is a VIEW intent on `MainActivity` (`launchMode=singleTop`): a cold start sets `pendingSyncAnki` (read once via the `getInitialSyncAnki` deeplink-channel call); a running app receives it through `onNewIntent`, which invokes `syncAnki` on the `com.nimeesh.interest/deeplink` channel. Either way the Flutter side (`HomeScreen._syncAnkiFromDeeplink`) runs `runAnkiDroidSync` → `AnkiSyncController.sync(AnkiDroidTransport())` and shows the result in a snackbar. **The app comes to the foreground — that is the intended, known-good behaviour; the sync is not headless.** `AnkiBridge` (the AnkiDroid ContentProvider bridge) is registered on `MainActivity`, which forwards `onRequestPermissionsResult` so the first-run `READ_WRITE_DATABASE` grant completes via the normal Activity flow. The same `runAnkiDroidSync` backs the Sources → AnkiDroid row (Android only), so plugin and in-app triggers behave identically. A prior iteration tried a headless foreground-service + transparent-activity trampoline; it never synced on-device and was reverted — do not reintroduce it.

**Hardcover / Books** — a book is an ordinary entity: a vault-root note with `collection: Books` + `hardcover_id` (+ `authors`/`status`/`rating` frontmatter, title/authors body), visible in the Collections tab. There is no separate Books subsystem, no `Interesting/Books/` directory, no field-partition convergence. Sync is a **one-way pull** (HC → vault): `HardcoverSyncService` fetches the library and creates (`BookNoteStorage.createBookNote`) or frontmatter-patches (`BookNoteStorage.patchFields`, body preserved) one note per book; dedup on `hardcover_id` with a title-slug fallback. `HardcoverService` keeps fetch/auth/search + `insertUserBook` (search-and-add); there is no MD→HC push. `HardcoverScreen` is pushed from the Sources screen; `HardcoverScreenState` is public so the Sources page can drive sync/search via `GlobalKey`. Token in `integrations.md`.

**Projects** — unified workspaces replacing Lists + Todos. New files in `Interesting/Projects/`; on first `ProjectStorageService.loadAll()`, existing `Lists/` + `Tasks/` files migrate (best-effort, idempotent). Detail screen is `TaskFileScreen`. No due dates, priorities, or scheduling. Full details: [docs/projects.md](docs/projects.md).

**Tasks (parser)** — `TaskStorageService.parseNodes()` powers `TaskFileScreen`. No YAML frontmatter; `parseNodes()` is pure (call only after `loadLines()`); `_collapsed` is session-only; `deleteBlock` hard-deletes; completing a root block calls `toggleBlockAndReorder` (moves to end-of-file); root blocks drag-reorderable via `reorderRootBlocks`. No due dates, reminders, or notifications. Full details: [docs/tasks.md](docs/tasks.md).

**Grokipedia** — never writes to vault; no caching; state lives only in `_EntityScreenState`.

**Navigation shell** — `home_screen.dart` is a 2-tab `BottomNavigationBar`: 0=Collections (landing), 1=Projects. `MainActivity` only hosts this UI. FAB shows on tab 0 (Collections → Quick Add Sheet) and tab 1 (Projects → new project). AppBar actions: Sources (`sensors`), and a popup (Settings, Templates, Open Obsidian).

**Sources screen** — `sources_screen.dart`, pushed from the `sensors` AppBar icon. Rows: Hardcover (pull), Obsidian (launch `obsidian://`), AnkiDroid (manual push, Android only), Anki desktop (manual AnkiConnect sync). The two Anki rows are mutually exclusive (`_ankiBusy`) — both write `anki_note_id` to the same files. The AnkiDroid row and the `interest://sync-anki` deep link share `runAnkiDroidSync`.

**Android widget** — reads `flutter.vault_path` directly; writes `collection: Quick Capture` (Collections-visible) AND `category: Default` (AnkiDroid deck) — both required, orthogonal; new notes at vault root with the app's collision scheme. Divergence from the app's new-entity model (deliberate, native-side): the widget stamps `created_at`/`updated_at` and builds a body from `Interesting/Templates/default.md` — the only code path that imposes body structure, and the only consumer of Templates.

**State management** — `setState` only. No `Provider`, `Riverpod`, `Bloc`.

**Sorting** — all entity list sorting routes through `MarkdownStorageService.sortEntities(entities, sortOrder)`. Add new sort options there first, then `DropdownMenuItem` entries in screens. Entity pickers are pre-sorted A→Z inline.

**Entity model** — `Entity` is a thin projection over a note's frontmatter: `id` (alias or filename slug), `name` (filename), `collection`, `tags`, `score`, `sourcePath` (plus in-memory `createdAt`/`updatedAt` for sort, defaulted to load time — never written back). It carries no body content — the body is read on demand and rendered via `noteMarkdownBody`. The app owns only `EntityFileWriter._knownOrder` (`collection`, `alias`, `tags`, `score`); any other frontmatter key (`category`/deck, `anki_note_id`, `hardcover_id`, user keys) is preserved untouched on save.

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
