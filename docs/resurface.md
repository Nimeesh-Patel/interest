# Notes / Resurface Subsystem

## Purpose

Vault-wide semantic notes layer. Notes outside `Interesting/` are understood as **problem-oriented epistemic artifacts** — evolving documents that encode problem-situations, conjectures, and partial resolutions. This subsystem projects them into three surfaces: a flashcard-style **deck viewer** (for `***`-separated notes), a **note browser with full-text search**, and an **inline note editor** that writes directly back to vault files.

The `***` horizontal rule is the semantic separator between a problem-situation (front) and its conjecture or resolution (back). The resurfacing viewer projects these pairs into a lightweight front/back viewer.

---

## Architectural role

```
vault notes
  → ResurfaceService.getAllNotes()   — recursive read + frontmatter strip + separator detection
  → List<ResurfaceNote>              — in-memory projection (all vault notes)
      ↳ .where(hasCard) → List<ResurfaceCard>   — deck list and card viewer source
      ↳ search filter → List<ResurfaceNote>     — inline search results
  → ResurfaceScreen                  — deck list + inline search; internal nav stack
      → _NoteCardViewerBody          — card viewer body; no Scaffold
      → NoteDetailScreen             — note body; tap-to-reveal or plain; no Scaffold; recursive
  → NoteEditScreen                   — full file editor; Navigator.push; writes vault file
```

Session state (card position, back-revealed flag, search query) is never written to the vault or to SharedPreferences.

---

## Ontology

### ResurfaceNote

A `ResurfaceNote` is a projection of any vault note passing folder exclusions, regardless of whether it has a `***` separator.

| Field | Value |
|---|---|
| `sourcePath` | Absolute path to the source file |
| `sourceFile` | Basename of the source file (e.g. `epistemology.md`) |
| `body` | Full body after frontmatter strip; used for search |
| `hasCard` | `true` when the body has a valid `***` separator with non-empty front and back |
| `front` | Non-null iff `hasCard`; content above the first `***`, trimmed |
| `back` | Non-null iff `hasCard`; content below the first `***`, trimmed |
| `decks` | List of deck names from `deck:` frontmatter; `[]` if absent |

### ResurfaceCard

A `ResurfaceCard` is a `ResurfaceNote` projected to a single-scan representation used by the card viewer. It is a strict subset: all `ResurfaceCard` instances have a corresponding `ResurfaceNote` with `hasCard: true`. `ResurfaceCard` has no identity anchor and is not stored or indexed.

---

## Deck metadata

Notes may declare optional deck membership via the `deck:` YAML frontmatter field:

```yaml
---
deck: epistemology
---
```

or for multiple decks:

```yaml
---
deck:
  - epistemology
  - programming
---
```

**Decks are resurfacing projection labels, not ownership containers.** A note belongs to its canonical Markdown file — decks only affect how the resurfacing viewer filters its display.

Deck membership is parsed at scan time via `parseDeckMetadata()` in `md_utils.dart`. Supports: absent → `[]`, String scalar → single-element list, YAML list → all elements as strings.

**A note may belong to zero, one, or many decks.** No exclusive ownership; overlapping semantic topology is expected.

### Deck navigation (ResurfaceScreen)

`ResurfaceScreen` shows a deck list. Each row is a deck name and card count. Tapping a row pushes a `_CardViewerRoute` onto `ResurfaceScreenState`'s internal nav stack with the cards pre-filtered to that deck.

The deck list always contains:
1. **All Notes** (bold) — all cards from the scan, regardless of `deck:` metadata
2. **Default** — cards whose `decks` list is empty (i.e., no `deck:` frontmatter); shown only if at least one such card exists
3. Named decks, one per distinct `deck:` value found, sorted A→Z

A note may appear in multiple named deck rows (if its `deck:` list has multiple entries) and also in "All Notes". The "Default" and named deck rows are mutually exclusive — a card either has decks or it doesn't.

