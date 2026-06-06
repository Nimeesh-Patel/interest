# Refactor Audit — Second Pass

This audit adds a second filter to the structural criterion from the first audit:

> Does this abstraction serve Interest's purpose as a **semantic traversal environment**?

The three-system model is now explicit:
- **Obsidian** — canonical editing environment
- **Interest** — semantic traversal environment
- **AnkiDroid** — retention drilling environment

A feature that passes the structural criterion (one reason to change) but fails the directional criterion (does not serve semantic traversal) is not a structural problem — it is a **directional misalignment**. This document records misalignments and proposes clarifications, not deletions.

Items addressed cleanly in Phase 3 are not reopened.

---

## README and CLAUDE.md Accuracy

### 1. README title: "Entity Tracker" — stale

`README.md` line 1:
```
# Entity Tracker
```

The system is no longer primarily an entity tracker. The entity graph is one subsystem in a semantic traversal environment. The name is the most visible signal of what the system is for; it currently signals the wrong thing.

**What to update:** The title and opening sentence in README.md. The phrase "Entity Tracker" appears in the title only; the body description is largely accurate.

---

### 2. README AppBar description has stale "Open Obsidian" entry

`README.md` lines 132–133:
```
screens/home_screen.dart — BottomNavigationBar shell (four tabs: Home, Notes, Entities, Projects);
                            AppBar: sensors → Sources, popup → Settings / Templates / Open Obsidian
```

"Open Obsidian" was moved from the AppBar popup to the Sources Inbox row. CLAUDE.md correctly records this (`**Obsidian launch** — moved from AppBar action to Sources Inbox row`), but README has not been updated. The discrepancy creates confusion about where the Obsidian launch lives.

**What to update:** README lib/ tree description for `home_screen.dart`: remove "Open Obsidian" from popup list.

---

### 3. README Architecture lib/ tree misses ~6 files added in Phase 3

`README.md` lines 100–135 describe the lib/ tree. The following files now exist and are not listed:

| File | Added by |
|---|---|
| `lib/features/entities/services/entity_file_parser.dart` | Phase 3 C3 |
| `lib/features/entities/services/entity_file_writer.dart` | Phase 3 C3 |
| `lib/features/entities/controllers/entity_list_controller.dart` | Phase 3 C5 |
| `lib/features/resurface/controllers/card_viewer_controller.dart` | Phase 3 C4 |
| `lib/features/resurface/services/ankidroid_sync_controller.dart` | Phase 3 R1 |
| `lib/shared/markdown/vault_scanner.dart` | Phase 3 C2 |
| `lib/features/resurface/screens/_backlinks_section.dart` | Post-Phase-3 |

Also not listed: `lib/features/resurface/screens/_note_md_helpers.dart` (if it exists).

**What to update:** README Architecture section lib/ tree. Update the entities and resurface subsystem descriptions to name the new controllers and split services.

---

### 4. `docs/ankidroid.md` write-back method reference is outdated

`docs/ankidroid.md` lines 42–43:
```
Write-back uses `patchFrontmatterField()` in `lib/shared/markdown/md_io.dart` — regex
in-place replacement, never rebuilds frontmatter.
```

Phase 3 R2 routed this write-back through `MarkdownStorageService.patchAnkiNoteId()`. The current code (`ankidroid_service.dart` lines 83, 93) calls `MarkdownStorageService.patchAnkiNoteId(note.sourcePath, newId)`. The `md_io.dart` reference is stale.

**What to update:** `docs/ankidroid.md` — replace the `patchFrontmatterField` sentence with a reference to `MarkdownStorageService.patchAnkiNoteId`.

---

### 5. `docs/entities.md` internal method list references wrong files

`docs/entities.md` lines 131–138 lists `_parseEntityFile`, `_patchEntityContent`, `_buildFrontmatter`, and `_semanticSections` as internal methods of `MarkdownStorageService`. After Phase 3 C3, these methods live in `EntityFileParser` (`entity_file_parser.dart`) and `EntityFileWriter` (`entity_file_writer.dart`). `MarkdownStorageService` calls through to them but no longer owns them.

