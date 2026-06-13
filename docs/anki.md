# AnkiDroid sync

## Overview

Problem notes (vault `.md` files containing a `***` separator) are pushed to AnkiDroid via its native ContentProvider API. Sync is one-way: vault → AnkiDroid. AnkiDroid never originates data; the vault remains the source of truth. Review history, scheduling state, ease factors, and due dates are never read or written.

## Sync pipeline

```
ResurfaceService.getAllNotes()
  → filter isProblemNote == true
  → AnkiDroidService.syncVault(problemNotes)
  → MethodChannel "com.nimeesh.interest/ankidroid"
  → MainActivity.kt (AddContentApi)
  → AnkiDroid ContentProvider
```

Triggered by the user tapping the AnkiDroid row in the Sources screen. No background sync; no scheduler.

## MethodChannel contract

Channel name: `com.nimeesh.interest/ankidroid`

| Method | Args | Returns | Notes |
|---|---|---|---|
| `isAnkiDroidAvailable` | — | `bool` | Package check (`com.ichi2.anki`) |
| `requestPermission` | — | `bool` | Runtime permission `com.ichi2.anki.permission.READ_WRITE_DATABASE` |
| `getAnkiDroidVersion` | — | `String?` (versionName, or null) | PackageManager lookup; gates `anki://` link emission |
| `addNote` | `deckName, front, back, tags` | `Long` (noteId, or -1) | Creates deck and model if absent |
| `updateNote` | `noteId, front, back, tags` | `bool` | `updateNoteFields` + `updateNoteTags` |
| `noteExists` | `noteId` | `bool` | `getNote(noteId) != null` |

Android implementation uses `AddContentApi` from `com.github.ankidroid:Anki-Android:api-2.0.0:api@aar`.

## Frontmatter fields written

Only `anki_note_id` is ever written back to a vault file. No other frontmatter field or note body is touched.

```yaml
anki_note_id: 1234567890   # Long returned by AnkiDroid addNote
```

Write-back calls `MarkdownStorageService.patchAnkiNoteId(filePath, noteId)` — patches `anki_note_id` in place; never rebuilds frontmatter.

## Deck mapping

