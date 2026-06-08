# Refactor Audit — Third Pass

Applies the same two criteria as prior audits:
1. **Structural** — one primary reason to change per artifact.
2. **Directional** — does this serve Interest's purpose as a semantic traversal environment?

Audit reads the codebase as it stands after Phase 1 (home screen removal, Recent Notes move).
Items resolved cleanly in prior audits are not reopened.

---

## What Changed Since Audit-2

**Collections pivot.** Entity-ness is now determined solely by `collection:` in frontmatter. `alias` and `category` are orthogonal. `EntityFileParser.isEntityFrontmatter` is the single canonical check.

**Entity model rewrite.** `Entity.collectionId` is a derived property (slugified `collection:`). The `Entity` model no longer carries a stored graph edge list or related-entity references. Wikilink graph is live-computed by `BacklinksSection` and `EntityFileParser.parseEntityFile`.

**Shared note view abstraction.** `noteMarkdownBody`, `noteMarkdownStyle`, `onNoteLinkTap`, and `BacklinksSection` were extracted to `lib/shared/widgets/`. `obsidianUri()` was extracted to `md_utils.dart`. All note viewers (`EntityScreen`, `NoteDetailScreen`, `_NoteViewerBody`) build on these primitives.

**Audit-2 structural fixes applied.** `ResurfaceNote` constructor triplication was resolved via `ResurfaceService._parseNoteFile()`. `extractWikilinks` now strips alias suffixes correctly. `resolveWikilink` now uses `VaultScanner`. `_wikilinkToAnkiLink` was replaced by `rewriteWikilinksToHtml` from `md_utils.dart`.

**Home screen removal (Phase 1).** `lib/features/home/` deleted. 4-tab shell → 3-tab shell (Notes=0, Collections=1, Projects=2). `HomeDashboardScreen` (card-peek hero, Worth Revisiting, Quick Add FAB) is gone. Browse Notes section replaced by Recent Notes section in `ResurfaceScreen._buildDeckList()` — same recency definition (filesystem `stat.modified`), count (2), and display format.

---

## Shared Note View — Completeness

### 1. Every "open this note" handler in the codebase

| Location | Trigger | Behaviour |
|---|---|---|
| `EntityScreen._navigateToNoteName()` (`entity_screen.dart:194`) | wikilink tap, backlink tap inside EntityScreen | Looks up entity by name; opens `EntityScreen` if found; **silently no-ops for non-entity notes** |
| `ResurfaceScreen._handleWikilinkTap()` (`resurface_screen.dart:321`) | wikilink tap in card viewer or NoteDetailScreen | Resolves name → path via `ResurfaceService.resolveWikilink`; pushes `_NoteDetailRoute` |
| `ResurfaceScreenState.openNoteByName()` (`resurface_screen.dart:184`) | deep link from `home_screen.dart` | Checks `_allNotes` first (memory); if problem note → card viewer; if plain → `_NoteDetailRoute`; vault-wide fallback |
| `ResurfaceScreen._openSearchResult()` (`resurface_screen.dart:361`) | search result tap, Recent Notes row tap | Problem note → `_pushDeck`; plain → `_NoteDetailRoute` |
| `BacklinksSection.onNavigateToNote` (callback) | backlink item tap | Delegates to whatever callback was passed by the parent viewer |

### 2. Per-viewer behaviour for each note type

| Viewer | Entity-only | Problem note | Plain note | Both-note (`collection:` + `***`) |
|---|---|---|---|---|
| `EntityScreen` | Opens EntityScreen | No-op (not in `allEntities`) | No-op | Opens EntityScreen (body shows `***` as raw text) |
| `ResurfaceScreen` card viewer | Not reached from here | Card viewer (flip) | NoteDetailScreen | Card viewer (flip) |
| `NoteDetailScreen` | Reads body regardless | Shows front/tap-to-reveal back | Shows body | Shows front/tap-to-reveal back |

### 3. Unified `openNote(filePath)` route

**Does not exist.** No single function decides which viewer to push based on a file path. A unified handler would need to:
1. Read frontmatter: `collection:` present? → EntityScreen
2. Read body: `***` separator present? → card viewer
3. Neither? → NoteDetailScreen
4. Both? → decision needed (see Deferred Items §1)

### 4. The traversal break

`EntityScreen._navigateToNoteName` is entity-scoped. If a problem-note-only note or a plain vault note links to a `collection:` entity and that entity screen tries to follow a wikilink or backlink back to the plain note, the tap is a no-op. A user reading an entity whose body links to a non-entity note cannot follow that link within Interest.