Tapping a row pushes a `_CardViewerRoute` onto `ResurfaceScreenState`'s internal nav stack (no `Navigator.push`). Card state — shuffled cards, current index, back-revealed flag — lives in `ResurfaceScreenState` and is preserved while navigating into and back from note details within the same session. Cards are shuffled when the deck is opened (unseeded random; order is random each session). Card state is discarded when returning to the deck list.

### What decks are NOT

- No deck database. Decks are frontmatter strings; they are not stored, indexed, or managed by the app.
- No deck hierarchy. There are no parent/child deck relationships.
- No scheduling by deck. Deck membership has no effect on review order, intervals, or due dates (none of which exist).
- No card ownership transfer. The canonical owner of a note is the file; decks are labels for projection filtering only.

---

## Separator detection

**Trigger:** a line matching `^\*{3,}\s*$` — three or more asterisks, optional trailing whitespace, nothing else on the line.

**Only the first matching separator is used.** If a note contains multiple `***` lines, extraction stops at the first one.

**Code-fence exclusion:** the scanner tracks code fence state. Any line whose left-trimmed content starts with ` ``` ` toggles `inCodeFence`. A `***` line inside a code fence is not treated as a separator.

**Empty-block guard:** if either `front` or `back` is empty after trimming, no card is produced. A `***` at the very start of the body (empty front) or at the very end (empty back) is silently skipped.

**YAML frontmatter:** `splitFrontmatter()` strips the YAML block before scanning. A `---` delimiter in the frontmatter is invisible to the extractor. `***` is used — not `---` — to avoid visual ambiguity with frontmatter delimiters when authoring.

**Exception handling:** any file that cannot be read, or whose content causes a parse error, is silently skipped. `ResurfaceService` never throws.

---

## Vault scan scope

`ResurfaceService.getAllNotes()` calls `Directory(vaultPath).list(recursive: true)` and processes every `.md` file found.

**Excluded folders:** any file whose relative path contains a segment matching an excluded folder name is skipped. Matching is exact and segment-based — the full path is split on the OS separator, the filename (last segment) is dropped, and each remaining segment is checked against the exclusion list.

Default excluded folders: `Interesting`, `.obsidian`, `Templates`, `Attachments`.

- `Interesting` is excluded because it contains the app's structured semantic objects (entities, books, Anki cards, projects) — schema-driven files with YAML frontmatter and semantic sections that are not the raw epistemic material the resurfacing viewer is designed for.
- `.obsidian` and `Templates` and `Attachments` are excluded because they contain configuration, templates, and binary assets rather than notes.

**Changing the exclusion list:** Settings → Resurface. Stored in `Interesting/System/integrations.md` under `## Resurface → excluded_folders:` via `IntegrationsConfigService`. The default list is used if the section is absent or empty.

---

## ResurfaceService API

```dart
class ResurfaceService {
  static Future<List<ResurfaceNote>> getAllNotes(
    String vaultPath, {
    List<String> excludedFolders = _defaultExcludedFolders,
  }) async

  static Future<String?> resolveWikilink(
    String vaultPath,
    String targetName,
  ) async
}
```

`getAllNotes()` returns every vault note that passes folder exclusions. Each `ResurfaceNote` has `hasCard`/`front`/`back` populated iff a valid `***` separator was found. Returns an empty list on any top-level I/O error; never throws.

`resolveWikilink()` searches the whole vault recursively — no folder exclusions — for a `.md` file whose basename-without-extension matches `targetName` case-insensitively. Returns the first matching absolute path, or `null` on no match or any I/O error. Never throws.

`_extractFrontBack()` is private. It is used internally by `_load()` on `ResurfaceScreen` to derive `_cards` from `_allNotes`. It takes a file path and raw file content and returns a `ResurfaceCard?`. Returns `null` on any of: no separator found, empty front, empty back, any exception during parsing.

---

## ResurfaceScreen behaviour

`ResurfaceScreen` is a primary navigation tab ("Notes"). It has **no Scaffold of its own** — HomeScreen provides the AppBar. `ResurfaceScreen` renders a deck list body or search results body, depending on state.

### Load