**What to update:** `docs/entities.md` — update the "Internal" method table to name the correct owning classes.

---

### 6. CLAUDE.md enforcement point for invariant 3 and entity movie fields is partially stale

CLAUDE.md invariant 3:
```
Enforcement: `markdown_storage_service.dart`.
```

After Phase 3 C3, `_patchEntityContent` lives in `entity_file_writer.dart`. `MarkdownStorageService` delegates to it; the invariant is still enforced but the file named as the enforcement point is now the caller, not the implementation. This is a documentation precision issue, not a violation.

CLAUDE.md entity movie fields section:
```
Adding category-specific fields requires updating both `_parseEntityFile` and `_buildFrontmatter`
in `markdown_storage_service.dart`.
```

Both methods now live in `entity_file_parser.dart` and `entity_file_writer.dart` respectively.

**What to update:** CLAUDE.md — update the enforcement pointers for invariant 3 and the entity movie fields note to name `entity_file_writer.dart` and `entity_file_parser.dart`.

---

## Directional Alignment Audit

Each subsystem evaluated against: does this problem belong in a semantic traversal environment?

---

### Home dashboard — tab 0

**What it does:** Card-peek hero (top-priority problem note front), Worth Revisiting (entity list weighted by score + recency), Quick Add FAB, recent notes.

| Component | Directional verdict |
|---|---|
| Card-peek hero | **Aligns** — surfaces the most contextually relevant note for the traversal session |
| Worth Revisiting entities | **Aligns** — surfaces entities likely to be contextually relevant; supports traversal entry |
| Recent notes | **Aligns** — temporal anchor for resuming a traversal session |
| Quick Add FAB | **Ambiguous** — creating a new entity is an editing action (Obsidian territory). Quick capture is useful, but it means Interest is also acting as an authoring entry point, not just a traversal entry point |

**Clarification needed:** The Quick Add FAB makes the Home dashboard a mixed editing + traversal surface. This is a directional choice, not a structural problem. The question is whether fast entity creation belongs in a traversal app, or whether it belongs in Obsidian and the FAB should be reconsidered.

---

### Notes / Resurface — tab 1

**What it does:** Deck viewer (star notes with `***`), graph scoring (BFS proximity + time decay), review log (`review_log.md`), backlinks, wikilink traversal, inline note editor.

| Component | Directional verdict |
|---|---|
| Deck viewer | **Aligns** — surfaces problem-notes for engagement |
| Graph scoring + activation model | **Aligns** — surfaces contextually related notes based on what you've recently reviewed |
| Review log | **Aligns** — records traversal history to drive the graph scorer |
| Backlinks | **Aligns** — shows inbound edges in the wikilink graph; core traversal feature |
| Wikilink traversal | **Aligns** — in-app navigation along semantic edges |
| Note editor (`NoteEditScreen`) | **Ambiguous** — editing is Obsidian territory. The inline editor allows users to capture insight during traversal without switching apps, which is a valuable traversal workflow. But it means Interest owns a write path for arbitrary vault files, not just its co-owned files |

**Clarification needed:** `NoteEditScreen` is the one component in the Notes subsystem that blurs the Interest/Obsidian boundary. The correct framing: is in-context note editing during traversal a traversal feature, or is it a convenience that erodes the editing environment boundary? The current codebase treats it as a traversal feature. That choice should be made explicit.

---

### Entities + graph — tab 2

**What it does:** Entity CRUD (create, rename, delete), category management, tag management, entity graph display, wikilink traversal via `WikilinkText`, Grokipedia enrichment.