**Severity:** High for traversal quality. The backlinks panel (`BacklinksSection`) shows the backlinker's name as a tappable link, but the tap does nothing for non-entities. Users will see backlinks that cannot be navigated.

---

## Collections Pivot Residue

### 1. `alias:` as entity discriminator

`alias:` is used only as an optional stable ID override in `EntityFileParser.parseEntityFile` (`entity_file_parser.dart:63`): if an `alias` key is present, the entity's `id` is derived from it; otherwise from the filename slug. It is NOT used as a membership discriminator. **Clean.**

### 2. `category:`-based entity discovery

No code uses `category:` to decide entity membership. `isEntityFrontmatter` checks only `collection:`. **Clean.**

### 3. Stale "Entities" references

**`VaultService.entitiesPath()` (`vault_service.dart:54`) and `ensureVaultDirectories` (`vault_service.dart:25`):** `Interesting/Entities/` is still created on vault setup, but entity files now land at vault root. New entities are created in the vault root (`MarkdownStorageService.saveEntity`), not in `Interesting/Entities/`. The path is vestigial.

**`vault_setup_screen.dart:75`:** User-facing text reads `"Will create: Interesting/Entities · Interesting/Lists · Interesting/Templates"`. This is stale — `Interesting/Entities/` is no longer the entity storage location.

**`home_screen.dart._buildEntitiesTab()`, `_HomeScreenState.entities` variables:** These are internal names for the tab and its data. Not user-facing; consistent with the internal model still being called "Entity". No action required.

### 4. `EntityFileParser.isEntityFrontmatter` — single canonical check?

Yes. The only scan path is `MarkdownStorageService.loadData()`, which calls `EntityFileParser.isEntityFrontmatter(yaml)` before proceeding. **No duplication.**

One gap: the Android widget (`android/`) writes `category: Default` but does NOT write `collection:`. Notes created by the Android widget are therefore invisible to `isEntityFrontmatter` — they do not appear in Collections. This appears intentional (the widget is a quick-capture tool, not a collection manager) but is undocumented.

### 5. Orphaned EntityLink model code

No `EntityLink`, `getRelatedEntities`, or `entityLinks` symbols found anywhere in the codebase. **Clean.**

---

## Note View Abstraction

### 1. Every screen that renders markdown note content

| Screen | Uses `noteMarkdownBody`? | Notes |
|---|---|---|
| `EntityScreen._buildDisplayBody()` | ✓ | Via `noteMarkdownBody` directly |
| `NoteDetailScreen` | ✓ | Via `_mdBody()` wrapper |
| `_NoteViewerBody` (plain-note path) | ✓ | Via `_mdBody()` wrapper |
| `_NoteViewerBody` (problem-note front/back) | ✗ — uses `_mdBodySerif()` | Correct: card viewer intentionally uses IBM Plex Serif at 17–21px; this is a distinct rendering mode, not duplication |

**Assessment:** clean. The serif card rendering is a deliberate divergence, not an oversight.

### 2. Every screen that shows backlinks

All three note viewers (`EntityScreen`, `NoteDetailScreen`, `_NoteViewerBody`) use `BacklinksSection`. **Clean.**

### 3. Every screen with "Open in Obsidian" (for a specific note)

| Location | Uses `obsidianUri()`? |
|---|---|
| `EntityScreen._openInObsidian()` | ✓ |
| `ResurfaceScreenState.launchObsidianForCurrentNote()` | ✓ |
| `AnkiDroidService.syncVault()` (card front link) | ✓ |

### 4. Duplicate `obsidian://` (app launch, not note)

`home_screen.dart._openObsidian()` (`line 207`) and `sources_screen.dart._openObsidian()` (`line 153`) are identical: both call `launchUrl(Uri.parse('obsidian://'), mode: LaunchMode.externalApplication)` with the same snackbar fallback. This is not the `obsidianUri()` function — it opens Obsidian itself, not a specific note. The two methods are identical and should share a utility.

---

## Structural Findings

### Multi-problem artifacts

**`_HomeScreenState` (`home_screen.dart`)** — owns five independent concerns after Phase 1:
1. Navigation shell (tab switching, AppBar delegation, FAB routing)
2. Collections tab UI (`_buildEntitiesTab`, `_buildCollectionFilter`, `_buildAddBar`, `_buildSearchBar`, `_buildSortBar`, `_buildEntityList`)
3. Entity + collection CRUD operations (`_openEntity`, `_deleteEntity`, `_addEntity`, `_addCollection`, `_showCollectionOptions`, `_showRenameCollection`, `_deleteCollection`)
4. Deep link reception (`_openNoteFromDeeplink`, `_pendingDeeplinkNote`)
5. Share sheet reception (`_ingestShareUrl`, `XBookmarkService`, `XBookmarkStorageService`)