On `initState`, the screen calls `VaultService.getVaultPath()`, then `IntegrationsConfigService.load()` to read the excluded folders, then `ResurfaceService.getAllNotes()`. `_cards` is derived by filtering `_allNotes` to those with `hasCard: true` and mapping to `ResurfaceCard`. Single scan; no second pass.

### States

| Condition | Displayed |
|---|---|
| Vault path not configured | `EmptyState` with error message |
| Scan in progress | `CircularProgressIndicator` |
| Scan complete, zero cards | `EmptyState` with hint to add a `***` separator |
| Cards loaded | deck list (or search results if search is active) |

### Deck list layout

`SafeArea(top: false)` → `ListView.builder` of `ListTile`s, one per deck:
- **"All Notes"** row (always first, bold title): total card count
- **"Default"** row (second, if any undecked cards exist): count of cards with `decks: []`
- **Named deck rows** (A→Z): count of cards that include that deck name

Trailing text shows the card count in `AppColors.textTertiary`. Tapping any row pushes a `_CardViewerRoute` onto `ResurfaceScreenState`'s internal nav stack and shows the card viewer.

### Inline search

A search icon appears in HomeScreen's AppBar when the deck list is showing and the vault is loaded. Tapping it toggles `_searchActive` and expands an inline `TextField` below the AppBar.

**Query matching:** case-insensitive; matches the filename (without extension) or any line of the note body. Results are shown live as the user types.

**Result list:** each `ListTile` shows the filename as title, a one-line body snippet containing the matched term as subtitle, and a small `auto_awesome` icon in the trailing position for `***` notes.

