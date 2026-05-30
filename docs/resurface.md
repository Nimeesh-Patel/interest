# Notes / Resurface Subsystem

## Overview

Vault-wide semantic notes layer. `ResurfaceService` scans every `.md` file in the vault and projects them into three surfaces: a **deck viewer** for `***`-separated notes (front/back card pairs), a **full-text search** over all vault notes, and an **inline note editor** that writes directly back to vault files. An **activation model** promotes non-`***` notes that are linked to reviewed `***` notes into the same review queue, weighted by graph proximity and time decay.

---

## Vault scan scope

`ResurfaceService.getAllNotes()` calls `Directory(vaultPath).list(recursive: true)` and processes every `.md` file found, subject to folder exclusions.

**Default excluded folders:** `.obsidian`, `Templates`, `Attachments`.

- `.obsidian` — Obsidian configuration; not user prose.
- `Templates` — template stubs; not epistemic artifacts.
- `Attachments` — binary assets.

`Interesting/` is **not excluded**. Entity files, book files, Anki cards, and project files are all reachable by the wikilink graph and can receive graph-score boosts. `***` notes inside `Interesting/` surface directly in the deck list.

**Exclusion semantics:** segment-exact. The relative path from vault root is split on the OS separator, the filename is dropped, and each remaining segment is checked against the list. `Interesting` does not match `Interesting-notes`.

**Configuring exclusions:** Settings → Resurface → "Excluded folders" (comma-separated). Stored in `Interesting/System/integrations.md` via `IntegrationsConfigService`. The default list is applied when the config section is absent.

---

## Note classification

Every note that passes folder exclusions becomes a `ResurfaceNote` with `hasCard` computed at scan time.

### `***` notes (`hasCard: true`)

A note has `hasCard: true` when its body (after frontmatter strip) contains a line matching `^\*{3,}\s*$` outside a code fence, with non-empty content on both sides. These notes are called **star notes** (`is_star: true` in the review log). They surface directly in the deck list and card viewer.

### Non-`***` notes (`hasCard: false`)

A non-`***` note is ineligible for the review queue by default. It becomes **activated** — eligible for the queue — when at least one star note within the configured degree range has been reviewed. Activation is tracked in `review_log.md` via the `activated_by` field.

**`is_star` in the log:** set to `true` when a note is reviewed from the card viewer (`markReviewed(..., isStar: true)`). Set to `false` when a non-star note is created as an activation entry. If a non-star note gains a `***` separator (user edits), `is_star` is updated to `true` and `activated_by` is cleared — the note becomes independently scheduled from that point.

---

## Deck grouping

Notes declare optional deck membership via the `deck:` YAML frontmatter field:

```yaml
deck: epistemology
```

or for multiple decks:

```yaml
deck:
  - epistemology
  - programming
```

Parsed via `parseDeckMetadata()` in `md_utils.dart`; absent → `[]`.

**Decks are projection labels, not ownership containers.** A note belongs to its file; decks only filter the viewer display.

The deck list always contains:
1. **All Notes** — all star notes regardless of `deck:` metadata
2. **Default** — star notes with `decks: []`; shown only if any exist
3. Named decks, A→Z, with counts

When a deck is opened, **activated non-star notes** that match the deck filter are merged into the queue alongside star notes, then sorted by priority.

---

## Wikilink navigation

Notes may contain `[[Target Note]]` or `[[Target Note|Display Text]]` wikilinks.

**Pre-processing:** `substituteWikilinks(text)` in `md_utils.dart` rewrites wikilinks to `[Display](wikilink:Target%20Encoded)` before the text reaches `flutter_markdown`. The `wikilink:` URI scheme is never opened by a URL launcher.

**Resolution:** `ResurfaceService.resolveWikilink(vaultPath, targetName)` searches the whole vault recursively (no folder exclusions) for a `.md` file whose basename-without-extension matches `targetName` case-insensitively. Returns the first match's absolute path, or `null`.

**Navigation:** a successful tap pushes a `_NoteDetailRoute` onto `ResurfaceScreenState`'s internal stack. No match shows a `SnackBar`. Multiple wikilink hops accumulate as stacked routes; back pops one level at a time. Tapping the Notes tab icon calls `resetStack()`, collapsing to the deck list in one tap.

---

## Note editing

`NoteEditScreen` is a proper pushed route (`Navigator.push`). It receives a `filePath` and writes back to that exact path on save. It never touches other vault files.

### Edit modes

| Mode | Condition | UI |
|---|---|---|
| **Structured** | note has a valid `***` separator | Two sections: "Problem" (front) and "Idea" (back) |
| **Plain** | no `***` separator | Single body `TextField` |
| **Full note edit** | user selects from three-dot menu | Raw file content including frontmatter, monospace font |

### Save semantics

`_buildCurrentContent()` reconstructs the full file from the active mode's controllers, prepending frontmatter verbatim. Save writes the file and pops with `true`. Cancel with unsaved changes shows a "Discard changes?" confirm dialog.

After save, `ResurfaceScreenState._reloadAfterEdit(filePath)` is called. For a `_NoteDetailRoute`, `_detailVersion` increments (forcing `initState` re-read). For a `_CardViewerRoute`, `_reloadViewerNote(filePath)` re-parses the edited file in place.

### Toolbar

A formatting toolbar (44px, pinned above keyboard) in structured and plain modes. Buttons: **B**, **I**, **U**, **—**, **T** (heading sheet), **+** (insert sheet: bullet/numbered/wikilink).

---

## Search

A search icon appears in HomeScreen's AppBar when the deck list is showing and the vault is loaded. Tapping toggles `_searchActive`.

**Scope:** all `_allNotes` — every vault note that passed folder exclusions, regardless of `hasCard`.

