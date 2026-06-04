# Refactor Audit

Each artifact should have one primary reason to change. This document names the artifacts
that violate that principle, explains why it matters, and proposes a concrete change for
each finding. Nothing here is a refactor for aesthetics alone.

---

## Current Strengths

These work well and should not be touched without strong justification.

1. **`md_utils.dart` is genuinely pure.** No I/O, no state, single file. All text operations
   (frontmatter splitting, wikilink extraction, slugification, YAML building) live here and are
   called by name. This is the correct pattern for everything else to follow.

2. **Field ownership partition in the books subsystem.** Readwise, Hardcover, and ReadEra each
   own distinct frontmatter keys and never overwrite each other. `BookStorageService.patchFields()`
   is the single write primitive; enrichment sources call through it. This is the intended model
   for all enrichment.

3. **Immutable identity anchors.** `alias` is never regenerated. `anki_note_id` is written once.
   `_parseEntityFile` rebuilds entity state from file; it never overwrites the anchor. The
   enforcement point (`_saveEdit()` in `entity_screen.dart`) is documented and respected.

4. **All-catch-null service standard.** Services return `null` or a result DTO on error; they
   never throw. This prevents cascading failures in async chains.

5. **Session-only state is correctly not persisted.** `_collapsed` (tasks), `_grokArticle` and
   `_grokSearched` (entities), and the deck-viewer navigation stack all live only in `State`
   objects. No accidental persistence creep.

6. **Snapshot + rollback for entity editing.** `_markDirty()` takes a deep copy of the entity on
   first change. Cancel restores the snapshot atomically. This is the right model for
   deferred-save screens.

7. **`ReviewLogService` is the sole writer of `review_log.md`.** No other service touches that
   file. This boundary is maintained.

8. **`ResurfaceService` is read-only.** It never writes to the vault. The write path for notes
   goes through `NoteEditScreen` directly to the file path it received. This is clean.

---

## Architectural Invariants

These must remain true after any refactoring. A proposed change that would violate any of these
requires explicit justification and user approval before proceeding.

1. Markdown is the database. No SQLite, no parallel JSON. All persistent state lives in `.md`
   files in the vault.
2. `alias` is immutable after creation. Wikilink graph identity depends on it.
3. Patch-not-rebuild for entity files. `_patchEntityContent()` preserves user `##` sections.
   Rebuild destroys them.
4. `_semanticSections` is the app/user boundary. Only keys in that const map are rewritten on
   save.
5. Full-body wikilink scan. Graph edges must not be location-dependent.
6. `ReviewLogService` is the sole writer of `review_log.md`.
7. `ResurfaceService` never writes.
8. Enrichment sources write only via `BookStorageService.patchFields()` (or
   `appendReaderaHighlights()`).

---

## Multi-Problem Artifacts

### 1. `lib/screens/home_screen.dart` (885 lines)

Problems it solves simultaneously:
- Tab navigation shell (4 tabs via `IndexedStack`)
- Entity CRUD (load, create, delete, sort, filter by category)
- Category CRUD (add, rename, delete with in-use validation)
- Full-text search across entities
- Share intent handling (URL → bookmark → vault write)
- Deep link handling (`interest://` → resurface tab + note open)
- Cross-feature state coordination (reloads after `EntityScreen` exits)
- AppBar mutation per tab state

**Why this is a problem:** Eight independent reasons to change. A new sort option, a new
deep-link scheme, a share-sheet redesign, and a category rename bug each require editing the
same 885-line class. The share intent handler calls `ResurfaceService` and
`MarkdownStorageService`; a change to either ripples into this screen for unrelated reasons.

---

### 2. `lib/features/resurface/screens/resurface_screen.dart` (943 lines)

Problems it solves simultaneously:
- Deck list display (filtered problem notes with counts)
- Card viewer with tap-to-reveal and swipe navigation
- Review state management (no-repeat queue, position tracking)
- Review logging (calls `ReviewLogService.markReviewed()`)
- Graph scoring coordination (calls `GraphScoringService.updateGraphScores()`)
- Full-text search across all notes
- Deep-link fallback resolution via `ResurfaceService.resolveWikilink()`
- Edit integration (reloads single note after `NoteEditScreen` exits)
- Deletion (removes file + cleans review log)
- Navigation stack management (`_stack` list driving three visual states)

**Why this is a problem:** Review logging, graph scoring, search, and card navigation are
independent problems. A graph scoring algorithm change requires editing the card viewer. A
search UX change requires understanding the review state machine.

---

