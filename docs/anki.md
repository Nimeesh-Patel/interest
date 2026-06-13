# Anki sync

## Overview

Problem notes (vault `.md` files containing a `***` separator) are pushed to Anki as Basic cards. Sync is **one-way: vault → Anki**, over either of two transports:

| Transport | Backend | Wire protocol | Platform |
|---|---|---|---|
| `AnkiDroidTransport` | AnkiDroid app | ContentProvider via MethodChannel (`AnkiBridge.kt`, `AddContentApi`) | Android only |
| `AnkiConnectTransport` | Anki desktop + [AnkiConnect](https://git.sr.ht/~foosoft/anki-connect) add-on | HTTP, default `http://127.0.0.1:8765`, API version 6 | Pure Dart — any platform that can reach the URL |

Anki never originates data; the vault remains the source of truth. Review history, scheduling state, ease factors, and due dates are never read or written — on either transport.

The whole sync stack lives self-contained under `lib/features/anki/`, with **zero dependency on any note viewer** (there is none — Obsidian + the Problem Notes plugin own viewing/editing).

## Architecture

```
AnkiProblemNoteScanner.scan(vaultPath, excludedFolders)   ← finds *** notes
  → List<AnkiProblemNote>                                  ← slim sync-only model
  → AnkiSyncController.sync(transport)
  → AnkiSyncService.syncVault(transport, problemNotes, vaultPath)   ← shared core
       → AnkiTransport                                              ← per-backend
            AnkiDroidTransport   → MethodChannel → AnkiBridge → AnkiDroid ContentProvider
            AnkiConnectTransport → HTTP POST     → AnkiConnect → Anki desktop
```

`AnkiProblemNoteScanner` is the sync's vault discovery: it scans every `.md` (via `VaultScanner`, honouring the excluded-folders config and `exclude_resurface: true`) and keeps only notes whose body has a `***` separator (`splitFrontBack`). It produces `AnkiProblemNote` — exactly the fields the sync needs (`sourcePath`, `sourceFile`, `front`, `back`, `category`, `tags`, `anki_note_id`) and nothing about rendering or viewing.

`AnkiSyncService` owns everything both transports must agree on — front/back rendering, `category:`→deck mapping (including the deck move on a category change), the `obsidian://` wikilink rewrite, the `anki_note_id` round-trip — so the same note yields the same card whichever transport carries it. Transports translate seven operations into their wire protocol and nothing else:

| `AnkiTransport` method | AnkiDroid (MethodChannel) | AnkiConnect (HTTP action) |
|---|---|---|
| `isAvailable` | `isAnkiDroidAvailable` (package check) | `version` answers |
| `requestPermission` | `com.ichi2.anki.permission.READ_WRITE_DATABASE` | `requestPermission` → `granted` |
| `addNote` | `addNote` (creates deck if absent) | `createDeck` (idempotent) then `addNote` |
| `updateNote` | `updateNoteFields` + `updateNoteTags` | `updateNoteFields` + `updateNoteTags` |
| `noteExists` | `getNote(noteId) != null` | `notesInfo` → non-empty object |
| `currentDeck` | `getCardDeck` (ContentProvider card → `DECK_ID` → name) | `notesInfo` → `cards` → `getDecks` |
| `moveToDeck` | `moveNoteToDeck` (ContentProvider card `DECK_ID` update) | `createDeck` then `changeDeck` |

Both `currentDeck` and `moveToDeck` degrade gracefully: a transport that cannot read or change a card's deck returns `null` / no-ops rather than throwing.

Transport failures: per-note failures return `-1`/`false` or throw `AnkiNoteFailure(message)` (recorded against the note, sync continues); collection-level fatal conditions throw `AnkiSyncAbort(message)` (recorded, sync stops). These two exceptions are consumed only by `AnkiSyncService.syncVault`.

## Triggers

| Trigger | Path |
|---|---|
| **`interest://sync-anki` deep link** (the primary path — fired by the Problem Notes Obsidian plugin) | `SyncActivity` → headless `ankiSyncMain` Dart entrypoint → `AnkiSyncController.sync(AnkiDroidTransport())`; progress as a notification |
| **Sources → Anki desktop** (manual) | `AnkiSyncController.sync(AnkiConnectTransport())` → result dialog/snackbar |

There is no AnkiDroid sync row in the app — the deep link is the only AnkiDroid trigger. No background scheduler.

## The deep-link sync contract (Android)

`interest://sync-anki` is the one contract between Interest and the Problem Notes Obsidian plugin: the plugin's sync button fires it; Interest runs the whole-vault AnkiDroid push **without bringing its main UI to the foreground**, so the user stays in Obsidian.

```
interest://sync-anki  (VIEW intent)
  → SyncActivity                         transparent, excludeFromRecents,
                                         noHistory, separate taskAffinity,
                                         singleInstance — draws nothing
      getDartEntrypointFunctionName() = "ankiSyncMain"   ← its own Flutter engine
      configureFlutterEngine: registers AnkiBridge (ankidroid channel)
                              + the `com.nimeesh.interest/sync` channel
  → ankiSyncMain()  (lib/anki_sync_entrypoint.dart)
      notify "Syncing problem notes to AnkiDroid…"  (ongoing)
      AnkiDroidTransport.isAvailable / requestPermission
      AnkiSyncController.sync(AnkiDroidTransport())
      notify "N synced (A added, U updated)"         (result)
      channel.invoke("finish")  → SyncActivity.finish()
```

The sync logic itself is unchanged from any other trigger; only *how it starts* and *how progress shows* differ. Progress surfaces via an Android notification (`SyncNotifier.kt`); `POST_NOTIFICATIONS` is requested best-effort (Android 13+) — the sync runs regardless of whether the notification is allowed.

`MainActivity` is now a plain `FlutterActivity` — it hosts only the Collections/Projects UI and has no Anki or deep-link code.

> **Status:** this transparent-trampoline path compiles and the debug APK builds, but its runtime behaviour has **not been verified on a physical device** in the current environment. A fully invisible (zero-flash) variant would use a foreground Service + a long-lived background isolate; the trampoline is the cleanest reliable approximation and is what is shipped.

## `anki_note_id` — the only vault write

Only `anki_note_id` is ever written back to a vault file, via `AnkiSyncService._patchAnkiNoteId` → `patchFrontmatterField` (patches in place, never rebuilds frontmatter, **never touches the body**). This is the entire vault-write surface of the sync.

```yaml
anki_note_id: 1234567890   # collection note id (epoch-millis Long)
```

**The id means the same thing on both transports**: it is the Anki *collection's* note id, which AnkiWeb preserves when syncing the collection between AnkiDroid and Anki desktop. A note first pushed via AnkiDroid updates cleanly via AnkiConnect later (and vice versa) **provided the user syncs their Anki collection via AnkiWeb in between**. If they don't, `noteExists` returns false in the other collection, the sync re-adds the note there and overwrites the frontmatter id — the same self-healing path as "deleted from Anki".

### Update vs. first push

| `anki_note_id` present? | Note exists in Anki? | Action |
|---|---|---|
| No | — | `addNote` → write ID back to frontmatter |
| Yes | Yes | `updateNote` (fields + tags), then move the card if its deck changed |
| Yes | No (deleted / collection never synced) | `addNote` → overwrite ID in frontmatter |

## Deck mapping

The `category:` frontmatter field is the deck name; absent means `"Default"`. Both transports look-up-or-create (AnkiDroid `getOrCreateDeck` in `AnkiBridge.kt`; AnkiConnect idempotent `createDeck`).

**Deck move on category change.** A new note is added straight into its `category:` deck. For an existing note, `updateNote` only rewrites fields/tags, so after a successful update the core asks `transport.currentDeck(noteId)` and, if it differs from the `category:`-derived deck, calls `transport.moveToDeck`. If the transport can't report the current deck (`null`), the move is skipped.

## Note model

Both transports create notes only on the model literally named **`Basic`** (fields `Front`/`Back`). If it is missing the sync aborts: AnkiDroid surfaces `BASIC_MODEL_NOT_FOUND`; AnkiConnect checks `modelNames` once per sync.

## What is NOT synced

Review history, intervals, ease factors, due dates; FSRS/SM-2 scheduling state; deck options/templates; media; notes without a `***` separator.

## Card-body wikilinks → Obsidian

Every `[[wikilink]]` in a synced card body is rewritten to an `obsidian://open` link to the target note (`obsidianUriForName` in `md_utils.dart`), the same scheme and encoding as the source link at the top of the card.

| Vault syntax | Rendered in the card |
|---|---|
| `[[Note Name]]` | `<a href="obsidian://open?vault=<vault>&file=Note%20Name">Note Name</a>` |
| `[[Note Name\|alias]]` | `<a href="obsidian://open?vault=<vault>&file=Note%20Name">alias</a>` |

Tapping a body wikilink during review opens the linked note in Obsidian, where the Problem Notes plugin renders a `***` note with tap-to-reveal. The rewrite (`AnkiSyncService._markdownToAnkiHtml`, via `rewriteWikilinksToHtml`) runs before Markdown→HTML conversion; vault files are never modified.

### Line breaks in card content

Standard Markdown collapses a single newline within a block to a space. Before Markdown→HTML conversion, `_markdownToAnkiHtml` promotes every lone newline (not adjacent to another) to a Markdown hard break (`<br>`). Paragraph breaks and fenced code blocks are untouched. This applies **only** to Anki card HTML.

## Obsidian note link in card front

Every card's front field is prepended with a right-aligned `obsidian://` link to the source note (`obsidianUri(vaultPath, noteFilePath)` in `md_utils.dart`). On re-sync the front is rebuilt, so a rename is reflected on the next sync. Anki's HTML renderer fires the href natively on tap; no Flutter code is involved.

## AnkiConnect specifics

- Endpoint default `http://127.0.0.1:8765`, overridable via an `## AnkiConnect` section in `Interesting/System/integrations.md` (`url: http://…`) — hand-edited; no in-app editor. A LAN URL lets an Android build push to a desktop Anki.
- Request shape: `POST {action, version: 6, params}` → `{result, error}`; HTTP status is always 200, failures arrive in `error`.
- `addNote` uses `options.allowDuplicate: true` — duplicate policy stays Interest's (one card per vault note via `anki_note_id`).
- `noteExists` reads `notesInfo`: a missing id comes back as an **empty object**, not an error.
- `Connection: close` is forced — AnkiConnect closes the socket after each response without advertising it, so a reused keep-alive connection breaks every second request.
- The wire contract is pinned by `test/anki_connect_transport_test.dart` against a fake server; the sync core by `test/anki_sync_service_test.dart`.

## MethodChannel contracts (Android)

**`com.nimeesh.interest/ankidroid`** (`AnkiBridge`, registered on `SyncActivity`):

| Method | Args | Returns |
|---|---|---|
| `isAnkiDroidAvailable` | — | `bool` |
| `requestPermission` | — | `bool` |
| `addNote` | `deckName, front, back, tags` | `Long` (noteId, or -1) |
| `updateNote` | `noteId, front, back, tags` | `bool` |
| `noteExists` | `noteId` | `bool` |
| `getCardDeck` | `noteId` | `String?` |
| `moveNoteToDeck` | `noteId, deckName` | `bool` |

**`com.nimeesh.interest/sync`** (`SyncActivity`): `notify {title, text, ongoing}` posts/updates the sync notification; `finish` finishes the trampoline activity.

Android implementation uses `AddContentApi` and `FlashCardsContract` from `com.github.ankidroid:Anki-Android:api-2.0.0:api@aar`.
