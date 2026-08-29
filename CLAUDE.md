Focus on creating progressively better abstractions: implementation should become more elegant and hard-to-vary over time. Encode error-correcting mechanisms into the code.

# Project

Filesystem-native companion to an Obsidian vault. All data lives as Markdown files in a user-chosen vault. The app does four narrow things: **Collections**, one persistent **Inbox**, **Projects**, and a **one-way Anki sync**. Problem Note review/editing and full graph traversal live in **Obsidian**; Collections has one read-only entity-body view whose wikilinks open Obsidian. Vault-root integrations patch frontmatter only; Inbox and Projects are Interest-owned Markdown bodies under `Interesting/`. Architectural rationale: [README.md](README.md). This file states constraints and their enforcement points.

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
| Modifying the Projects subsystem | [docs/projects.md](docs/projects.md), then `ProjectStorageService` |
| Modifying Inbox capture or query scope | [docs/inbox.md](docs/inbox.md), then `InboxStorageService` + `OpenInboxQueryService` |
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

**3. Vault-root integrations patch frontmatter, never the body.**
Entity writes go through `EntityFileWriter.patchFrontmatter` (owned keys only: `collection`, `tags`, `score`) or `buildNewEntity`; the Anki sync writes only `anki_note_id` via `patchFrontmatterField`. In every case an existing vault-root note body is preserved byte-for-byte. Interest-owned Inbox and Project files under `Interesting/` are the explicit body-write boundary. WHY: rebuilding user-authored vault-root bodies destroyed content (including a Problem Note's `***` front/back).

**4. Problem Note and Entity are orthogonal sets.**
Problem Note structure ⟺ `***` in body; Anki-ready ⟺ both sides of that split are non-empty (deck = `category:`, default `Default`). Entity ⟺ `collection:` in frontmatter. A note may be both. WHY: conflating them is exactly what corrupted notes in June 2026. Enforcement: `splitFrontBack` (`AnkiProblemNoteScanner`) and `isEntityFrontmatter` (`EntityFileParser`) are independent predicates — never gate one on the other.

**5. Full-body wikilink scan.**
`extractWikilinks(body)` / `rewriteWikilinksToHtml(body, …)` scan the whole Markdown body. WHY: narrowing the scan makes link relationships location-dependent — moving a `[[link]]` between sections silently drops it. Enforcement: `EntityFileParser.parseEntityFile` and `AnkiSyncService._markdownToAnkiHtml`. There is no stored or in-memory edge list.

## The vault-write safety invariant (Anki sync)

The Anki sync's **only** vault write is `AnkiSyncService._patchAnkiNoteId` → `patchFrontmatterField`, which writes the `anki_note_id` frontmatter key and preserves the body verbatim. No sync code opens or writes any note body. A prior version destroyed note bodies by rebuilding them on save; that must never be reintroduced. The sync stack (`lib/features/anki/`) is self-contained and depends on no viewer.

## Service standard

Expected failure must cross a service boundary as an explicit result, including whether an observation was complete. `AnkiProblemNoteScanner`, `AnkiSyncService`, and entity discovery expose errors rather than returning an ordinary empty/partial success. `AnkiTransport` implementations may throw `AnkiSyncAbort` / `AnkiNoteFailure`, consumed only by `AnkiSyncService.syncVault`. Several older storage services still use nullable or `Future<void>` catch boundaries; do not infer success from those return shapes.

## Save semantics

- **Per-file writes only.** Each mutation touches exactly one file; there is no bulk "save all" path (that pattern caused the June 2026 corruption).
- **Frontmatter edit** (collection, tags, score) in `EntityScreen` edit mode → `_saveEdit()` → `MarkdownStorageService.saveEntity(entity)`, which patches that one file's frontmatter and preserves its body. `Cancel` restores the pre-edit snapshot in memory (no I/O).
- **There is no in-app vault-root note-body editor.** Body editing for user-authored vault-root notes lives in Obsidian. The explicit exceptions are Interest-owned Inbox and Project files under `Interesting/`.
- **New entity**: `saveEntity` creates a file with **only `collection:` frontmatter** and an **empty body** — no imposed `# Name`, no timestamps — at vault root, then sets `Entity.sourcePath`. **Delete**: `deleteEntity` removes that one file. **Collection rename**: `renameCollection` patches each member file, then reloads.
- The app neither requires nor stamps `created_at`/`updated_at`; if a note already has them they are preserved, never added.

## Write paths

Each storage path co-owns specific files. Vault-root integrations preserve note bodies; Inbox and Project editing is bounded to Interest-owned files under `Interesting/`.

| Storage layer | Writes |
|---|---|
| `MarkdownStorageService` | vault-root entity notes (`collection:`); per-file frontmatter patch via `saveEntity`, body never rewritten |
| `AnkiSyncService` | `anki_note_id` only, via `patchFrontmatterField` — the sole vault write of the sync (see safety invariant) |
| `ProjectStorageService` | `Interesting/Projects/` |
| `InboxStorageService` | Creates `Interesting/Inbox.md` once; never rebuilds or migrates an existing Inbox |
| `TaskStorageService` | Shared checkbox-outline parser/editor for `Interesting/Inbox.md` and todo-style files in `Interesting/Projects/`; no path of its own |
| `IntegrationsConfigService` | `Interesting/System/integrations.md` — vault-native integration config |
| `TemplatesScreen` / `TemplateEditorScreen` | `Interesting/Templates/` — direct screen writes |

## Identity anchors

| Type | Anchor | Mutability | Delete |
|---|---|---|---|
| Entity | `collection:` presence = membership; identity = note name (filename); `alias:` optional, used as `id` when present else filename slug | filename can change | Hard (delete the file) |
| Problem note | `anki_note_id` (frontmatter) | Written on first sync; stable | Hard |
| Inbox item / Task / Project file | None | — | Items hard-delete; the Inbox file itself has a fixed path and no delete/rename UI |

## Shared utilities — do not duplicate

- **Markdown parsing and YAML serialization** — `lib/shared/markdown/md_utils.dart` (pure, no I/O): frontmatter splitting, `splitFrontBack` (the `***` predicate), section parsing, wikilink extraction + `rewriteWikilinksToHtml`, `obsidianUri`/`obsidianUriForName`, `slugify`, `sanitizeFilename`, timestamp helpers, `buildFrontmatterBlock(fields, knownOrder)` (canonical YAML frontmatter builder). Never reimplement in services or screens.
- **Note identity** — `noteKey(filePathOrFilename)` in `md_utils.dart` (lowercase basename without extension) is the canonical note identity. Apply `noteKey` only to paths/filenames (it strips after the last dot), never to bare wikilink targets — lowercase those directly.
- **Vault iteration and current-state eligibility** — `VaultScanner.scanResult()` in `lib/shared/markdown/vault_scanner.dart` is the sole recursive `Directory.list` site and exposes incomplete traversal. `CurrentVaultContent` in `lib/shared/markdown/current_vault_content.dart` is the sole path-eligibility owner for cards, entities, and link targets. It permanently excludes rollback/history, trash, templates, attachments, Basic Memory, and Interest system config; Anki additionally excludes all `Interesting/` content and accepts additive configured exclusions. Root notes and `Clippings/` remain current authored surfaces. `lib/shared/markdown/md_io.dart` holds `patchFrontmatterField` (the body-safe write primitive used for `anki_note_id`).
- **UI primitives** — `lib/shared/widgets/`: `showInputDialog()`, `showConfirmDialog()`, `showBottomSheetMenu()`, `showQuickAddSheet()`, `showSnack()`, `SectionHeader`, `EmptyState`, `LoadingState`, `InlineSpinner`, `ErrorRetryState`, `AppFab`, `SelectChip`, `ListRow`, `BusyButton`, `AccentButton`, `WikilinkText`. Never inline `AlertDialog+TextField`, raw `showModalBottomSheet`, direct `ScaffoldMessenger…showSnackBar`, raw `FloatingActionButton`, `Center(child: CircularProgressIndicator())`, or a hand-built bottom-bordered tappable row. Screen bodies have exactly three placeholder states: `LoadingState`, `EmptyState`, `ErrorRetryState`.
- **Date display** — `lib/shared/utils/date_format.dart`: `formatRelative(msEpoch)`, `formatMonthDay`, `formatMonthDayYear`. The month-abbreviation table lives only here.
- **Shared note view** — `lib/shared/widgets/note_markdown.dart` (`noteMarkdownBody` / `noteMarkdownStyle` / `onNoteLinkTap` — render Markdown with tappable `[[wikilinks]]`). Used by `EntityScreen` (the only in-app note view). Wikilink taps route to Obsidian; there is no in-app backlinks panel or note-detail screen.
- **Quick Add Sheet** — `lib/shared/widgets/quick_add_sheet.dart`: `showQuickAddSheet(context, entities:, collections:, storage:, onCreated:, initialCollection?)`. Free-text Collection field (existing collections shown as chips); any value creates/uses a collection. Requires a name and a collection. Creates the file via `storage.saveEntity`; persists last-used collection in `SharedPreferences` key `last_used_collection`.
- **Text styles** — `lib/shared/constants/app_text_styles.dart`: `AppTextStyles` static getters for every named role (IBM Plex Sans/Serif). Never hardcode `GoogleFonts.ibmPlex…` inline.
- **Colors** — `lib/shared/constants/app_theme.dart` `AppColors`: all color constants including `borderMid` (#282828). No hex literals inline.
- **Spacing** — `lib/shared/constants/app_spacing.dart`: `kFabListBottomPad` (88.0), `kScreenHPad` (16.0). No magic numbers.

## Configuration ownership

Integration configuration lives in `Interesting/System/integrations.md` (vault-canonical), managed by `IntegrationsConfigService` in `lib/core/`. SharedPreferences owns only settings that must be known before the vault is accessible or that are local UI state:

| Key | Location | Rationale |
|---|---|---|
| `vault_path` | SharedPreferences | Must be known before vault is accessible |
| AnkiConnect URL override | `integrations.md` (`## AnkiConnect`) | Hand-edited only (no in-app editor); null = `http://127.0.0.1:8765` |
| Additional excluded folders (Anki scan scope) | `integrations.md` (`## Resurface`) | Portable additive exclusions. System/history exclusions are invariant in `CurrentVaultContent` and cannot be removed by config. The old section name remains for compatibility. |

## Subsystem constraints

**Anki sync** — one-way push only (vault → Anki) over two transports: `AnkiDroidTransport` (MethodChannel → `AnkiBridge.kt` → ContentProvider, Android) and `AnkiConnectTransport` (HTTP → Anki desktop's AnkiConnect add-on, pure Dart). `AnkiProblemNoteScanner.scan()` returns a completeness-bearing discovery result; historical/system paths, unreadable traversal, and duplicate active `anki_note_id` values block all card mutation. `AnkiSyncService` owns rendering, `category:`→deck mapping, the `obsidian://` wikilink rewrite, hard-break promotion, and the `anki_note_id` round-trip. A transport identity lookup distinguishes missing from unavailable, and an abort/deck-move failure is not counted as success. Both transports require the model literally named `Basic`. **Triggers:** the `interest://sync-anki` deep link and Sources → AnkiDroid row (foreground app), plus Sources → Anki desktop (AnkiConnect). Full details: [docs/anki.md](docs/anki.md).

**Deep-link sync (Android)** — `interest://sync-anki` is a VIEW intent on `MainActivity` (`launchMode=singleTop`): cold start stores `pendingSyncAnki`, while `onNewIntent` sends `syncAnki` over `dev.interest.app/deeplink`. Flutter runs the same foreground `runAnkiDroidSync` path used by Sources → AnkiDroid. `AnkiBridge` is registered on `MainActivity`, which forwards permission results. Compilation covers this contract; delivery and permission behavior still require on-device evidence.

**Projects** — unified shell replacing Lists + Todos. Files live only in `Interesting/Projects/`; legacy stores and migration paths are absent. Todo-style files use `TaskFileScreen`; constrained `type: list` files use `ProjectListDetailScreen`. No due dates, priorities, or scheduling. Full details: [docs/projects.md](docs/projects.md).

**Inbox** — the deliberately loose, persistent `Interesting/Inbox.md`; arbitrary Markdown is valid capture, while checkbox open/closed semantics and attached prose are optional editor affordances. Completion toggles in place; drag/completed regrouping is disabled. Every UI write requires the exact strict-UTF-8 byte snapshot still to match and uses same-ID staged/backup siblings for a flushed, verified replacement with recovery; stale or ambiguous outcomes reload without retrying. This is recoverable but not an atomic cross-process CAS. First creation writes a verified sibling marker before exclusively creating/appending the canonical bytes; a leftover marker accepts the canonical only on an exact match. On restart, owned recovery artifacts block empty creation and their exact paths surface for inspection; mutation recovery never replaces an existing canonical. Missing/unreadable/invalid UTF-8 is an error, not an empty Inbox. `OpenInboxQueryService` is read-only and scans this exact file only; top-level `records` contains its one coherent complete Markdown document, while unchecked checkboxes appear only in a non-exhaustive `derived_hints` outcome whose failure cannot discard or downgrade that document. Both carry the exact `Interesting/Inbox` Obsidian locator; a changing/incoherent observation emits neither. Every Project and every other vault checkbox is explicitly outside this provider's responsibility. Full details: [docs/inbox.md](docs/inbox.md).

**Tasks (parser)** — `TaskStorageService.parseNodes()` powers both Inbox and Project outline editing. No YAML frontmatter; `parseNodes()` is pure; `_collapsed` is session-only; `deleteBlock` hard-deletes. Project root completion/reordering remains available, but nested completion always toggles in place. Inbox uses the guarded snapshot mutations and disables every reorder surface. No due dates, reminders, or notifications. Full details: [docs/tasks.md](docs/tasks.md).

**Grokipedia** — never writes to vault; no caching; state lives only in `_EntityScreenState`.

**Navigation shell** — `home_screen.dart` is a 3-tab `BottomNavigationBar`: 0=Collections (landing), 1=Inbox, 2=Projects. Inbox has its persistent bottom capture field rather than a FAB. FAB shows on Collections and Projects. AppBar actions: Sources (`sensors`), and a popup (Settings, Templates, Open Obsidian).

**Sources screen** — `sources_screen.dart`, pushed from the `sensors` AppBar icon. Rows: Obsidian (launch `obsidian://`), AnkiDroid (manual push, Android only), Anki desktop (manual AnkiConnect sync). The two Anki rows are mutually exclusive (`_ankiBusy`) — both write `anki_note_id` to the same files. The AnkiDroid row and the `interest://sync-anki` deep link share `runAnkiDroidSync`.

**Android widget** — reads `flutter.vault_path` directly; writes `collection: Quick Capture` (Collections-visible) AND `category: Default` (AnkiDroid deck) — both required, orthogonal; new notes at vault root with the app's collision scheme. Divergence from the app's new-entity model (deliberate, native-side): the widget stamps `created_at`/`updated_at` and builds a body from `Interesting/Templates/default.md` — the only code path that imposes body structure, and the only consumer of Templates.

**State management** — `setState` only. No `Provider`, `Riverpod`, `Bloc`.

**Sorting** — all entity list sorting routes through `MarkdownStorageService.sortEntities(entities, sortOrder)`. Add new sort options there first, then `DropdownMenuItem` entries in screens. Entity pickers are pre-sorted A→Z inline.

**Entity model** — `Entity` is a thin projection over a current eligible note's frontmatter: `id` (alias or filename slug), `name`, `collection`, `tags`, `score`, `sourcePath`, plus in-memory timestamps. Duplicate active IDs are withheld and surfaced as discovery errors rather than guessed. The body is read on demand and rendered via `noteMarkdownBody`. The app owns only `EntityFileWriter._knownOrder` (`collection`, `alias`, `tags`, `score`); other frontmatter keys are preserved on save.

## Mobile UX conventions

Full reference: [docs/mobile_ux.md](docs/mobile_ux.md). Enforcement rules:

- Every `Scaffold` body: `SafeArea(top: false)` (AppBar handles top; SafeArea handles gesture nav bar bottom)
- Every list behind a FAB: `padding: const EdgeInsets.only(bottom: kFabListBottomPad)`
- Scrollable search sheets (`isScrollControlled: true`): `screenHeight * fraction` for height, never fixed pixels
- Every `TextField`: declare `textInputAction` (`next` / `done` / `newline` / `send`)

## Targeted Anki CLI

`tool/sync_anki_notes.dart` exists for file-bounded restructuring transactions. It must reuse `AnkiProblemNoteScanner`, `AnkiSyncService`, and `AnkiConnectTransport`; it must require explicit `--file` arguments, reject paths outside the vault, and never duplicate card rendering or imply a whole-vault sync.