### 3. `lib/features/entities/screens/entity_screen.dart` (1343 lines)

Problems it solves simultaneously:
- Entity display mode (read-only view of all fields)
- Entity field editing (name, category, tags, score, notes, links, relations)
- Grokipedia integration (background fetch, lazy summary expansion, article state)
- Entity link management with immediate persistence
- Category and tag management UI

**Why this is a problem:** Grokipedia is an optional enrichment concern entirely independent
of field editing. The immediate-save path for links and the deferred-save path for fields
live in the same 1343-line class, making it easy to accidentally use the wrong path when
adding new field types.

---

### 4. `lib/features/entities/services/markdown_storage_service.dart` (565 lines)

Problems it solves simultaneously:
- Vault-wide file scanning (done twice: lines 46–64 in `loadData`, lines 120–133 in
  `saveData`)
- YAML frontmatter parsing (4+ distinct call sites within the file)
- Markdown section parsing (Why Interesting, Related, Sources)
- Wikilink extraction for graph edge inference
- Entity file write (frontmatter + body reconstruction)
- Semantic section rendering (list bullets vs. wikilink bullets vs. generic)
- Template loading and instantiation (category-specific or default)
- Entity ID and category ID generation (slugification)
- Sorting (`sortEntities` static method called from UI)

**Why this is a problem:** Vault scanning logic, section rendering logic, and ID generation
each change for independent reasons. The two separate vault scans (load vs. save) are a
maintenance hazard: if scan logic changes, both must be updated. `sortEntities` belongs in
the UI layer or a dedicated sort utility, not a storage service.

---

### 5. `android/app/src/main/kotlin/.../MainActivity.kt`

Problems it solves simultaneously:
- AnkiDroid bridge (permission requests, note add/update/exists via `AddContentApi`)
- Share intent extraction (URL from `ACTION_SEND`)
- Deep link extraction (`interest://` from `ACTION_VIEW`)
- App startup coordination

**Why this is a problem:** AnkiDroid permission flow, share intent parsing, and deep link
routing are independent concerns. A change to the AnkiDroid API version requires
understanding the share intent handler.

---

### 6. `lib/features/resurface/services/review_log_service.dart` (397 lines)

Problems it solves simultaneously:
- Persistence of review state to YAML file
- Complex entry mutation (immutable-record updates via list comprehensions)
- Settings persistence (min/max degree)
- Activation chain management (`activated_by` list appends)

**Why this is a problem:** The entry mutation pattern (lines 246–260, 298–311, 371–384) is
error-prone and scattered. Three separate methods perform similar read-mutate-write cycles
without shared primitives. A missed field update in one of the three paths silently corrupts
the log.

---

### 7. `lib/core/integrations_config_service.dart`

Problems it solves simultaneously:
- Configuration file read/write
- Token parsing (Readwise, Hardcover)
- RSS feed list parsing and serialization
- Resurface excluded folders parsing
- YAML file construction (monolithic `_buildContent`)
- SharedPreferences migration (legacy one-time migration)

**Why this is a problem:** Adding a new config section requires editing the parser, the
builder, and the migration path. They are not isolated.

---

### 8. `lib/features/rss/screens/sources_screen.dart` (170 lines, misleadingly small)

Problems it solves simultaneously:
- Navigation hub (links to Hardcover, Articles, Readwise, Bookmarks, Obsidian, AnkiDroid)
- AnkiDroid sync orchestration (loads vault, loads config, gets notes, filters, calls sync,
  shows result dialogs)
- External app launching (Obsidian URI)

**Why this is a problem:** The AnkiDroid sync flow (lines 91–163) reaches into
`ResurfaceService`, `IntegrationsConfigService`, and `VaultService` from a navigation screen.
A change to sync logic requires editing a screen. This is a boundary violation, not just a
sizing problem.

---

## Duplicate Solutions

### 1. Vault scanning — 5 independent implementations

| Location | Scope |
|---|---|
| `MarkdownStorageService.loadData()` | All vault `.md` files (line 46) |
| `MarkdownStorageService.saveData()` | All vault `.md` files again (line 120) |
| `ResurfaceService.getAllNotes()` | All vault `.md` files with exclusion filter |
| `ArticleStorageService.buildIndex()` | `Interesting/Articles/` |
| `LetterboxdAdapter._buildMovieIndex()` | Vault root, filtered by `category: Movies` |

**Canonical location:** A shared `VaultScanner` utility (read-only, no parsing, just file
iteration with exclusion) would serve all five.

---

### 2. Frontmatter parsing — 11+ independent call sites