| Component | Directional verdict |
|---|---|
| Entity graph viewing (related entities, wikilinks) | **Aligns** — traversal of the knowledge graph |
| Entity detail view (Why Interesting, score, tags) | **Aligns** — reading a semantic node |
| Entity field editing (name, category, tags, notes) | **Ambiguous** — authoring is Obsidian territory. Interest's entity editor lets users annotate nodes encountered during traversal — valuable, but it means Interest co-owns write paths for its core node type |
| Category management | **Ambiguous** — organizing entities is more of an editing/curation action than traversal |
| Entity deletion | **Ambiguous** — destructive edit, not traversal |
| Grokipedia | **Aligns** — reading external context about an entity during traversal is a traversal activity; it never writes to the vault |
| Quick Add FAB (tab 2) | Same directional note as Home dashboard |

**Clarification needed:** Interest necessarily owns some entity write paths (this is documented in CLAUDE.md as "co-ownership"). The directional question is whether the full entity editing workflow (category management, bulk rename, delete) belongs in the traversal environment. These are authoring/curation tasks. Clarifying which entity mutations are "traversal annotations" vs. "editorial curation" would sharpen the directional model.

---

### Projects — tab 3

**What it does:** Task tracking (todo-style), list management (checklist-style), project file management.

| Component | Directional verdict |
|---|---|
| Task completion, reordering | **Does not align** — task management is not semantic traversal |
| Project list browsing | **Partially aligns** — a project file can be a semantic workspace that links to entities. Browsing project context during traversal is valid. But executing tasks and managing completion state is not. |

**Clarification needed:** Projects as semantic workspaces (collections of related entities and notes) could serve a traversal purpose. Projects as to-do lists do not. These two roles are merged in the current subsystem. The directional question: is a project in Interest a "context for traversal" or a "task management container"? The current implementation handles both.

---

### Books subsystem

**What it does:** Book model, Hardcover sync (bidirectional), Readwise highlight import, ReadEra import.

| Component | Directional verdict |
|---|---|
| Book detail viewing (highlights, metadata) | **Aligns** — a book is a semantic object in the knowledge graph; reading its highlights supports traversal |
| Hardcover sync (bidirectional reading state) | **Does not align** — syncing reading progress/status is a lifecycle management task (editing environment) |
| Readwise highlight ingestion | **Partially aligns** — importing highlights creates vault content; it is more of an authoring pipeline than traversal |
| ReadEra highlight import | Same as Readwise |
| Book ↔ entity graph participation | **Not yet implemented** per CLAUDE.md: "books do NOT participate in entity graph yet" — this is the most clearly traversal-adjacent capability, and it is deferred |

**Clarification needed:** Books are enrichment objects in the current model. They contain potentially traversal-relevant content (highlights, notes), but the sync machinery (Hardcover, Readwise, ReadEra) is import/enrichment pipeline work, not traversal. The three-system model would say: enrichment pipelines write to the vault (editing environment concern); Interest reads and traverses the resulting files. The current architecture does both in Interest.

---

### RSS / Articles

**What it does:** RSS feed ingestion, article storage in `Interesting/Articles/`, Letterboxd movie import.

| Component | Directional verdict |
|---|---|
| Browsing imported articles | **Aligns** — reading article content in the vault context supports traversal |
| RSS feed configuration, sync, ingestion pipeline | **Does not align** — feed management and ingestion are authoring/import tasks |
| `ArticleStorageService` writes | Same directional note as Books enrichment |

**Clarification needed:** RSS in Interest serves as an import pipeline that creates traversal-eligible content. The pipeline itself (fetch, parse, store) does not serve semantic traversal; it populates the vault so traversal can happen. Whether this pipeline belongs in Interest or in a separate ingestion tool is a directional question.

---

### AnkiDroid sync

**What it does:** One-way push of star notes to AnkiDroid, `anki_note_id` write-back, Obsidian deep link in card front, wikilink-to-deeplink transformation.

