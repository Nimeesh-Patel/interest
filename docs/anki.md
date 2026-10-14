# Anki sync

## Overview

Revising an existing Problem Note retains its Anki identity and review history,
regardless of the extent of the revision (current decision, 2026-09-22). This
does not settle predecessor handling for splits, merges or withdrawal.

Identity writes use the shared source-span frontmatter patcher. It preserves
the original body, unrelated metadata, line endings and UTF-8 BOM rather than
rebuilding the note through the read-only parser. Invalid or unsupported
frontmatter is refused. A refusal after an external create remains a partial
projection requiring reconciliation; this patch does not add crash recovery
or change sync discovery's separate metadata-validation boundary.

Problem notes whose `***` split has non-empty problem and conjecture sides, with no `collection:` key, are pushed to Anki as Basic cards. Blank templates and unfinished structural notes are not review-ready. Collection membership opts out of Anki, including notes that also have a category; an existing projection is retired and its local ID cleared only after verified absence. The `***` body structure and local Problem Notes rendering remain unchanged. Sync is **one-way: vault → Anki**, over either of two transports:

| Transport | Backend | Wire protocol | Platform |
|---|---|---|---|
| `AnkiDroidTransport` | AnkiDroid app | ContentProvider via MethodChannel (`AnkiBridge.kt`, `AddContentApi`) | Android only |
| `AnkiConnectTransport` | Anki desktop + [AnkiConnect](https://git.sr.ht/~foosoft/anki-connect) add-on | HTTP, default `http://127.0.0.1:8765`, API version 6 | Pure Dart — any platform that can reach the URL |

Anki never originates data; the vault remains the source of truth. Ordinary updates do not read or rewrite scheduling, ease factors or due dates. Retirement deliberately deletes the native note and its cards, including their review history; a source-link mismatch or unavailable observation refuses that deletion.

The whole sync stack lives self-contained under `lib/features/anki/`, with zero dependency on the Collections entity-body viewer. Obsidian + the Problem Notes plugin own Problem Note editing and review.

## Architecture

```
AnkiProblemNoteScanner.scan(vaultPath, excludedFolders)   ← current-state discovery
  → AnkiProblemNoteScanResult                              ← notes + completeness/errors
  → AnkiSyncController.sync(transport)
  → AnkiSyncService.syncVault(transport, problemNotes, vaultPath)   ← shared core
       → AnkiTransport                                              ← per-backend
            AnkiDroidTransport   → MethodChannel → AnkiBridge → AnkiDroid ContentProvider
            AnkiConnectTransport → HTTP POST     → AnkiConnect → Anki desktop
```

`AnkiProblemNoteScanner` uses `CurrentVaultContent`, the shared path-eligibility owner also used by Collections. Root notes and `Clippings/` are current authored surfaces. `.perspirator` rollback/history, `.trash`, `.obsidian`, Templates, Attachments, Basic Memory, and `Interesting/` are never card sources; configured exclusions are additive. Collection notes with an existing ID become retirement candidates even if their former separator has been removed. Other sources honour `exclude_resurface: true` and require a non-empty `splitFrontBack`. Duplicate IDs across active and retiring sources, malformed frontmatter, ambiguous category values and traversal/read errors make discovery incomplete; the controller then changes no cards.

`AnkiSyncService` owns everything both transports must agree on — rendering, category/deck mapping, source links, local identity and collection withdrawal — so the same note yields the same projection whichever transport carries it. Transports translate seven operations into their wire protocol:

| `AnkiTransport` method | AnkiDroid (MethodChannel) | AnkiConnect (HTTP action) |
|---|---|---|
| `isAvailable` | `isAnkiDroidAvailable` (package check) | `version` answers |
| `requestPermission` | `com.ichi2.anki.permission.READ_WRITE_DATABASE` | `requestPermission` → `granted` |
| `addNote` | `addNote` (creates deck if absent) | `createDeck` (idempotent) then `addNote` |
| `updateNote` | `updateNoteFields` + `updateNoteTags` | `updateNoteFields` + `updateNoteTags` |
| `noteExists` | `getNote(noteId) != null` | `notesInfo` → non-empty object |
| `moveToDeck` | `moveNoteToDeck` (ContentProvider card `DECK_ID` update) | `createDeck` then `changeDeck` |
| `retireNote` | Exact note query, source-link guard, ContentProvider delete, absence verification | `notesInfo`, source-link guard, `deleteNotes`, `notesInfo` absence verification |

`moveToDeck` is applied idempotently after every existing-note update and every new/recovered note's local identity patch. New IDs remain linked even if placement fails, allowing a retry in place. Android verifies the actual card deck IDs after a move rather than treating a no-op update as success. Unknown native note cursors/responses are not interpreted as missing notes.

The transport also exposes the shared external-projection lifecycle as
capabilities rather than pretending every backend supports every correction:
`read`, `create`, `update`, `verify` and source-guarded `retire` are supported;
local vault-id patches can be rolled back in-process, but Anki mutations cannot.
The operation names are open strings, so a future projection can add a
capability without changing a closed enum in the core.

Transport failures: per-note failures return `-1`/`false` or throw `AnkiNoteFailure(message)` (recorded against the note, sync continues); collection-level fatal conditions throw `AnkiSyncAbort(message)` (recorded as a failure, remaining notes counted unattempted, sync incomplete). `noteExists` is tri-state: `false` is a confirmed absence, while `null` is an unavailable observation and never triggers re-addition. These exceptions are consumed only by `AnkiSyncService.syncVault`.

## Triggers

| Trigger | Path |
|---|---|
| **`interest://sync-anki` deep link** (the primary path — fired by the Problem Notes Obsidian plugin) | `MainActivity` (VIEW intent) → deeplink channel → `HomeScreen._syncAnkiFromDeeplink` → `runAnkiDroidSync` → `AnkiSyncController.sync(AnkiDroidTransport())`; result as a snackbar |
| **Sources → AnkiDroid** (manual, Android only) | same `runAnkiDroidSync` → `AnkiSyncController.sync(AnkiDroidTransport())` → result snackbar/dialog |
| **Sources → Anki desktop** (manual) | `AnkiSyncController.sync(AnkiConnectTransport())` → result dialog/snackbar |

The deep link and the Sources AnkiDroid row share `runAnkiDroidSync`, so they behave identically. No background scheduler.

### Targeted desktop CLI

`dart run tool/sync_anki_notes.dart --vault <path> --file <note.md> [--file ...]` uses the same scanner, renderer, sync core, and AnkiConnect transport as Interest. It deliberately requires exact file arguments and rejects paths outside the vault. This gives restructuring transactions a bounded sync without an ad-hoc renderer or an implicit whole-vault push. Whole-vault sync remains an Interest UI operation.

## The deep-link sync contract (Android)

`interest://sync-anki` is the one contract between Interest and the Problem Notes Obsidian plugin: the plugin's sync button fires it; Interest **opens to the foreground** and runs the whole-vault AnkiDroid push there, reporting via a snackbar. The app surfacing is expected and accepted — viewing stays in Obsidian, but the sync itself runs in Interest's normal UI.

```
interest://sync-anki  (VIEW intent on MainActivity, launchMode=singleTop)
  ├─ cold start → onCreate sets pendingSyncAnki
  │                Flutter pulls it once via deeplink.getInitialSyncAnki
  └─ running app → onNewIntent → deeplink.invokeMethod("syncAnki")
  → HomeScreen._syncAnkiFromDeeplink()  (lib/screens/home_screen.dart)
      snackbar "Syncing problem notes to AnkiDroid…"
      runAnkiDroidSync(context)  (lib/features/anki/services/anki_sync_runner.dart)
        AnkiDroidTransport.isAvailable / requestPermission
        AnkiSyncController.sync(AnkiDroidTransport())
        showAnkiSyncResult → snackbar on complete success
                             or an explicit incomplete/failures dialog
```

The sync logic itself is unchanged from any other trigger; only *how it starts* differs. `AnkiBridge` (the AnkiDroid ContentProvider bridge) is registered on `MainActivity`; `MainActivity.onRequestPermissionsResult` forwards into `AnkiBridge.onRequestPermissionsResult`, so the first-run `READ_WRITE_DATABASE` grant completes through the normal Activity permission flow. `MainActivity` uses `launchMode=singleTop`, so a deep link to a running app arrives via `onNewIntent` rather than relaunching.

## `anki_note_id` — the only vault write

Only `anki_note_id` is written or removed in a vault file. Creation/recovery uses `AnkiSyncService._patchAnkiNoteId` → `patchFrontmatterField`; retirement preflights `prepareFrontmatterField` and applies its unchanged-source patch after native absence is verified. Both use the same source-span patcher, preserving unrelated metadata and **never replacing the body**. The applied patch has a verified result and stale-safe local rollback. An external create/deletion followed by a failed local patch is reported as a partial projection; it is not claimed as success or as reversible native review history.

```yaml
anki_note_id: 1234567890   # collection note id (epoch-millis Long)
```

The id is an Anki *collection's* note id, which AnkiWeb preserves when syncing a collection between AnkiDroid and Anki desktop. A note first pushed through one transport updates through the other only after the two Anki collections share that identity. A confirmed absence in the active collection follows the same re-add path as deletion; an unavailable identity observation stops that note without mutation. If two eligible vault notes claim one ID, discovery stops before any card mutation.

### Update vs. first push

| `anki_note_id` present? | Note exists in Anki? | Action |
|---|---|---|
| No | — | `addNote` → write ID back to frontmatter |
| Yes | Yes | `updateNote` (fields + tags), then move the card if its deck changed |
| Yes | Confirmed no (deleted / collection never synced) | `addNote` → overwrite ID in frontmatter |
| Yes | Unknown / unavailable | Fail that note without adding or updating |

## Deck mapping

The `category:` frontmatter field is the deck name, as text or a singleton text list; leading/trailing whitespace is trimmed. Missing/empty means `"Default"`. Multiple distinct names or non-text values are refused rather than projected to Default. Both transports look up or create the requested deck; manually created decks are reused. Collection membership takes precedence over category and opts out of Anki.

**Deck projection.** Create/update is followed by explicit deck placement, including recovery of an existing duplicate by Android. A failed placement is explicit even though the field/tag update or creation has already happened. Native card IDs and review history are preserved during ordinary deck changes.

## Collection withdrawal

Sync preflights a source-span removal of `anki_note_id` against the current file before mutating Anki. The file must still be a collection note with the expected ID. The native note must carry the exact Obsidian source href; unrelated cards are refused. After deletion, the transport must observe absence before the prepared local patch is applied. A confirmed already-absent projection can clear a stale ID. Failed reads, deletes, verification or local patches retain a visible failure and any remaining ID for reconciliation/retry. An intervening source edit is preserved rather than overwritten. This is a sequential distributed operation, not an atomic rollback of native review history.

## Note model

Both transports create notes only on the model literally named **`Basic`** (fields `Front`/`Back`). If it is missing the sync aborts: AnkiDroid surfaces `BASIC_MODEL_NOT_FOUND`; AnkiConnect checks `modelNames` once per sync.

## What is NOT synced

Review history, intervals, ease factors, due dates; FSRS/SM-2 scheduling state; deck options/templates; media. Notes without a complete `***` split are not created/updated as cards, and collection notes only withdraw former projections. Source deletion, split/merge retirement and `exclude_resurface` retirement are outside this correction.

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
- `noteExists` reads `notesInfo`: a missing id comes back as an **empty object** (`false`); transport/protocol failure returns `null`.
- `Connection: close` is forced — AnkiConnect closes the socket after each response without advertising it, so a reused keep-alive connection breaks every second request.
- The wire contract is pinned by `test/anki_connect_transport_test.dart` against a fake server; the sync core by `test/anki_sync_service_test.dart`.

## MethodChannel contracts (Android)

**`dev.interest.app/ankidroid`** (`AnkiBridge`, registered on `MainActivity`):

| Method | Args | Returns |
|---|---|---|
| `isAnkiDroidAvailable` | — | `bool` |
| `getAnkiDroidVersion` | — | Installed version name or null |
| `requestPermission` | — | `bool` (true if already granted, else requests via the Activity and resolves on the result) |
| `addNote` | `deckName, front, back, tags` | Positive `Long` noteId, or explicit error |
| `updateNote` | `noteId, front, back, tags` | `bool` |
| `noteExists` | `noteId` | `bool`; unavailable or invalid observation is an error |
| `moveNoteToDeck` | `noteId, deckName` | `bool` |
| `retireNote` | `noteId, expectedSourceUri` | `true` only after verified absence; source mismatch is an error |

**`dev.interest.app/deeplink`** (`MainActivity`): `getInitialSyncAnki` → `bool` (Flutter pulls a cold-start `interest://sync-anki` once); native→Flutter `syncAnki` invoked from `onNewIntent` when a running app receives the deep link.

Android implementation uses `AddContentApi` and `FlashCardsContract` from `com.github.ankidroid:Anki-Android:api-v1.1.0`, as pinned in `android/app/build.gradle.kts`.

## Device verification

The Flutter tests cover discovery, source-span ID removal, role changes, partial outcomes and both transport contracts. The opt-in `AnkiBridgeDeviceChecks` instrumentation runner also exercises the actual installed AnkiDroid provider. It requires Interest's normal Anki permission and an existing ordinary deck other than Default. It creates only uniquely identified temporary notes, verifies existing-deck reuse and placement, ordinary updates, source-guarded withdrawal and repeat withdrawal, then removes its own notes. It creates no decks, launches no sync and edits no vault files.

```text
cd android
gradlew :app:assembleDebugAndroidTest
adb -s DEVICE install -r ../build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s DEVICE shell am instrument -w -e deckName Vocabulary dev.interest.app.test/dev.interest.app.AnkiBridgeDeviceChecks
adb -s DEVICE uninstall dev.interest.app.test
```

Install the matching debug app first. Check `INSTRUMENTATION_RESULT: result=PASS`; the shell command's exit code alone is insufficient. On 2026-10-14, these checks passed on the user's Moto G45 with AnkiDroid 2.25.1 against the existing Vocabulary deck. Both temporary notes were verified absent, and the test package was removed. The updated Interest app remains installed with its permission retained. Whole-vault sync and first-time permission/deep-link delivery were not invoked by these device checks.

## Concurrent requests and source freshness

The shared sync core obtains one non-blocking lease per resolved physical vault,
with an in-process guard and OS file lock. It covers UI, deep link and file CLI
mutations; it does not coordinate separately mirrored vaults on other devices.
The empty `Interesting/System/.anki-sync.lock` must not be unlinked while a
process could hold it. It is coordination state, never knowledge.

Discovery carries the exact source, including BOM/line endings. A changed
snapshot is refused before mutation; edits observed during external operations
are reported as partial outcomes requiring a fresh sync. Creation validates
its local identity patch before adding a native card. One add/link/deck helper
owns both first creation and re-creation. All local ID writes/removals use
`MarkdownFile` staging; native review history is still not atomically reversible.
Source hrefs use vault-relative paths, including subfolders. Older ambiguous
hrefs are not sufficient authority for retirement.

The UI and exact-file CLI load the same authored integration configuration.
Absent configuration retains defaults; invalid/unreadable configuration and
ambiguous sections are explicit errors. Editing exclusions preserves endpoints,
unknown keys and unrelated sections through the shared source transaction.
Run `dart run tool/check_sync_lock.dart` for the independent-process lease
check against a disposable vault.