**Match criteria:** case-insensitive; matches the filename (without extension) or any line of the note body.

**Result rendering:** filename as title, first matching body snippet as subtitle, `✦` icon for star notes.

**Tapping a result:**
- Star note → `_pushDeck` with the single matched note
- Plain note → `_NoteDetailRoute` to `NoteDetailScreen`

---

## Review logging

`ReviewLogService` is the sole owner of `Interesting/System/review_log.md`. No other file reads or writes this file.

### File format

```yaml
---
settings:
  min_degree: 2
  max_degree: 3
reviews:
  - note: "refutation in chess"
    last_reviewed: "2026-05-30"
    graph_score: 2.4
    last_boosted: "2026-05-29"
    activated_by: []
    is_star: true
  - note: "some plain note"
    last_reviewed: null
    graph_score: 0.0
    last_boosted: "2026-05-30"
    activated_by:
      - "refutation in chess"
    is_star: false
---
```

### `settings:` section

| Field | Type | Default | Owner |
|---|---|---|---|
| `min_degree` | int | 2 | `ReviewLogService.saveSettings()` |
| `max_degree` | int | 3 | `ReviewLogService.saveSettings()` |

Read by `GraphScoringService` before each BFS traversal. Configurable in Settings → Resurface → "Graph neighbour range".

### `reviews:` entries

| Field | Type | Meaning |
|---|---|---|
| `note` | String | Filename without extension — the entry's identity key |
| `last_reviewed` | ISO date or `null` | Date of last direct review; `null` if never reviewed |
| `graph_score` | float | Raw accumulated score from graph boosts (before decay) |
| `last_boosted` | ISO date or omitted | Date of last graph boost received |
| `activated_by` | list of strings | Star note filenames whose reviews activated this note |
| `is_star` | bool | Whether the note has a `***` separator |

**Who writes what:**
- `markReviewed(filename, isStar:)` — updates `last_reviewed` and `is_star`; clears `activated_by` if promoting from non-star to star
- `patchGraphScores(updates)` — updates `graph_score`, `last_boosted`, `is_star`
- `activateNotes(reviewedStarNote, targets)` — appends to `activated_by`; creates entries for notes not yet in the log
- `saveSettings(minDegree:, maxDegree:)` — updates the `settings:` section; preserves all entries

**Failure semantics:** if the file is missing or malformed, all methods return empty state and the app continues unaffected. No method throws.

---

## Graph scoring

`GraphScoringService` builds a wikilink graph at call time, propagates scores to neighbours, and sorts the review queue.

### Graph construction

Called once per `updateGraphScores(reviewedNoteFilename)` invocation. No caching.

```dart
for each note in ResurfaceService.getAllNotes(vaultPath):
  graph[normalise(note.sourceFile)] = extractWikilinks(note.body).map(normalise)
```

Normalisation: lowercase, strip `.md` extension. A parallel `normalToOrig` map preserves original casing for writing back to the log.

### BFS traversal

```
visited = {reviewed}
frontier = {reviewed}
for d in 1..maxDegree:
  next = neighbours(frontier) - visited
  hopNodes[d] = next
  visited += next
  frontier = next
```

All nodes in `hopNodes[d]` receive a score boost of `kBaseBoost / d`.

Nodes in `hopNodes[d]` where `d >= minDegree` are **activation-eligible**: if they are non-star notes, `reviewedNoteFilename` is appended to their `activated_by`.

### Constants

```dart
const double kBaseBoost = 1.0;   // boost at hop distance 1
const double kDecayLambda = 0.1; // Ebbinghaus-style decay rate
```

### Time decay

Applied at read time, not write time:

```
decayedScore = rawScore × e^(−λ × daysSinceLastBoosted)
```

where `daysSinceLastBoosted = today − last_boosted` in integer days. Returns `0.0` if `last_boosted` is null.

### Activation model for non-star notes

A non-star note N is activation-eligible when it falls in the hop range `[minDegree, maxDegree]` from a reviewed star note P. When activated, P is appended to N's `activated_by` list. N enters the review queue on the next deck open, alongside star notes.

If N has multiple activating parents in `activated_by`, its priority uses the **maximum** decayed score across all parents:

```
parent_score = max(decayedScore(P) for P in activated_by)
```

---

## Sort priority

Both star notes and activated non-star notes share the same descending-priority queue.

**Star note priority:**
```
priority = daysSinceReview + decayedScore(graph_score, last_boosted)
```

**Non-star note priority:**
```
priority = daysSinceReview + max_parent_score
```

`daysSinceReview` = `today − last_reviewed` in integer days. If never reviewed: treated as 365.

Higher priority surfaces first. Within ties, order is stable (Dart's sort is stable).

---

## What is not implemented

- No FSRS, no review intervals, no due dates.
- No cloud sync of review state.
- No statistics or review history display.
- No gamification (streaks, points, ratings).
- No note creation. `NoteEditScreen` edits existing files only.
- No deck hierarchy.
- No persistent deck filter or card position between sessions.
- No deck management UI; decks are `deck:` frontmatter values.

---

## Boundaries

- `ResurfaceService` never writes any file.
- `NoteEditScreen` writes only to the file path it receives.
- `ReviewLogService` is the only service that reads or writes `review_log.md`.
- `GraphScoringService` never writes vault notes; it only calls `ReviewLogService` write methods.
- Folder exclusion is segment-exact: `Interesting` does not match `interesting-notes`.
- The `***` separator pattern `^\*{3,}\s*$` is not expanded to match `---` or `___`.
- Do not add scheduling, FSRS, deck databases, or any persistent card-state machinery.
- Do not add note creation from within this subsystem.