The `category:` frontmatter field of the vault note is used as the AnkiDroid deck name. If absent, the deck name defaults to `"Default"` (AnkiDroid's built-in deck).

```yaml
category: Philosophy   # → deck "Philosophy" in AnkiDroid
```

Deck lookup uses `getOrCreateDeck` in `MainActivity.kt`, which checks `api.deckList()` before calling `api.addNewDeck()` — existing decks are never duplicated.

## Update vs. first push

| `anki_note_id` present? | Note exists in AnkiDroid? | Action |
|---|---|---|
| No | — | `addNote` → write ID back to frontmatter |
| Yes | Yes | `updateNote` (fields + tags) |
| Yes | No (deleted from AnkiDroid) | `addNote` → overwrite ID in frontmatter |

## What is NOT synced

- Review history, intervals, ease factors, due dates
- Scheduling state (FSRS or SM-2)
- Deck options / templates
- Media attachments
- Notes without a `***` separator (non-problem notes)

## Degraded mode

If AnkiDroid is not installed: snackbar "AnkiDroid not installed", no crash.  
If permission is denied: snackbar "Permission denied", no crash.  
Per-note errors are accumulated in `AnkiSyncResult.errors` and reported in the final snackbar without aborting the rest of the sync.

## Wikilink deep-links

### Two link tiers

A wikilink in a synced card resolves to one of two schemes, decided per link at sync time:

| Tier | Condition | Rendered href | Tap behaviour |
|---|---|---|---|
| **In-AnkiDroid** | target is a synced problem note (its `anki_note_id` is known) AND installed AnkiDroid ≥ 2.16 | `anki://x-callback-url/browser?search=nid%3A<anki_note_id>` | AnkiDroid's own Card Browser opens filtered to that note, stacked on the reviewer; back returns to the review session |
| **Fallback** | anything else (target not a problem note, not yet synced, version unknown or < 2.16) | `interest://note/<percent-encoded-note-name>` | Hands off to Interest, which resolves and routes the note |

The `anki://x-callback-url/browser` intent filter (`BROWSABLE` + `DEFAULT`) exists on AnkiDroid's `CardBrowser` activity since 2.16. AnkiDroid's reviewer fires link taps as `ACTION_VIEW` intents, so the link resolves back into AnkiDroid itself. This is the deepest in-AnkiDroid traversal possible: neither AnkiDroid's JS API nor any URI scheme can navigate the *reviewer* to an arbitrary card.

Example: `[[Zeno's Paradox]]` becomes `<a href="anki://x-callback-url/browser?search=nid%3A1234567890">Zeno's Paradox</a>` if that note is synced, else `<a href="interest://note/Zeno's%20Paradox">Zeno's Paradox</a>`.

### Export transformation

During sync, `AnkiDroidService._markdownToAnkiHtml()` rewrites wikilinks (via `rewriteWikilinksToHtml` in `md_utils.dart`) before Markdown→HTML conversion:

| Vault syntax | Rendered in AnkiDroid card |
|---|---|
| `[[Note Name]]` | `<a href="<resolved-href>">Note Name</a>` |
| `[[Note Name\|alias]]` | `<a href="<resolved-href>">alias</a>` |

Resolution uses an ID map built at sync start from each problem note's `anki_note_id` frontmatter, keyed by `noteKey` (lowercased basename); wikilink targets are lowercased to match. The map grows as the sync assigns new IDs, so notes later in the loop resolve earlier additions immediately.

**Not-yet-synced targets:** a note synced before its link target received an ID gets the `interest://` fallback. After the main loop, an upgrade pass re-renders and re-updates any successfully synced note whose wikilinks point at a note that received a new ID this sync (first add, or re-add after deletion in AnkiDroid — the latter also heals stale `nid:` links). Upgrade-pass failures are silently ignored: the fallback link still works, so the user is never worse off than the fallback tier.

**Version gate:** `_supportsBrowserLinks()` reads AnkiDroid's `versionName` via `getAnkiDroidVersion` and requires ≥ 2.16. On any failure (not installed, unparsable version) every link falls back to `interest://`.

Markdown files in the vault are never modified. Wikilink rendering inside Interest (Notes tab) is unchanged.

### Incoming intent handling

```
interest://note/<name> intent (VIEW)
  → MainActivity.kt extractDeeplinkNote()   Uri.lastPathSegment — auto-decodes %20 → space
  → MethodChannel "com.nimeesh.interest/deeplink"
      cold start  → getInitialDeeplinkNote (polled from initState)
      warm start  → openNote (pushed via onNewIntent)
  → HomeScreen._openNoteFromDeeplink()      switch to Notes tab (index 0)
  → ResurfaceScreenState.openNoteByName()   resolve and route (see below)
      problem note (***) → card viewer (_CardViewerRoute)
      plain note         → detail screen (_NoteDetailRoute)
      not found          → snackbar "Note not found: <name>"
```

**Decoding:** Android's `Uri.lastPathSegment` percent-decodes the note name segment before it reaches Flutter (e.g. `%20` → space). `HomeScreen._openNoteFromDeeplink()` nonetheless runs `Uri.decodeComponent()` on the already-decoded name. Known quirk: this double decode is harmless for ordinary names but would mangle a note name that itself contains a literal percent-escape sequence.

**Resolution in `openNoteByName()`:** two-step.
1. Case-insensitive scan of `_allNotes` (already loaded in `ResurfaceScreenState`) — fast path; covers the common case.
2. If not found there: `ResurfaceService.resolveWikilink(vaultPath, name)` — full recursive vault scan. Handles notes in excluded folders, or the rare race where the deep link fires before loading completes.

### Ownership boundary

Interest owns all note resolution and rendering. AnkiDroid is a launch point only — it fires the URI and hands control back. No note data flows from AnkiDroid into Interest.

---

## Obsidian note link in card front

Every synced card's front field is prepended with a right-aligned link to the source note in Obsidian:

```html
<div style="text-align:right;font-size:0.75em;margin-bottom:6px;opacity:0.6;">
  <a href="obsidian://open?vault=<encoded-vault>&file=<encoded-note>">Note Name ↗</a>
</div>
```

**URI construction:** `obsidianUri(vaultPath, noteFilePath)` in `md_utils.dart` — pure, no I/O.
- vault name = last path segment of vault path (e.g. `nimeesh vault`)
- note name = basename without `.md` extension
- Both encoded with `Uri.encodeComponent()`

**Placement:** prepended to the converted HTML of `note.front`, before the question text. The back field is unchanged.

**Updates:** when the note is re-synced (via `anki_note_id` match → `updateNote`), the front field is rebuilt automatically, so a rename is reflected on the next sync without any additional logic.

**Launching:** AnkiDroid's HTML renderer fires the `obsidian://` href natively when the user taps the link during review. No Flutter code is involved in the tap.

**If Obsidian is not installed:** Android's intent system receives the `obsidian://` URI from AnkiDroid. If no app handles it, Android shows a system "no app found" error or silently drops it depending on OS version. Flutter has no error-handling path for this case — the tap is outside Flutter's process.