| Component | Directional verdict |
|---|---|
| One-way vault → AnkiDroid push | **Aligns with three-system model** — this is the defined boundary: Interest pushes to AnkiDroid |
| Wikilink → `interest://note/` deep links in cards | **Aligns** — enables navigation back from retention environment to traversal environment |
| Obsidian link in card front | **Aligns** — enables navigation from retention environment to editing environment |
| `anki_note_id` write-back | **Aligns** — minimum necessary write-back to maintain sync identity |

**No clarification needed.** This subsystem is the cleanest expression of the three-system model in the current codebase.

---

### Bookmarks — X share sheet

**What it does:** Receives `ACTION_SEND` intent from X/Twitter; fetches note content via nitter/oEmbed pipeline; writes to vault root.

| Component | Directional verdict |
|---|---|
| Vault note creation from share | **Does not align** — capturing content from an external share sheet is an authoring/import action |
| Resulting note (with `***` separator) as traversal content | **Aligns** — once in the vault, a bookmark note can be reviewed in the deck viewer |

**Clarification needed:** Bookmarks are an import pipeline that creates traversal-eligible content, not a traversal feature itself. It is the same directional question as RSS. The share-sheet capture workflow (bookmark creation from X) is at minimum an "editing environment" action. Whether Interest should own this pipeline or whether a separate tool should write to the vault is a directional question.

---

### Sources screen — integration hub

**What it does:** Navigation hub for Hardcover, Articles, Readwise, Bookmarks, Obsidian, AnkiDroid rows; "Sync all" button.

| Component | Directional verdict |
|---|---|
| AnkiDroid row (sync to retention environment) | **Aligns** — sends content to the correct destination environment |
| Obsidian row (launch editing environment) | **Aligns** — opens the editing environment from within the traversal environment |
| Hardcover, Articles, Readwise, Bookmarks rows | **Does not align** — these are import/sync pipelines, not traversal actions |

**Clarification needed:** The Sources screen is an operational hub for import pipelines. Its presence in Interest is a consequence of Interest currently owning enrichment pipelines that arguably belong elsewhere. The two rows that align with the three-system model (AnkiDroid and Obsidian) would remain even if all import pipelines were moved. The four import rows (Hardcover, Articles, Readwise, Bookmarks) are directionally ambiguous at the screen level — they're present because Interest currently owns those pipelines.

---

## Dual-Scheduling Conflict

Interest and AnkiDroid both handle scheduling of problem notes (star notes with `***`). This section documents whether they conflict, complement, or duplicate each other.

### What each system schedules and on what criteria

**Interest-native scheduler** (`GraphScoringService` + `ReviewLogService` + `review_log.md`):
- **Scope:** star notes AND activated non-star notes (linked notes within `[minDegree, maxDegree]` hops of a reviewed star note)
- **Criteria:** `daysSinceReview + decayedGraphScore`; graph score is boosted by BFS proximity to recently reviewed notes; decays exponentially at λ=0.1/day; late-review penalty is capped
- **Purpose:** surfaces contextually related material based on what you have been thinking about — a graph-topological, recency-weighted exploration queue
- **State written to:** `review_log.md` — records `last_reviewed`, `graph_score`, `last_boosted`, `activated_by`, `scheduled_interval`

**AnkiDroid scheduler** (FSRS or SM-2):
- **Scope:** star notes only (those with `anki_note_id` after sync)
- **Criteria:** recall probability decay modeled from review history; due date computed per card
- **Purpose:** optimizes long-term retention — a memory consolidation queue
- **State written to:** AnkiDroid's internal database. Never written to vault.

### Do they conflict, complement, or duplicate each other?

They are **mechanically independent** — they run in separate processes and share no state. They are **conceptually different in purpose**: Interest surfaces notes for semantic exploration; AnkiDroid surfaces notes for retention drilling. A user could reasonably want both activities.

However, their **review state diverges**:

1. A note reviewed in AnkiDroid does not update `last_reviewed` in `review_log.md`. From Interest's perspective, the note was never reviewed. This causes Interest's scheduler to treat heavily-drilled notes as perpetually stale, pushing them to the top of the exploration queue and spuriously activating their neighbours.

