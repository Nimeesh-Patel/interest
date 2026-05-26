# Notes / Resurface Subsystem

## Purpose

Vault-wide semantic resurfacing viewer. The resurfacing layer is a **projection over notes** — it surfaces problem-situation structures, ideas, and conjectures already latent in the user's epistemic artifacts, without modifying them.

Notes are primary. The resurfacing viewer is secondary: a read-only projection that emerges from notes, not a card-authoring system imposed on top of them.

This is a **read-only semantic projection**. The vault is never modified.

---

## Architectural role

The resurfacing viewer sits at the read-only projection end of the architecture: it discovers structure already encoded in notes, rather than imposing structure from outside.

```
vault notes (unchanged)
  → ResurfaceService.scan()       — recursive read + separator extraction
  → List<ResurfaceCard>           — in-memory projection (filesystem order, unshuffled)
  → ResurfaceScreen               — deck list; tap a deck to push NoteCardViewerScreen
      → NoteCardViewerScreen      — card viewer; shuffles cards on open; discarded on pop
          → NoteDetailScreen      — full note view; pushed on wikilink tap; recursive
```

Nothing about the session is written to the vault or to SharedPreferences.

---

## Ontology

A `ResurfaceCard` is a transient view derived from a single note at read time. It has no identity anchor and is not stored or indexed.

| Field | Value |
|---|---|
| `sourcePath` | Absolute path to the source file |
| `sourceFile` | Basename of the source file (e.g. `epistemology.md`) |
| `front` | Content above the first `***` separator, trimmed |
| `back` | Content below the first `***` separator, trimmed |
| `decks` | List of deck names from `deck:` frontmatter; `[]` if absent |

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

`ResurfaceScreen` shows a deck list. Each row is a deck name and card count. Tapping a row pushes `NoteCardViewerScreen` with the cards pre-filtered to that deck.

The deck list always contains:
1. **All Notes** (bold) — all cards from the scan, regardless of `deck:` metadata
2. **Default** — cards whose `decks` list is empty (i.e., no `deck:` frontmatter); shown only if at least one such card exists
3. Named decks, one per distinct `deck:` value found, sorted A→Z

A note may appear in multiple named deck rows (if its `deck:` list has multiple entries) and also in "All Notes". The "Default" and named deck rows are mutually exclusive — a card either has decks or it doesn't.

`NoteCardViewerScreen` receives the filtered `List<ResurfaceCard>`, the deck name, and `vaultPath` (used for wikilink resolution). It shuffles the cards in `initState` (unseeded random; order is different each session). The viewer is discarded when the user navigates back to the deck list.

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

`ResurfaceService.scan()` calls `Directory(vaultPath).list(recursive: true)` and processes every `.md` file found.

**Excluded folders:** any file whose relative path contains a segment matching an excluded folder name is skipped. Matching is exact and segment-based — the full path is split on the OS separator, the filename (last segment) is dropped, and each remaining segment is checked against the exclusion list.

Default excluded folders: `Interesting`, `.obsidian`, `Templates`, `Attachments`.

- `Interesting` is excluded because it contains the app's structured semantic objects (entities, books, Anki cards, projects) — schema-driven files with YAML frontmatter and semantic sections that are not the raw epistemic material the resurfacing viewer is designed for.
- `.obsidian` and `Templates` and `Attachments` are excluded because they contain configuration, templates, and binary assets rather than notes.

**Changing the exclusion list:** Settings → Resurface. Stored in `Interesting/System/integrations.md` under `## Resurface → excluded_folders:` via `IntegrationsConfigService`. The default list is used if the section is absent or empty.

---

## ResurfaceService API

```dart
class ResurfaceService {
  static Future<List<ResurfaceCard>> scan(
    String vaultPath, {
    List<String> excludedFolders = _defaultExcludedFolders,
  }) async

  static Future<String?> resolveWikilink(
    String vaultPath,
    String targetName,
  ) async
}
```

`scan()` returns all `ResurfaceCard` projections found across the vault, in filesystem iteration order (the caller is responsible for shuffling). Returns an empty list on any top-level I/O error; never throws.

`resolveWikilink()` searches the whole vault recursively — no folder exclusions — for a `.md` file whose basename-without-extension matches `targetName` case-insensitively. Returns the first matching absolute path, or `null` on no match or any I/O error. Never throws.

`_extractFrontBack()` is private. It takes a file path and raw file content and returns a `ResurfaceCard?`. Returns `null` on any of: no separator found, empty front, empty back, any exception during parsing.

---

## ResurfaceScreen behaviour

`ResurfaceScreen` is a primary navigation tab ("Notes"). It has **no Scaffold of its own** — HomeScreen provides the AppBar (title: "Notes"). `ResurfaceScreen` renders a deck list body only.