`splitFrontmatter()` and `parseYamlMap()` are called inline in:
- `MarkdownStorageService._parseEntityFile()` (lines 262, 277)
- `MarkdownStorageService.loadData()` (line 54)
- `MarkdownStorageService._patchEntityContent()` (line 387)
- `MarkdownStorageService.saveData()` (line 128)
- `ResurfaceService.getAllNotes()` (lines 53–54)
- `ResurfaceService.loadSingleNote()` (lines 86–87)
- `NoteDetailScreen._load()` (line 56)
- `NoteEditScreen._load()` (line 69)
- `BookStorageService.loadBooks()` (lines 23–25)
- `ArticleStorageService.buildIndex()` (lines 68–71)
- `LetterboxdAdapter._buildMovieIndex()` (lines 108–111)

**Problem:** No single layer is responsible for "parse a vault file into structured data."
Changes to YAML field handling must be made in 11+ places.

**Canonical location:** `md_utils.dart` already provides the primitives. The duplication is
in callers doing inline `split → parseYamlMap → extract field` sequences rather than calling
a typed parser per domain object.

---

### 3. Frontmatter building — 6 independent implementations

| Location | Purpose |
|---|---|
| `MarkdownStorageService._buildFrontmatter()` | Entity files |
| `BookStorageService._buildNewBookContent()` | Book files |
| `ArticleStorageService._buildContent()` | Article files |
| `LetterboxdAdapter._buildMovieMarkdown()` | Movie files |
| `XBookmarkStorageService.save()` | Bookmark files |
| `IntegrationsConfigService._buildContent()` | Config file |

`buildFrontmatterBlock()` in `md_utils.dart` exists precisely for this purpose but is not
used consistently. `ArticleStorageService._yamlValue()` and
`IntegrationsConfigService._yamlQuote()` are independent reimplementations of
`md_utils._yamlScalar()`.

---

### 4. Wikilink handling — 3 separate approaches

| Location | Approach |
|---|---|
| `md_utils.extractWikilinks()` | Extracts target names (correct shared utility) |
| `AnkiDroidService._wikilinkToAnkiLink()` | Inline regex reimplementing `[[...]]` pattern |
| `ResurfaceScreen` search (line 534) | `plainTextWikilinks()` called inline |

`AnkiDroidService` reimplements the regex that already exists in `md_utils`. Any change to
wikilink syntax (e.g., supporting `[[file#anchor]]`) would need to be applied to both
independently.

---

### 5. Slug/alias generation — 3 implementations

| Location |
|---|
| `md_utils.generateUniqueId()` — canonical |
| `ArticleStorageService.uniqueAlias()` — independent reimplementation |
| `XBookmarkStorageService.uniqueSlug()` — third copy |

---

### 6. YAML quoting — 3 implementations

| Location |
|---|
| `md_utils._yamlScalar()` (private) |
| `ArticleStorageService._yamlValue()` |
| `IntegrationsConfigService._yamlQuote()` |

---

## Boundary Violations

### 1. `ProjectListDetailScreen` does direct file I/O (critical)

Lines 50, 76, 142–157: `File.readAsString()` and `File.writeAsString()` called directly from
UI. Frontmatter parsing (`splitFrontmatter`, `extractH1`) done inline in the screen. Rename
logic (H1 patching + file rename) reimplemented without a service.

**Violation:** Presentation reaching into infrastructure. The screen owns its own persistence.

---

### 2. `AnkiDroidService` calls `patchFrontmatterField` from `md_io` directly

Lines 75–76, 86–87: `AnkiDroidService` calls `md_io.patchFrontmatterField()` to write
`anki_note_id` back to frontmatter. This bypasses `MarkdownStorageService` entirely —
storage infrastructure is accessed directly from a sync service.

**Violation:** `anki_note_id` write-back is the only cross-boundary write that does not go
through a storage service.

---

### 3. `LetterboxdAdapter` writes directly to vault root

Lines 74–75: `LetterboxdAdapter` constructs file paths from `vaultPath` directly and writes
movie files to the vault root, bypassing `MarkdownStorageService`. It also builds its own
movie index (lines 97–127) by scanning the vault independently.

**Violation:** Adapter owns storage that should belong to `MarkdownStorageService` (movies
are entities with `category: Movies`). Index building duplicates `loadData()`.

---

### 4. `SourcesScreen` orchestrates AnkiDroid sync (lines 91–163)

The sync flow reaches into `VaultService`, `IntegrationsConfigService`, `ResurfaceService`,
and `AnkiDroidService` directly from a navigation screen. Result dialogs are constructed
inline.