2. A note reviewed in Interest's card viewer does not update AnkiDroid's scheduling state. The two intervals walk independently.

3. If a user primarily uses AnkiDroid for drilling and uses Interest for contextual exploration, `review_log.md` will correctly accumulate Interest-specific review history. The divergence is only a problem if the user expects Interest's scheduler to know about AnkiDroid sessions.

### Whether the Interest-native scheduler still serves a purpose

Yes, with a clarification: the Interest-native scheduler and AnkiDroid serve **different cognitive activities**. AnkiDroid is for retention (drilling a specific card until recalled). Interest's graph scorer is for contextual surfacing (showing you what is likely to be relevant given your recent intellectual trajectory). These are complementary. The scheduler in Interest should be understood as a **contextual relevance ranker**, not a retention scheduler.

The risk of confusion is in the label "review" — Interest calls card engagement a "review" and writes `last_reviewed` to the log. If users understand "review" to mean the same thing in both systems, they will be confused when AnkiDroid reviews do not propagate to Interest. The concept should be clarified: Interest tracks **traversal sessions**, not reviews in the FSRS sense.

### Whether `review_log.md` state can drift in ways that create confusion

Yes, in one specific scenario: a user syncs many notes to AnkiDroid and completes a large AnkiDroid session. Interest's graph scorer then treats all those notes as "never touched" and generates a queue dominated by them. The backfill activations (non-star notes activated by these notes) will also dominate. The Interest queue will appear stale relative to the user's actual engagement.

This is not a bug — it is a consequence of the two systems being intentionally independent. But it is a user experience friction point that should be documented as a known limitation.

---

## New Code Quality Audit

The following features were added since the previous audit. Evaluated for structural quality using the same criteria.

---

### 1. Backlinks computation

**Files:** `ResurfaceService.getBacklinks` (`resurface_service.dart` lines 82–119), `BacklinksSection` (`_backlinks_section.dart`).

**Single reason to change:** `getBacklinks` changes when the vault scan logic changes or when `ResurfaceNote` construction changes. `BacklinksSection` changes when the backlinks UI changes. Both are clean.

**Boundary:** `getBacklinks` is read-only, uses `VaultScanner` (shared utility), uses `noteKey()` (canonical identity). `BacklinksSection` loads its own vault path via `VaultService.getVaultPath()` — acceptable since it is a self-contained widget that cannot receive the path from a parent that also doesn't have it.

**One structural issue: `ResurfaceNote` construction is triplicated.**

The same 10-field `ResurfaceNote(...)` constructor block appears in three methods of `ResurfaceService`:
- `getAllNotes()` (lines ~55–72)
- `getBacklinks()` (lines ~96–113)
- `loadSingleNote()` (lines ~128–147)

Each block reads `splitFrontmatter`, `parseYamlMap`, `splitFrontBack`, `parseDeckMetadata`, and builds the same set of optional fields from the same YAML key names. If a new field is added to `ResurfaceNote` (e.g., a new frontmatter key), all three sites must be updated. This is a duplicate-solution pattern.

A private `static ResurfaceNote _parseNoteFile(File entry, String content)` factory would be the correct fix: take the file and its content, return a `ResurfaceNote`. All three callers reduce to reading the file then calling the factory.

**One subtle issue: `resolveWikilink` does not use `VaultScanner`.**

`ResurfaceService.resolveWikilink` (lines 26–33) calls `Directory(vaultPath).list(recursive: true)` directly. All other vault scans in the codebase go through `VaultScanner`. The reason `resolveWikilink` does not is that it intentionally uses NO folder exclusions. `VaultScanner.scan(vaultPath)` with no `excludedFolders` argument would produce the same result. This is a minor inconsistency — `resolveWikilink` should use `VaultScanner` for uniformity, passing an empty exclusion set explicitly.

**`extractWikilinks` does not handle aliases — silent mismatch in `getBacklinks`.**