Reasons to change: tab structure changes (§1), collection UI layout changes (§2), entity CRUD logic changes (§3), deep link scheme changes (§4), share sheet logic changes (§5). This is the most structurally complex file in the codebase.

**`ResurfaceScreen` (`resurface_screen.dart`)** — owns:
1. Deck list with Recent Notes
2. Card viewer (via `_NoteViewerBody`)
3. Note detail routing (the internal `_stack`)
4. Full-text search (cross-vault inline search)
5. Public API for `home_screen.dart` (`openNoteByName`, `launchObsidianForCurrentNote`, `openEditForCurrentNote`, `navTitle`, `canGoBack`, `resetStack`, `isSearchable`, `toggleSearch`)

The internal `_stack` pattern is load-bearing: it enables ResurfaceScreen to be a single `IndexedStack` child while maintaining its own navigation depth. This is not cleanly separable without a navigator refactor. The public API surface (`openNoteByName`, `launchObsidianForCurrentNote`, etc.) is a consequence of `home_screen.dart` owning the AppBar — these actions are driven by AppBar buttons but executed inside ResurfaceScreen via `GlobalKey`. This is a coupling that exists because ResurfaceScreen has no Scaffold of its own.

### Duplicate solutions

**`_openObsidian()`** — Identical 8-line method exists in `home_screen.dart:207` and `sources_screen.dart:153`. Should be a shared static utility.

**`_formatTimestamp()`** — Defined in `home_screen.dart:525` (relative timestamp: "3m ago", "2h ago", etc.). No equivalent in `md_utils.dart`. If another screen needs relative timestamps, this pattern will be duplicated.

### Boundary violations

**`_buildEntitiesTab()` in `home_screen.dart`** — Entity list presentation logic (a full CRUD UI with collection filters, search, sort, add bar) lives inside the navigation shell file. The tab's content should be a self-contained `CollectionsScreen` widget. The navigation shell should not own business logic for one of its tabs.

### Missing conceptual boundaries

**No `openNote(filePath)` handler** — the concept of navigating to any vault note by file path has no canonical owner. `EntityScreen` handles entities, `ResurfaceScreen` handles all note types, but there is no routing decision function that maps a file path to the correct viewer. The traversal break in `EntityScreen` is a direct consequence.

**`VaultService.entitiesPath()`** — names a directory that no current write path uses. The concept of "where entities live" has drifted: the method says `Interesting/Entities/`, reality is vault root.

---

## Directional Alignment

**Notes (tab 0 — `ResurfaceScreen`):** Deck viewer, graph-scored traversal, full-text search, Recent Notes. Strongly aligns. Recent Notes is a temporal anchor for resuming a traversal session — same alignment as the removed Browse Notes, better framing (recency over exhaustive listing).

**Collections (tab 1 — inline in `_HomeScreenState`):** Entity graph traversal via wikilinks and backlinks aligns. Entity CRUD (create, rename, delete collection) is editorial. Same finding as audit-2 — no change.

**Projects (tab 2 — `ProjectsScreen`):** Same finding as audit-2. Project browsing partially aligns; task management does not.

**Home screen removal:** Card-peek hero and Worth Revisiting were high-alignment features removed as part of the structural simplification. The traversal session no longer has a curated entry point — the user lands on the deck list. This is a directional regression in traversal ergonomics, though structurally cleaner. Worth documenting as a known tradeoff.

**RSS/Articles, Bookmarks:** Import pipeline directional question unchanged from audit-2.

**AnkiDroid sync:** Three-system alignment unchanged. Still the cleanest subsystem.

**Sources screen:** After home removal, all six rows remain. Obsidian and AnkiDroid rows align. Four import rows (Hardcover, Articles, Readwise, Bookmarks) are pipeline-management. No change from audit-2.

---

## Dual Scheduling

### 1. Conceptual distinction in code and docs

**Progress since audit-2:** The public API of `ReviewLogService` uses `recordTraversal` and `loadTraversalLog`. The vocabulary shift from "review" to "traversal" is underway at the API surface.