### Load

On `initState`, the screen calls `VaultService.getVaultPath()`, then `IntegrationsConfigService.load()` to read the excluded folders, then `ResurfaceService.scan()`. The card list is stored as-is (filesystem order, unshuffled) in `_cards`.

### States

| Condition | Displayed |
|---|---|
| Vault path not configured | `EmptyState` with error message |
| Scan in progress | `CircularProgressIndicator` |
| Scan complete, zero cards | `EmptyState` with hint to add a `***` separator |
| Cards loaded | `ListView` of deck rows |

### Deck list layout

`SafeArea(top: false)` → `ListView.builder` of `ListTile`s, one per deck:
- **"All Notes"** row (always first, bold title): total card count
- **"Default"** row (second, if any undecked cards exist): count of cards with `decks: []`
- **Named deck rows** (A→Z): count of cards that include that deck name

Trailing text shows the card count in `Colors.grey`. Tapping any row pushes `NoteCardViewerScreen`.

### NoteCardViewerScreen

A pushed route (`Navigator.push`) with its own Scaffold and AppBar. Receives `List<ResurfaceCard> cards` (pre-filtered, unshuffled), `String deckName`, and `String vaultPath` (used for wikilink resolution).

**AppBar**: title = `deckName`; trailing counter `"N / total"` (e.g. `"3 / 12"`).

**initState**: `_cards = List.of(widget.cards)..shuffle()` — shuffle is unseeded; order is random each session.

**Card layout** (`SingleChildScrollView` with 20px padding):
- **Source title**: filename without extension, rendered as `# heading` via `MarkdownBody`
- **Front**: rendered via `MarkdownBody` (theme `onSurface` colour)
- **"tap to reveal"** hint when back is hidden (centred italic grey text)
- **Divider** + **back** when revealed (back rendered in `Colors.grey.shade800`)

**Interaction**: tap anywhere on the card area toggles `_backRevealed`. Swipe left (velocity < −200) advances; swipe right (velocity > +200) retreats. Prev/next `IconButton`s at the bottom (disabled at boundaries). Navigation resets `_backRevealed` to `false`.

**Session state**: `_cards` (shuffled), `_currentIndex`, `_backRevealed`. Popping back to the deck list discards all viewer state.

### Markdown rendering

All content — source title, front, back — is rendered via `flutter_markdown`'s `MarkdownBody` with explicit sizes: H1 26px bold, H2 19px semi-bold, H3 16px semi-bold, body/listBullet 15px (line height 1.55). Front and title use `onSurface`; back uses `Colors.grey.shade800`.

`[[wikilinks]]` in front and back are pre-processed by `substituteWikilinks()` before rendering. They appear as tappable links in the theme's primary/accent colour. See [§ Wikilink navigation](#wikilink-navigation) below.

### NoteDetailScreen

A pushed route opened when the user taps a wikilink in the card viewer. Receives `vaultPath` and `filePath`. Renders the note's full body (frontmatter stripped) via `MarkdownBody` with the same wikilink handling, enabling recursive navigation. Displays the filename (without extension) as the AppBar title.

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

- **Match found:** pushes `NoteDetailScreen(vaultPath, filePath)` onto the Navigator stack.
- **No match:** shows a `SnackBar` — `"Note not found: <targetName>"`.
- `NoteDetailScreen` itself also processes wikilinks, enabling recursive navigation.

### Boundaries

- Wikilinks are never written to any file.
- Resolution never throws; `null` on any I/O error.
- No backlinks, no graph UI, no vault mutation.

---

## What is not implemented

- No scheduler, no review intervals, no due dates, no FSRS.
- No review history. The session is stateless; which cards were seen is not recorded anywhere.
- No mutation of vault files. The vault is opened read-only.
- No card authoring. There is no UI for creating or editing notes from within this screen.
- No ordering beyond the in-session shuffle. The shuffle is not persisted.
- No per-card actions (mark known, snooze, rate). The only interactions are tap-to-reveal and prev/next navigation.
- No deck state persistence. Which deck was last viewed and card position within it are discarded when `NoteCardViewerScreen` is popped.
- No deck management UI. Decks are added by editing the `deck:` field directly in the note file.

---

## Boundaries (do not violate)

- `ResurfaceService` must never write to any file.
- `_extractFrontBack` must return `null` rather than throw on any malformed input.
- The separator pattern `^\*{3,}\s*$` must not be silently expanded to match `---` or `___`.
- Folder exclusion is segment-exact: `Interesting` must not match `interesting-notes` or similar.
- Card order must not be persisted between sessions.
- Deck filter state must not be persisted between sessions.
- Do NOT add scheduling, FSRS, deck hierarchy, or any operational card-state machinery.