`md_utils.extractWikilinks(text)` uses `RegExp(r'\[\[([^\]]+)\]\]')` — this returns the full bracket content including any pipe and alias. For `[[Note Name|alias]]`, it returns `"Note Name|alias"`, not `"Note Name"`. `getBacklinks` compares `l.toLowerCase() == targetKey`, so a backlink written as `[[Target Note|alias]]` will NOT match the target note's key. This is a pre-existing issue in `extractWikilinks`, not introduced by backlinks, but it silently drops aliased backlinks. The fix belongs in `extractWikilinks`: strip the alias portion before returning.

---

### 2. `obsidianUri` utility

**File:** `md_utils.dart` lines 196–203.

**Single reason to change:** the `obsidian://open` URI scheme changes.

**Location:** correct — `md_utils.dart` is the canonical home for pure text and URI utilities with no I/O.

**Callers:** `AnkiDroidService.syncVault` (Anki card front link) and `ResurfaceScreenState.launchObsidianForCurrentNote` (in-app Obsidian launch button). Both callers use the same function — no duplication.

**No issues.** This is a clean single-purpose utility.

---

### 3. Deep link to specific note

**Files:** `MainActivity.kt` lines 74–83, 194–199 (Android side); `home_screen.dart` (Flutter receive); `resurface_screen.dart` `openNoteByName` (resolution).

**Android side:** `extractDeeplinkNote` is a private method with a single purpose: parse `interest://note/<name>` from an intent. Clean. The `pendingDeeplinkNote` state and the two channels (cold start via `getInitialDeeplinkNote`; warm start via `openNote` push) correctly cover both launch modes.

**Flutter side:** `HomeScreen` receives the deep link, switches to tab 1, and calls `ResurfaceScreenState.openNoteByName`. The two-step resolution (memory fast path → vault-wide fallback) is correct and well-documented in `docs/resurface.md`.

**Multi-concern in `MainActivity.kt`:** `MainActivity` still handles three independent concerns: share intent, deep link, and AnkiDroid bridge. This was listed as Multi-Problem Artifact §5 in the previous audit and deferred. The deep link feature added a third method channel handler to the same class, increasing the accumulation. The finding is unchanged: `MainActivity` is a structural multi-problem artifact. The deep link implementation is otherwise clean.

**No new issues specific to this feature.** The boundary is correct: Android decodes the URI, Flutter resolves the note, routing is consistent with in-app wikilink navigation.

---

### 4. Note name as Obsidian link in Anki cards

**File:** `ankidroid_service.dart` lines 42–115.

**Single reason to change:** the card front HTML format changes (Anki deck format, Obsidian link placement, CSS).

**`_wikilinkToAnkiLink` — unresolved duplicate from Duplicate Solutions §4.**

The previous audit (Duplicate Solutions §4) identified `AnkiDroidService._wikilinkToAnkiLink()` as a reimplementation of the `[[...]]` wikilink regex. Since then, `md_utils.dart` has gained `substituteWikilinks` and `plainTextWikilinks`, both of which use the same regex pattern: `\[\[([^\]|]+)(?:\|([^\]]+))?\]\]`.

The three functions that use this pattern are now:
- `md_utils.plainTextWikilinks` — strips to display text
- `md_utils.substituteWikilinks` — rewrites to `wikilink:` scheme for flutter_markdown
- `AnkiDroidService._wikilinkToAnkiLink` — rewrites to `interest://note/` scheme for AnkiDroid HTML

The regex is identical across all three. `_wikilinkToAnkiLink` differs only in output scheme. It could be expressed as `substituteWikilinks` with a configurable scheme, or as a call to a shared `rewriteWikilinks(text, mapper)` utility. The private location (inside `AnkiDroidService`) is a structural misalignment: it belongs in `md_utils.dart` alongside the other two wikilink rewriters.

Note that `_wikilinkToAnkiLink` correctly handles aliases (separates target from display). `extractWikilinks` does not (returns `"Name|alias"` as the target). The two code paths handle the same syntax differently — a separate inconsistency.