**Violation:** Sync orchestration belongs in a service or controller, not a screen.

---

### 5. `HardcoverScreen` does duplicate-book detection (lines 292–295)

Checks whether an incoming book already exists by title/`hardcover_id` matching against
loaded books — logic that belongs in `BookStorageService.reconcile()`.

**Violation:** Storage policy in the UI layer.

---

### 6. `Book.fromFrontmatterYaml` parses frontmatter in the model

Lines 41–67: The `Book` model calls `parseSectionsH2()` and `parseIsoToMs()` from `md_utils`
to parse its own frontmatter. The model owns a read path that belongs to
`BookStorageService`.

**Violation:** Model containing parsing logic that belongs to the storage service.

---

### 7. `rss_utils.stripHtml` is scoped to the RSS feature

`stripHtml()` strips HTML tags and entities from arbitrary text. It lives in
`lib/features/rss/utils/rss_utils.dart` but is needed for any content from external sources.
Its current location prevents reuse.

---

## Missing Conceptual Boundaries

### 1. Note identity

A note's identity is its `basenameWithoutExtension`. This normalization is performed inline,
inconsistently:
- `ResurfaceScreen`: `basenameWithoutExtension(note.sourcePath)` (un-normalized)
- `ReviewLogService`: note name as YAML key (un-normalized)
- `GraphScoringService`: `key.toLowerCase()` (lowercased)

If `ReviewLogService` stores `"My Note"` and `GraphScoringService` looks up `"my note"`, the
lookup fails silently. There is no single function responsible for "canonical note identity
string."

---

### 2. Front/back render mode decision

Whether a note is a two-sided card (`***` present) or plain text is determined by calling
`splitFrontBack()` in four places:
- `NoteDetailScreen._load()` (line 57)
- `NoteEditScreen._load()` (line 70)
- `ResurfaceService.getAllNotes()` (line 56)
- `ResurfaceService.loadSingleNote()` (line 88)

`isProblemNote` on `ResurfaceNote` is the closest thing to a canonical owner, but screens
re-derive the same fact from raw file content independently.

---

### 3. Wikilink resolution

`ResurfaceService.resolveWikilink(name)` performs vault-wide name lookup but is called in
only one path (deep-link fallback in `ResurfaceScreen`). `GraphScoringService` builds its
own note graph keyed by filename without going through `resolveWikilink`. There is no single
owner for "given a `[[Name]]`, which file does it resolve to?"

---

### 4. Review log atomic update

`ReviewLogService` is correctly the sole writer. However, `GraphScoringService` calls three
separate `ReviewLogService` methods (`patchGraphScores`, `activateNotes`, `loadFullLog`) in
a single `updateGraphScores` call without transactional safety. If `patchGraphScores`
succeeds but `activateNotes` fails, the log is partially updated. There is no "update graph
state atomically" operation.

---

### 5. Vault scan ownership

Five services scan the vault independently (see Duplicate Solutions §1). There is no
`VaultScanner` or equivalent that owns "here is the list of all vault `.md` files." Each
scanner has its own exclusion logic, recursion depth, and error handling.

---

## Refactor Candidates

Ordered by estimated impact. Each proposes exactly one concrete change.

---

**R1: Extract `AnkiDroidSyncController` from `SourcesScreen`** ✓ DONE

Move lines 91–163 of `sources_screen.dart` into a dedicated service. `SourcesScreen` calls
`controller.sync()` and receives a result DTO. Result dialogs remain in the screen but are
constructed from the DTO.

- Fixes: Boundary Violation §4
- Impact: `SourcesScreen` becomes navigation-only; sync logic is independently testable
- Implemented: `lib/features/resurface/services/ankidroid_sync_controller.dart` (all-static,
  returns `AnkiSyncResult?` — null signals no vault configured). Pre-flight checks
  (`isAvailable`, `requestPermission`) remain in the screen as they reference only
  `AnkiDroidService`.

---

**R2: Move `AnkiDroidService` write-back through a storage service**

Replace the two direct `patchFrontmatterField()` calls in `AnkiDroidService` (lines 75–76,
86–87) with a method on `MarkdownStorageService` (e.g.,
`patchAnkiNoteId(filePath, noteId)`). `AnkiDroidService` must not import from `md_io`
directly.

- Fixes: Boundary Violation §2
- Impact: `anki_note_id` write-back goes through the canonical storage boundary

---

**R3: Extract `ProjectListDetailScreen` file I/O into `ProjectStorageService`** ✓ DONE