**Remaining "review" terminology in traversal context:**
- `ReviewLogService` — class name uses "review"
- `review_log_service.dart` — filename
- `review_log.md` — vault file (changing this requires a migration)
- `_RawEntry.lastReviewed`, `GraphScoringService.updateGraphScores(reviewedNoteFilename)` — internal field/parameter names
- `ReviewLogService.loadTraversalLog()` returns `Map<String, DateTime>` but the internal field is `lastReviewed`

The naming inconsistency (public API says "traversal", internals say "review") creates conceptual noise but no functional bug.

### 2. Known limitation not documented user-facing

AnkiDroid review sessions do not update `review_log.md`. From Interest's traversal scorer, notes drilled in AnkiDroid appear perpetually unvisited and bubble to the top of the exploration queue. This is a known divergence documented in audit-2 but still absent from user-facing docs (`docs/resurface.md`) or any in-app guidance.

---

## Refactor Candidates

Ordered by traversal impact.

**RC-1: Unified `openNote(filePath)` in ResurfaceScreen** ✓ COMPLETE
- Implemented `ResurfaceScreenState.openNoteByPath(String filePath)`: problem note → card viewer; `collection:` → `onOpenEntity` callback → HomeScreen pushes EntityScreen; plain note → NoteDetailScreen.
- Updated `EntityScreen._navigateToNoteName`: fast path checks `allEntities`; vault scan fallback calls `onOpenNonEntityNote` callback.
- `onOpenNonEntityNote` in HomeScreen pops EntityScreen, switches to Notes tab, calls `openNoteByPath`.
- Both-note decision: `***` takes priority — opens in card viewer.
- Deviation: EntityScreen falls back silently (no snackbar) when `onOpenNonEntityNote` is null (acceptable for direct EntityScreen pushes without HomeScreen).

**RC-2: Extract `CollectionsScreen` from `_HomeScreenState`** ✓ COMPLETE
- Created `lib/features/entities/screens/collections_screen.dart` with all collection/entity UI and CRUD.
- `_HomeScreenState` now owns only: navigation shell, deep link handling, share sheet handling, entity navigation (`_openEntity`, `_openEntityByPath`), and settings/templates navigation.
- No behaviour changes — `EntityListController.onDataChanged` drives HomeScreen setState which propagates to CollectionsScreen via build.

**RC-3: Remove `VaultService.entitiesPath()` and `Interesting/Entities/` directory creation** ✓ COMPLETE
- Removed `entitiesPath()` from `VaultService`.
- Removed `edir` creation from `ensureVaultDirectories()`.
- Updated `vault_setup_screen.dart` user-facing text.

**RC-4: Deduplicate `_openObsidian()` in `home_screen.dart` and `sources_screen.dart`** ✓ COMPLETE
- Created `lib/shared/utils/obsidian_launcher.dart` with top-level `launchObsidianApp(BuildContext context)`.
- Removed `_openObsidian()` from both callers; both now call `launchObsidianApp(context)`.

**RC-5: Rename `ReviewLogService` → `TraversalLogService`** ✓ COMPLETE
- Renamed class and file (`traversal_log_service.dart`); deleted `review_log_service.dart`.
- Renamed `_RawEntry.lastReviewed` → `lastTraversed` (internal Dart field).
- Renamed `GraphScoringService.updateGraphScores(reviewedNoteFilename)` → `traversedNoteFilename`.
- Updated all four import sites (resurface_screen, graph_scoring_service, card_viewer_controller, settings_screen).
- YAML keys `last_reviewed` and `is_star` preserved unchanged for vault file backward compatibility.

---

## Deferred Items

**D-1: Both-note (has `collection:` AND `***`) canonical viewer.** EntityScreen shows entity view (body with `***` visible as raw text). Deck viewer shows front/back flip. No canonical correct behaviour defined. Requires architectural decision before acting.

**D-2: Android widget creates non-entity notes.** Widget writes `category: Default` but not `collection:`. Notes from the widget do not appear in Collections. Whether this is intentional or a gap requires the user's input.

**D-3: Home screen traversal features removed.** Card-peek hero and Worth Revisiting provided a curated traversal entry point. Their removal is a directional regression in traversal ergonomics. Whether to replace them (possibly within ResurfaceScreen's deck list) is a directional decision.

**D-4: Import pipeline scope.** Books/RSS/Bookmarks/Hardcover as import pipelines in a traversal tool — unchanged from audit-2. No new findings.

**D-5: Projects scope.** Task management vs. semantic workspace — unchanged from audit-2. No new findings.