**Hardcoded HTML in Dart string:** The `obsLinkHtml` string (lines 53–56) contains inline CSS with literal hex-style style values (`font-size:0.75em`, `opacity:0.6`). There is no test for the output format. If the Anki card template changes, this string must be found and edited manually. This is a fragility, not a violation — there is no canonical Anki card style system to reference. It is noted as a maintenance risk.

---

## Post-Phase-3C Residual Issues

These items were explicitly deferred at the end of the previous refactor. Evaluated against the directional shift.

---

### `sortEntities` in `MarkdownStorageService`

Status: **unchanged; directional shift does not affect position.**

`sortEntities` was kept in `MarkdownStorageService` as the CLAUDE.md enforcement point for the sorting rule. The entity graph is a core traversal feature, and sorting the entity list is how users navigate it. `sortEntities` should remain where it is.

---

### `CardViewerController` setState-only constraint

Status: **unchanged; remains acceptable.**

The setState-only state management constraint means `CardViewerController` is a plain Dart class (no `ChangeNotifier`, no streams). The testability tradeoff was noted. The directional shift does not change this — the card viewer is a traversal-environment component and its testing constraint is a known, documented limitation.

---

### `EntityListController.onDataChanged` coupling to `HomeDashboard`

Status: **no worse structurally; directionally more visible.**

`EntityListController.onDataChanged` triggers a reload in the Home dashboard. This coupling exists because `HomeDashboardScreen.reload()` is called externally after entity mutations. The directional shift makes this coupling more visible: the Home dashboard blends entity data (Worth Revisiting) with notes data (card peek). The mixed data sources on the dashboard are the root cause of the coupling. This is a directional-alignment question about the Home dashboard's scope, not a new structural problem.

---

### `LetterboxdAdapter` writing to vault root

Status: **directional shift makes the question sharper.**

`LetterboxdAdapter` writes movie files to the vault root, bypassing `MarkdownStorageService`, and builds its own movie index. This was listed as a deferred architectural direction question: are movies entities (with `alias`, graph participation) or a separate projection?

The three-system model sharpens this: `LetterboxdAdapter` is an RSS import pipeline (authoring/enrichment), not a traversal feature. If movies are meant to be traversal objects (searchable, graphable, reviewable via deck viewer), they should participate in the entity graph and their import pipeline should go through `MarkdownStorageService`. If they are not traversal objects, their presence in the vault root (alongside user entities) is a namespace collision.

The directional model implies a decision is needed: either migrate movies to full entities (with `alias`, through `MarkdownStorageService`) or treat them as archived content (a separate subdirectory, not mixed with entities). Currently they are neither cleanly, which is the original structural complaint plus a directional one.

---

## Emerging Patterns from the Three-System Model

The three-system model implies three boundary patterns. This section documents where those patterns hold and where they are blurred.

### Pattern 1: Interest reads vault files; Obsidian writes them

**Where this holds:** `ResurfaceService` is strictly read-only. `GraphScoringService` never writes vault notes. Book enrichment (Readwise, Hardcover, ReadEra) writes through `BookStorageService` via `patchFields` — controlled and partitioned.

**Where this is blurred:**

1. **`NoteEditScreen`** writes any vault `.md` file passed to it. This is the most direct write from a traversal context into the editing environment's territory. The current framing ("in-context annotation during traversal") is coherent, but it means Interest has a general-purpose vault file writer. The boundary is permeable by design.

2. **Entity CRUD** (`MarkdownStorageService.saveData`) writes entity files in `Interesting/Entities/`. This is the "co-ownership" model documented in README. It is not a boundary violation, but it means Interest is both reading and writing its core semantic objects.

3. **`XBookmarkStorageService`** writes to vault root from a share-sheet intent — Interest creating vault files in response to external input. This is an authoring action driven from the traversal environment.