**Tapping a result:**
- `***` note → pushes a `_CardViewerRoute` with a single-card deck (the matched note's card)
- plain note → pushes a `_NoteDetailRoute` which opens `NoteDetailScreen`

**Empty query:** no results shown (not "No notes match"). **No-match query:** "No notes match" centered text.

Tapping X inside the search field clears the query but keeps the search bar open. Tapping the close icon in HomeScreen's AppBar collapses the search bar and returns to the deck list. `resetStack()` also collapses search.

### Card viewer (`_NoteCardViewerBody`)

An in-place body widget (`_NoteCardViewerBody`, private stateless). No Scaffold — HomeScreen's AppBar shows the deck name as title. All mutable state (`_viewerCards`, `_viewerIndex`, `_viewerBackRevealed`) lives in `ResurfaceScreenState` and is passed in as props; this lets card position survive wikilink navigation into and back from note detail without losing the current card.

**AppBar**: provided by HomeScreen; title = deck name. A pencil icon appears when a current card has a resolved file path; tapping it calls `openEditForCurrentNote(context)`.

**Card layout** (`SingleChildScrollView` with 20px padding):
- **Source title**: filename without extension, rendered as `# heading` via `MarkdownBody`
- **Front**: rendered via `MarkdownBody` (theme `onSurface` colour)
- **"tap to reveal"** hint when back is hidden (centred italic `AppColors.textTertiary`)
- **Divider** (`AppColors.border`) + **back** when revealed (back rendered with `AppColors.textPrimary`)

**Bottom row**: prev `IconButton` — counter `"N / total"` — next `IconButton`. Counter is in this row, not in the AppBar.

**Interaction**: tap anywhere on the card area toggles `_backRevealed`. Swipe left (velocity < −200) advances; swipe right (velocity > +200) retreats. Navigation resets `_backRevealed` to `false`.

**Session state**: all card viewer state is owned by `ResurfaceScreenState`. Returning to the deck list (back to root or tapping the Notes tab icon) clears the viewer state via `resetStack()`.

### NoteDetailScreen

An in-place body widget. No Scaffold — HomeScreen's AppBar shows the note's filename (without extension) as title. Receives `filePath` and an `onNavigateToNote` callback; does not hold a vault path.

On load, `splitFrontBack(body)` is called. If the note has a valid `***` separator, it renders as a single flashcard with tap-to-reveal. If not, it renders the full body as plain Markdown.

A pencil icon appears in HomeScreen's AppBar when a `NoteDetailScreen` is active. Tapping it opens `NoteEditScreen` for that note's file.

After `NoteEditScreen` returns with `true` (saved), `ResurfaceScreenState._reloadAfterEdit(filePath)` is called. If the current route is a `_NoteDetailRoute`, it increments `_detailVersion` (which changes `NoteDetailScreen`'s `ValueKey`, forcing `initState` to re-read the file). If the current route is a `_CardViewerRoute`, `_reloadCard(filePath)` re-parses only the edited file and updates `_viewerCards[idx]` in-place (or removes the card if the separator was deleted).

Wikilink taps call `onNavigateToNote(targetName)` → `ResurfaceScreenState._handleWikilinkTap()`, which resolves the path and pushes a new `_NoteDetailRoute` onto the internal stack. Multiple wikilink hops accumulate as stacked `_NoteDetailRoute` entries; each press of the AppBar back button pops one level.

---

## Note editing (NoteEditScreen)

`NoteEditScreen` is a proper pushed route (`Navigator.push`). It receives a `filePath` and writes back to that exact path on save. It never touches other vault files.

### Edit modes

Three modes, selected automatically on load:

| Mode | Condition | UI |
|---|---|---|
| **Structured** | note has a valid `***` separator | Two collapsible sections: "Problem" (front) and "Idea" (back) |
| **Plain** | no `***` separator | Single body `TextField` |
| **Full note edit** | user selects from three-dot menu | Raw file content including frontmatter, monospace font, no toolbar |

Mode switch to full edit populates the raw controller from `_buildCurrentContent()` (not stale disk content) and updates `_initialFullEdit`, preventing spurious dirty detection.

### Save semantics

`_buildCurrentContent()` reconstructs the full file from the active mode's controllers, prepending frontmatter verbatim. Frontmatter is never modified in structured or plain mode — only the body is edited. Full edit mode writes the raw controller text as-is.

Save calls `File(widget.filePath).writeAsString(content)` and pops with `true`. Cancel with unsaved changes shows "Discard changes?" confirm dialog before discarding.

### Toolbar

A formatting toolbar (44px, pinned above keyboard) appears in structured and plain modes. Buttons: **B** (`**...**`), **I** (`*...*`), **U** (`<u>...</u>`), **—** (`\n---\n`), **T** (heading sheet H1–H5), **Tт** (no-op placeholder), **+** (insert sheet: bullet/numbered/wikilink). Each acts on the currently focused controller.

---

## Markdown rendering

All content — source title, front, back — is rendered via `flutter_markdown`'s `MarkdownBody` with explicit sizes: H1 22px w600 (letter-spacing −0.3, line height 1.3), H2 19px w600 (1.35), H3 16px w600 (1.4), body/listBullet 16px (line height 1.6). All text uses `AppColors.textPrimary`; links use `AppColors.accent` (no underline).

`[[wikilinks]]` in front and back are pre-processed by `substituteWikilinks()` before rendering. They appear as tappable links in the theme's primary/accent colour. See [§ Wikilink navigation](#wikilink-navigation) below.

**Render mode detection** — `splitFrontBack(body)` in `md_utils.dart` is called at render time on every note body, regardless of how the note was reached (deck list, card flip, or wikilink tap). If the body contains a valid `***` separator outside code fences with non-empty front and back, the note renders as a flashcard (front visible, back hidden until tap). If no separator is found, or either side is empty, the note renders as plain Markdown. This is a pure body-level check, separate from the scan-time detection in `getAllNotes()` which populates `ResurfaceNote.hasCard`.

**External URLs** — `_onTapLink` in both `_NoteCardViewerBody` (`resurface_screen.dart`) and `NoteDetailScreen` (`note_detail_screen.dart`) handles `http:` and `https:` hrefs by calling `launchUrl(uri, mode: LaunchMode.externalApplication)` via `url_launcher`. `wikilink:` scheme links are routed to note navigation (see [§ Wikilink navigation](#wikilink-navigation)). Any other scheme is silently ignored.

---

## Wikilink navigation

Notes may contain `[[Target Note]]` or `[[Target Note|Display Text]]` wikilinks. These are recognized in card front/back content and in `NoteDetailScreen`.

### Pre-processing

`substituteWikilinks(text)` in `md_utils.dart` rewrites wikilinks to standard Markdown links before the text reaches `flutter_markdown`:

- `[[Target]]` → `[Target](wikilink:Target%20Encoded)`
- `[[Target|Display]]` → `[Display](wikilink:Target%20Encoded)`

`flutter_markdown` renders these as styled links (theme primary colour, underlined) and fires `onTapLink` on tap. The `wikilink:` URI scheme is a sentinel — it is never opened by a URL launcher.

### Resolution

`ResurfaceService.resolveWikilink(vaultPath, targetName)` searches the whole vault recursively (no folder exclusions) for a `.md` file whose basename-without-extension matches `targetName` case-insensitively. Returns the first match's absolute path, or `null`.

### Navigation

- **Match found:** `ResurfaceScreenState._handleWikilinkTap()` pushes a `_NoteDetailRoute(filePath)` onto the internal nav stack. HomeScreen's AppBar updates to show the new note's filename as title and exposes a back button.
- **No match:** shows a `SnackBar` — `"Note not found: <targetName>"`.
- **Recursive navigation:** each wikilink tap from within a `NoteDetailScreen` adds another `_NoteDetailRoute` to the stack. Back presses pop one level at a time. The bottom navigation bar remains visible throughout all depths.
- **Returning to deck list:** tapping the Notes tab icon at any stack depth calls `ResurfaceScreenState.resetStack()`, which collapses the entire stack to `[_DeckListRoute]` in a single tap.

### Boundaries

- Wikilinks are never written to any file by the navigation layer.
- Resolution never throws; `null` on any I/O error.
- No backlinks, no graph UI.

---

## ResurfaceScreenState public API (for HomeScreen)

HomeScreen drives the AppBar and reads state via `GlobalKey<ResurfaceScreenState>`.

| API | Type | Purpose |
|---|---|---|
| `currentEditFilePath` | `String?` | Non-null when a `_NoteDetailRoute` or `_CardViewerRoute` is active with a known file; HomeScreen shows pencil icon |
| `openEditForCurrentNote(context)` | method | Pushes `NoteEditScreen` for `currentEditFilePath`; handles reload on return |
| `isSearchable` | `bool` | True when deck list is showing and vault is loaded; HomeScreen shows search icon |
| `isSearchActive` | `bool` | True when search bar is expanded; HomeScreen shows close icon instead of search |
| `toggleSearch()` | method | Expands/collapses the search bar; clears query on collapse |
| `resetStack()` | method | Collapses entire nav stack to deck list; called when Notes tab icon is tapped |

---

## What is not implemented

- No scheduler, no review intervals, no due dates, no FSRS.
- No review history. The session is stateless; which cards were seen is not recorded anywhere.
- No note creation. `NoteEditScreen` edits existing files only; there is no UI for creating new notes.
- No ordering beyond the in-session shuffle. The shuffle is not persisted.
- No per-card actions (mark known, snooze, rate). The only interactions are tap-to-reveal and prev/next navigation.
- No deck state persistence between sessions. Card position and back-revealed state are preserved within a session while navigating into and back from note details, but are discarded when returning to the deck list or switching tabs.
- No deck management UI. Decks are added by editing the `deck:` field directly in the note file.

---

## Boundaries (do not violate)

- `ResurfaceService` must never write to any file.
- `NoteEditScreen` writes only to the file path it receives (`widget.filePath`). It must never write to other vault files or touch any storage service.
- `_extractFrontBack` must return `null` rather than throw on any malformed input.
- The separator pattern `^\*{3,}\s*$` must not be silently expanded to match `---` or `___`.
- Folder exclusion is segment-exact: `Interesting` must not match `interesting-notes` or similar.
- Card order must not be persisted between sessions.
- Deck filter state must not be persisted between sessions.
- Do NOT add scheduling, FSRS, deck hierarchy, or any operational card-state machinery.
- Do NOT add note creation from within this subsystem.