Move the file read/write, frontmatter parsing, H1 patching, and rename logic from
`ProjectListDetailScreen` (lines 50, 76, 142–157) into `ProjectStorageService` methods. The
screen calls service methods only.

- Fixes: Boundary Violation §1 (critical)
- Impact: Removes the only screen that currently owns its own persistence
- Implemented: added `ProjectMeta` class + `loadProjectContent`, `loadProjectMeta`,
  `saveProjectContent`, `renameProjectByPath` to `ProjectStorageService`. Screen has zero
  `File`, `splitFrontmatter`, or `extractH1` references; `dart:io` import removed.
- Deviation: method named `renameProjectByPath(String filePath, String newTitle)` rather than
  `renameProject(...)` — Dart has no overloading and the existing
  `renameProject(vaultPath, ProjectFile, newName)` (called from `projects_screen.dart`) must
  not change.

---

**R4: Make `md_utils._yamlScalar` public, remove duplicates**

`ArticleStorageService._yamlValue()` and `IntegrationsConfigService._yamlQuote()` are
independent reimplementations of `md_utils._yamlScalar()`. Make `_yamlScalar` public (rename
to `yamlScalar`). Update both callers.

- Fixes: Duplicate Solutions §6
- Impact: One implementation of YAML quoting; zero risk of behavioral divergence

---

**R5: Deduplicate slug/alias generation**

`ArticleStorageService.uniqueAlias()` and `XBookmarkStorageService.uniqueSlug()` reimplement
`md_utils.generateUniqueId()`. Update both to call the canonical function.

- Fixes: Duplicate Solutions §5
- Impact: Single implementation of the `-2/-3` collision resolution pattern

---

**R6: Move `rss_utils.stripHtml` to `md_utils`**

`stripHtml()` has no RSS-specific logic. Move it to `md_utils.dart`. Update the one import
in `LetterboxdAdapter`.

- Fixes: Boundary Violation §7
- Impact: Low risk; pure function move with one caller update

---

**R7: Centralize note identity normalization**

Add `noteKey(String filePath) → String` in `md_utils.dart` returning
`basenameWithoutExtension(filePath).toLowerCase()`. All of `ResurfaceScreen`,
`ReviewLogService`, and `GraphScoringService` use this function.

- Fixes: Missing Conceptual Boundary §1
- Impact: Eliminates the silent case-mismatch lookup failure

---

**R8: Add `ReviewLogService.updateGraphState(...)` atomic method**

Replace the three separate calls in `GraphScoringService.updateGraphScores()` with a single
`ReviewLogService` method that performs all mutations in one read-mutate-write cycle. The
caller passes a typed result struct.

- Fixes: Missing Conceptual Boundary §4
- Impact: Eliminates partial-update risk; `ReviewLogService` interface becomes clearer

---

**R9: Fix `EmptyState` widget to use `AppColors`**

Replace `Colors.grey.shade400` and `Colors.grey.shade600` in
`lib/shared/widgets/empty_state.dart` with `AppColors.textSecondary` and
`AppColors.textTertiary`.

- Fixes: Theme abstraction violation
- Impact: Trivial; one file, two lines

---

**R10: Route article, bookmark, and movie frontmatter through `buildFrontmatterBlock`**

`ArticleStorageService._buildContent`, `XBookmarkStorageService.save`, and
`LetterboxdAdapter._buildMovieMarkdown` build YAML frontmatter manually. Route these through
`md_utils.buildFrontmatterBlock()`.

- Fixes: Duplicate Solutions §3 (partial)
- Impact: Consistent field ordering and quoting in three file types

---

## Deferred / Out of Scope

These findings are real but require architectural decisions before acting:

- **Splitting `ResurfaceScreen`, `EntityScreen`, `HomeScreen`** — multi-screen refactors
  involving navigation contract changes. Require per-screen approval in Phase 3.
- **Splitting `MarkdownStorageService`** — vault scan ownership and semantic section handling
  should be separate, but extracting them risks breaking the `loadData`/`saveData` symmetry.
  Needs careful design.
- **`LetterboxdAdapter` writing to vault root** — fixing this requires deciding whether
  Letterboxd movies should be full entities (with `alias`, graph participation) or remain a
  separate projection. Architectural direction question, not a refactor.
- **Unified note/entity abstraction** — five distinct file types each have their own storage
  service. A unified abstraction risks flattening meaningful domain distinctions. Defer until
  simpler dedup candidates are done.
- **`MainActivity.kt` decomposition** — sound, but requires Kotlin refactoring and platform
  channel renaming. Defer.