**These are documented design choices, not undocumented violations.** The directional model asks: should these write paths be reconsidered as the system matures toward a cleaner traversal role? The current codebase answers: Interest co-owns entity files and note files it created, but reads the rest. This is a defensible position.

---

### Pattern 2: Interest pushes to AnkiDroid; AnkiDroid never writes back

**Where this holds:** perfectly. `AnkiDroidService.syncVault` is the only write direction. The only write-back from the sync is `anki_note_id` into the vault's own frontmatter — which is an entity property owned by Interest, not an AnkiDroid state. `review_log.md` is never touched by AnkiDroid. No AnkiDroid scheduling state (intervals, ease factors, due dates) enters the vault.

**One implicit blurring:** deep link navigation from AnkiDroid into Interest (`interest://note/<name>`) changes the traversal state in Interest (switches tab, opens a note). This is not a write path, but it is AnkiDroid driving Interest's navigation state. It aligns with the three-system model — AnkiDroid launching Interest is the intended use of deep links — but it is worth noting that AnkiDroid can change what note Interest is displaying without Interest having any write path in return.

---

### Pattern 3: Deep links connect the three systems

**Where this holds:** three link types exist:

| From | To | Mechanism | Status |
|---|---|---|---|
| AnkiDroid card | Interest note | `interest://note/<name>` deep link | Implemented, clean |
| Interest/AnkiDroid card | Obsidian note | `obsidian://open?vault=<v>&file=<f>` | Implemented, clean |
| Interest Notes AppBar | Obsidian note | `obsidianUri()` + `url_launcher` | Implemented, clean |

All three deep-link paths use `obsidianUri()` from `md_utils.dart` (or the `interest://note/` scheme via `_wikilinkToAnkiLink`). The cross-system navigation fabric is coherent.

**One asymmetry:** there is no deep link from Obsidian back to Interest. A user reading an entity in Obsidian has no one-tap path back to the Interest traversal view for that entity. This is not a bug — Obsidian is the editing environment and does not need to drive the traversal environment. But it is a gap in the three-system navigation fabric that could be filled with an Obsidian plugin or a URI scheme entry point.

---

## Summary Table

| Finding | Type | Urgency |
|---|---|---|
| README title "Entity Tracker" | Documentation accuracy | Low — cosmetic but signals wrong purpose |
| README AppBar "Open Obsidian" in popup | Documentation accuracy | Low |
| README lib/ tree missing 6 files | Documentation accuracy | Low |
| `docs/ankidroid.md` stale `patchFrontmatterField` reference | Documentation accuracy | Medium — misleads on boundary violation R2 |
| `docs/entities.md` stale internal method locations | Documentation accuracy | Medium — misleads on enforcement points |
| CLAUDE.md invariant 3 / movie fields enforcement pointers | Documentation accuracy | Low |
| Quick Add FAB directional role | Directional clarification | — |
| `NoteEditScreen` traversal-vs-editing boundary | Directional clarification | — |
| Entity CRUD in traversal environment | Directional clarification | — |
| Projects scope (workspace vs. task list) | Directional clarification | — |
| Books/RSS/Bookmarks as import pipelines | Directional clarification | — |
| AnkiDroid sync — cleanest three-system alignment | Strength to preserve | — |
| Dual-scheduling divergence (review_log.md vs. Anki state) | Conceptual clarity | Medium — user confusion risk |
| `ResurfaceNote` construction triplicated in `ResurfaceService` | Structural | Medium |
| `extractWikilinks` silently drops aliased wikilinks | Structural (pre-existing) | Medium |
| `resolveWikilink` not using `VaultScanner` | Structural (minor) | Low |
| `_wikilinkToAnkiLink` regex duplicates `md_utils` pattern | Structural (from prior audit §4) | Low |
| `MainActivity.kt` multi-concern (unchanged) | Structural (deferred) | Low — unchanged since prior audit |
| `LetterboxdAdapter` direction question sharpened | Directional + structural | Medium |
