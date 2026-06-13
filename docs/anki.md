# Anki sync

## Overview

Problem notes (vault `.md` files containing a `***` separator) are pushed to Anki as Basic cards. Sync is **one-way: vault → Anki**, over either of two transports:

| Transport | Backend | Wire protocol | Platform |
|---|---|---|---|
| `AnkiDroidTransport` | AnkiDroid app | ContentProvider via MethodChannel (`MainActivity.kt`, `AddContentApi`) | Android only |
| `AnkiConnectTransport` | Anki desktop + [AnkiConnect](https://git.sr.ht/~foosoft/anki-connect) add-on | HTTP, default `http://127.0.0.1:8765`, API version 6 | Pure Dart — any platform that can reach the URL |

Anki never originates data; the vault remains the source of truth. Review history, scheduling state, ease factors, and due dates are never read or written — on either transport.

## Architecture

```
ResurfaceService.getAllNotes()
  → filter isProblemNote == true
  → AnkiSyncController.sync(transport)
  → AnkiSyncService.syncVault(transport, problemNotes, vaultPath)   ← shared core
       → AnkiTransport                                              ← per-backend
            AnkiDroidTransport   → MethodChannel → AnkiDroid ContentProvider
            AnkiConnectTransport → HTTP POST     → AnkiConnect → Anki desktop
```

`AnkiSyncService` owns everything both transports must agree on — front/back rendering, `category:`→deck mapping (including the deck move on a category change), the obsidian:// wikilink rewrite, the `anki_note_id` round-trip — so the same note yields the same card whichever transport carries it. Transports translate seven operations into their wire protocol and nothing else:

| `AnkiTransport` method | AnkiDroid (MethodChannel) | AnkiConnect (HTTP action) |
|---|---|---|
| `isAvailable` | `isAnkiDroidAvailable` (package check) | `version` answers |
| `requestPermission` | `com.ichi2.anki.permission.READ_WRITE_DATABASE` | `requestPermission` → `granted` |
| `addNote` | `addNote` (creates deck if absent) | `createDeck` (idempotent) then `addNote` |
| `updateNote` | `updateNoteFields` + `updateNoteTags` | `updateNoteFields` + `updateNoteTags` |
| `noteExists` | `getNote(noteId) != null` | `notesInfo` → non-empty object |
| `currentDeck` | `getCardDeck` (ContentProvider card → `DECK_ID` → name) | `notesInfo` → `cards` → `getDecks` |
| `moveToDeck` | `moveNoteToDeck` (ContentProvider card `DECK_ID` update) | `createDeck` then `changeDeck` |

Both `currentDeck` and `moveToDeck` degrade gracefully: a transport that cannot read or change a card's deck returns `null` / no-ops rather than throwing, so the deck-move check simply does nothing.

Transport failures: per-note failures return `-1`/`false` or throw `AnkiNoteFailure(message)` (recorded against the note, sync continues); collection-level fatal conditions throw `AnkiSyncAbort(message)` (recorded, sync stops). These two exceptions are consumed only by `AnkiSyncService.syncVault`; nothing else in the app sees them.

Triggered by the user tapping the AnkiDroid row (Android) or Anki desktop row (all platforms) in the Sources screen. No background sync; no scheduler.

## `anki_note_id` across transports

Only `anki_note_id` is ever written back to a vault file (via `MarkdownStorageService.patchAnkiNoteId` → `patchFrontmatterField`; patches in place, never rebuilds frontmatter, never touches the body).

```yaml
anki_note_id: 1234567890   # collection note id (epoch-millis Long)
```

**The id means the same thing on both transports**: it is the Anki *collection's* note id, which AnkiWeb preserves when syncing the collection between AnkiDroid and Anki desktop. A note first pushed via AnkiDroid updates cleanly via AnkiConnect later (and vice versa) **provided the user syncs their Anki collection via AnkiWeb in between**. If they don't, the id won't resolve in the other device's collection, `noteExists` returns false, and the sync re-adds the note there and overwrites the frontmatter id — the same self-healing path as "deleted from Anki", but it leaves the un-synced copy orphaned in the other collection. This is a property of running two un-synced Anki collections, not of the transport split.

## Update vs. first push

| `anki_note_id` present? | Note exists in Anki? | Action |
|---|---|---|
| No | — | `addNote` → write ID back to frontmatter |
| Yes | Yes | `updateNote` (fields + tags), then move the card if its deck changed |
| Yes | No (deleted from Anki / collection never synced) | `addNote` → overwrite ID in frontmatter |

## Deck mapping

The `category:` frontmatter field of the vault note is used as the deck name; absent means `"Default"` (Anki's built-in deck). Both transports look-up-or-create:

- AnkiDroid: `getOrCreateDeck` in `MainActivity.kt` checks `api.deckList()` before `api.addNewDeck()`.
- AnkiConnect: `createDeck` is idempotent — for an existing name it returns that deck's id without duplicating (verified live against AnkiConnect 6).

**Deck move on category change.** A new note is added straight into its `category:` deck. For an *existing* note (the `updateNote` path), `updateNote` only rewrites fields/tags — it does not move the card. So after a successful update the sync core asks `transport.currentDeck(noteId)` and, if it differs from the `category:`-derived deck, calls `transport.moveToDeck(noteId, deck)`. The deck is created if absent (AnkiConnect `createDeck`, AnkiDroid `getOrCreateDeck`). If the transport can't report the current deck (`null`), the move is skipped — the card stays where it is rather than risking a wrong move.

## Note model

Both transports create notes only on the model literally named **`Basic`** (fields `Front`/`Back`), so a note added by one updates cleanly via the other. If it is missing the sync aborts: AnkiDroid surfaces `BASIC_MODEL_NOT_FOUND` from `MainActivity.kt`; AnkiConnect checks `modelNames` once per sync. (Legacy notes on the auto-generated `com.nimeesh.interest.basic` model also use `Front`/`Back`, so updates reach them too.)

## What is NOT synced

- Review history, intervals, ease factors, due dates
- Scheduling state (FSRS or SM-2)
- Deck options / templates
- Media attachments
- Notes without a `***` separator (non-problem notes)

## Degraded mode

AnkiDroid not installed → snackbar "AnkiDroid not installed". AnkiConnect unreachable → snackbar "Anki desktop not reachable — is Anki running with AnkiConnect installed?". Permission denied → snackbar, no crash. Per-note errors are accumulated in `AnkiSyncResult.errors` and reported in a dialog without aborting the rest of the sync. The two Anki rows in the Sources screen are mutually exclusive while syncing (both write `anki_note_id` to the same files).

## AnkiConnect specifics

- Endpoint default `http://127.0.0.1:8765`, overridable via an `## AnkiConnect` section in `Interesting/System/integrations.md` (`url: http://…`) — hand-edited; there is no in-app editor. A LAN URL lets the Android build push to a desktop Anki.
- Request shape: `POST {action, version: 6, params}` → `{result, error}`; HTTP status is always 200, failures arrive in `error`.
- `addNote` uses `options.allowDuplicate: true` — duplicate policy stays Interest's (one card per vault note via `anki_note_id`), not Anki's front-field heuristic.
- `noteExists` reads `notesInfo`: a missing id comes back as an **empty object** in the result array, not an error.
- The wire contract above was verified against a live Anki desktop + AnkiConnect 6 (createDeck idempotency, missing-deck error, empty-object `notesInfo`, `updateNoteFields`/`updateNoteTags` round-trip). `test/anki_connect_transport_test.dart` pins it against a fake server.

## Card-body wikilinks → Obsidian

Note traversal lives in **Obsidian**, not Interest. Every `[[wikilink]]` in a synced card body is rewritten to an `obsidian://open` link to the target note — the same scheme and vault-name + percent-encoding the source link at the top of the card already uses (`obsidianUriForName` in `md_utils.dart`, the shared core of `obsidianUri`).

| Vault syntax | Rendered in the card |
|---|---|
| `[[Note Name]]` | `<a href="obsidian://open?vault=<vault>&file=Note%20Name">Note Name</a>` |
| `[[Note Name\|alias]]` | `<a href="obsidian://open?vault=<vault>&file=Note%20Name">alias</a>` |

Tapping a body wikilink during review opens the linked note in Obsidian. **This requires the Obsidian `***`-note rendering plugin** for the intended tap-to-reveal experience — it renders a `***` problem note with the back side hidden until tapped. Without the plugin the link still opens the note in Obsidian, just rendered normally (front and back both visible). There is a single scheme: no per-link tier decision, no `anki_note_id` lookup, no upgrade pass — body links don't depend on whether the target itself is synced.

The rewrite (`AnkiSyncService._markdownToAnkiHtml`, via `rewriteWikilinksToHtml`) runs before Markdown→HTML conversion. Markdown files in the vault are never modified; wikilink rendering inside Interest's own Notes tab is unchanged.

### Line breaks in card content

Standard Markdown collapses a single newline within a block to a space. For card content that erases the note's visual line structure (e.g. a list of `Corollary #N` lines run together). So before Markdown→HTML conversion, `_markdownToAnkiHtml` promotes every lone newline (one not adjacent to another newline — i.e. not a paragraph break) to a Markdown hard break (two trailing spaces), which renders as `<br>`. Paragraph breaks (blank lines) and fenced code blocks are untouched. This applies **only** to Anki card HTML — no other Markdown rendering in the app changes.

### Incoming intent handling (Android)

Two `interest://` deep links are handled, both via `MainActivity.kt` → MethodChannel `com.nimeesh.interest/deeplink`:

**`interest://note/<name>`** — open a note in Interest's reader (used by legacy cards and external callers; current cards link to Obsidian, not here):

```
interest://note/<name> intent (VIEW)
  → MainActivity.kt extractDeeplinkNote()   Uri.lastPathSegment — auto-decodes %20 → space
      cold start  → getInitialDeeplinkNote (polled from initState)
      warm start  → openNote (pushed via onNewIntent)
  → HomeScreen._openNoteFromDeeplink()      switch to Notes tab (index 0)
  → ResurfaceScreenState.openNoteByName()   resolve and route
      problem note (***) → card viewer; plain note → detail screen; not found → snackbar
```

**`interest://sync-anki`** — trigger a whole-vault AnkiDroid push without navigating Interest's UI (so the Obsidian plugin can sync with one tap):

```
interest://sync-anki intent (VIEW)
  → MainActivity.kt extractSyncAnki()
      cold start  → getInitialSyncAnki (polled from initState)
      warm start  → syncAnki (pushed via onNewIntent)
  → HomeScreen._syncAnkiFromDeeplink()
  → runAnkiDroidSync()   the same path the Sources screen AnkiDroid row triggers
      → AnkiSyncController.sync(AnkiDroidTransport()) → result via snackbar/dialog
```

The handler only invokes the existing sync controller; routing introduces **no new write path** (the `anki_note_id` write-back inside the sync is the sole vault write, unchanged).

**Decoding** (`interest://note` only): Android's `Uri.lastPathSegment` percent-decodes the note name before it reaches Flutter; `HomeScreen._openNoteFromDeeplink()` nonetheless runs `Uri.decodeComponent()` again. This double decode is harmless for ordinary names but would mangle a name containing a literal percent-escape.

There is no desktop handler for `interest://` — on desktop the links are inert.

### Ownership boundary

Interest owns all note resolution and the sync. Anki (either flavour) is a launch point only — it fires `obsidian://` (body/source links) or `interest://` (sync trigger / legacy note links) and hands control back. No note data flows from Anki into Interest.

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

**Launching:** Anki's HTML renderer fires the `obsidian://` href natively when the user taps the link during review — on desktop this opens Obsidian desktop (which registers the scheme); on Android it goes through the intent system. No Flutter code is involved in the tap. If Obsidian is not installed, the OS shows a "no handler" error or silently drops it; Interest has no error-handling path for this case — the tap is outside its process.

## MethodChannel contract (AnkiDroid transport)

Channel name: `com.nimeesh.interest/ankidroid`

| Method | Args | Returns | Notes |
|---|---|---|---|
| `isAnkiDroidAvailable` | — | `bool` | Package check (`com.ichi2.anki`) |
| `requestPermission` | — | `bool` | Runtime permission `com.ichi2.anki.permission.READ_WRITE_DATABASE` |
| `addNote` | `deckName, front, back, tags` | `Long` (noteId, or -1) | Creates deck and model if absent |
| `updateNote` | `noteId, front, back, tags` | `bool` | `updateNoteFields` + `updateNoteTags` |
| `noteExists` | `noteId` | `bool` | `getNote(noteId) != null` |
| `getCardDeck` | `noteId` | `String?` (deck name, or null) | First card's `DECK_ID` → name via `getDeckList()` |
| `moveNoteToDeck` | `noteId, deckName` | `bool` | Updates each card's `DECK_ID` via the ContentProvider; deck created if absent |

The deep-link channel `com.nimeesh.interest/deeplink` also serves `getInitialDeeplinkNote` / `openNote` (note links) and `getInitialSyncAnki` / `syncAnki` (the `interest://sync-anki` trigger).

Android implementation uses `AddContentApi` and `FlashCardsContract` from `com.github.ankidroid:Anki-Android:api-2.0.0:api@aar`. (`getAnkiDroidVersion` remains in `MainActivity.kt` but is no longer called from Dart — card-body links now use `obsidian://` unconditionally, so the AnkiDroid version gate that drove the old `anki://` tier was removed.)
