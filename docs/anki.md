# Anki Subsystem

Bidirectional synchronization between Markdown cards in `Interesting/Anki/` and Anki notes via the AnkiConnect API. Self-contained subsystem (three services + two screens) that follows the same filesystem-native, no-database philosophy as the rest of the app.

**Why Anki is the one bidirectional exception.** Most integrations in this app are unidirectional: Letterboxd ingests in, Grokipedia reads out. Anki is different because it has its own independent state — review scheduling (intervals, ease, due dates) that the app has no business owning. The design response is a clean ownership split: Markdown owns semantic content (front/back/text, tags, deck); Anki owns scheduling. The app never writes review metadata to Markdown. This is also why deletion must be soft: a hard-deleted card re-synced from Anki would be recreated with a new `anki_id`, permanently breaking the identity chain.

---

## Setup (Required Before First Sync)

### Communication architecture

```
Flutter app (Android)
  → WiFi/LAN
  → AnkiConnect add-on (running inside Desktop Anki)
  → Desktop Anki
  → AnkiWeb (standard Anki sync)
```

The app does **not** talk to Anki mobile directly. Desktop Anki is the bridge: it runs the AnkiConnect API server, the app pushes/pulls semantic content to it over the local network, and Desktop Anki then syncs review state to AnkiWeb normally. This preserves Markdown-first ownership of content and Anki's scheduling engine for review.

### Step 1 — Install Desktop Anki

Download and install from https://apps.ankiweb.net/

### Step 2 — Install the AnkiConnect add-on

Inside Desktop Anki: **Tools → Add-ons → Get Add-ons**

Enter add-on code: **2055492159**

Restart Anki after installation. Add-on page: https://ankiweb.net/shared/info/2055492159

### Step 3 — Verify AnkiConnect is running

With Anki open, visit in a browser:

```
http://localhost:8765
```

Expected response: `{"apiVersion":"AnkiConnect v.6"}`

If this fails, AnkiConnect is not installed or Anki is not open.

### Step 4 — Allow LAN access (phone requires this)

By default AnkiConnect only accepts `localhost`. To allow the phone to connect over WiFi, change the bind address:

**Tools → Add-ons → AnkiConnect → Config**

```json
{
  "webBindAddress": "0.0.0.0",
  "webBindPort": 8765,
  "apiLogPath": null,
  "apiPollInterval": 1
}
```

Restart Anki after saving.

### Step 5 — Find the desktop's LAN IP

On Windows (run in terminal):

```
ipconfig
```

Look for **Wireless LAN adapter Wi-Fi → IPv4 Address**, e.g. `192.168.0.105`. Do not use the gateway IP (`192.168.0.1` — that is the router).

If `http://192.168.0.105:8765` does not respond in a browser, Windows Firewall is likely blocking it. Allow **Anki** (or port **8765**) on private networks.

### Step 6 — Configure the app

In the Flutter app: **Settings → AnkiConnect URL**

Enter:
```
http://<your-desktop-ip>:8765
```

Tap **Test Connection**. A green "Connected" confirms the phone can reach AnkiConnect.

### Sync architecture summary

| What syncs | Via |
|------------|-----|
| Semantic content (front/back/text, tags, deck) | This app ↔ AnkiConnect |
| Review state (intervals, ease, due dates) | Desktop Anki ↔ AnkiWeb |

The app is the semantic synchronization layer. It never touches review metadata.

---

## Vocabulary

- **Anki note**: content record in Anki (fields + tags). One note → one or more review cards.
- **AnkiCard**: the app's model (`lib/features/anki/models/anki_card.dart`). Maps 1:1 to an Anki note and 1:1 to a Markdown file.
- **`anki_id`**: stable cross-system identity anchor. Written into Markdown frontmatter on first sync. Immutable — never regenerated.

---

## Markdown File Format

### Basic note — `Interesting/Anki/<slug>.md`

```markdown
---
anki_id: 183726271
note_type: Basic
deck: Philosophy
tags:
  - epistemology
updated_at: 2026-05-18T12:00:00.000Z
---

# Front

What is falsifiability?

# Back

Criterion proposed by Karl Popper.
```

### Cloze note — `Interesting/Anki/<slug>.md`

```markdown
---
anki_id: 183726272
note_type: Cloze
deck: Physics
tags:
  - relativity
updated_at: 2026-05-18T12:00:00.000Z
---

# Text

Einstein proposed {{c1::general relativity}} in 1915.
```

### Section parsing

Card files use H1 headers (`#`) for content sections — different from entity files which use H2 (`##`).

| Note type | Semantic sections (rewritten on save) | Preserved verbatim |
|-----------|---------------------------------------|--------------------|
| Basic     | `Front`, `Back`                       | all other `#`/`##` sections |
| Cloze     | `Text`                                | all other `#`/`##` sections |

`[[wikilinks]]` anywhere in the content are preserved intact (Obsidian-compatible).

### Frontmatter fields

| Field | Required | Notes |
|-------|----------|-------|
| `anki_id` | No | Absent on new cards; written after first push to Anki; immutable thereafter |
| `note_type` | Yes | `Basic` or `Cloze` |
| `deck` | Yes | Anki deck name |
| `tags` | Yes | YAML list; `tags: []` when empty |
| `updated_at` | Yes | ISO 8601 UTC; used for conflict resolution |

### Filename

Slugified first 50 chars of `Front` (Basic) or `Text` (Cloze). Collision suffix `-2`, `-3`. Filename is aesthetic only — `anki_id` is the stable identity.

---

## Services

### `AnkiConnectService` (`lib/features/anki/services/anki_connect_service.dart`)

All-static HTTP client for AnkiConnect. Every method catches all exceptions and returns `null`/`false` — same pattern as `GrokipediaService`.

**Configuration:** URL in SharedPreferences (key: `'anki_connect_url'`). Default: `'http://localhost:8765'`. On Android, Anki runs on a desktop — user must enter the desktop's LAN IP (e.g. `http://192.168.1.5:8765`) in Settings.

**HTTP pattern** (POST to configured URL):
```
body: {"action": action, "version": 6, "params": {...}}
response: {"result": ..., "error": null}  ← success
          {"result": null, "error": "msg"} ← failure → return null
```

**Methods and AnkiConnect actions:**

| Method | Action | Returns |
|--------|--------|---------|
| `testConnection()` | `version` | `bool` |
| `deckNames()` | `deckNames` | `List<String>?` |
| `addNote(card)` | `addNote` | `int?` (note ID) |
| `updateNote(card)` | `updateNote` | `bool` |
| `changeDeck(ankiId, deck)` | `changeDeck` | `bool` |
| `notesInfo(ids)` | `notesInfo` | `List<Map>?` |
| `findNotes(query)` | `findNotes` | `List<int>?` |

**Note type → AnkiConnect mapping:**
- Basic: `modelName: 'Basic'`, fields `{Front: ..., Back: ...}`
- Cloze: `modelName: 'Cloze'`, fields `{Text: ...}`

---

### `AnkiStorageService` (`lib/features/anki/services/anki_storage_service.dart`)

All-static service for Anki card `.md` file I/O. Writes directly to `Interesting/Anki/` — does NOT call `saveData()`, same as `LetterboxdService`.

| Method | Description |
|--------|-------------|
| `loadCards()` | Scan `Interesting/Anki/*.md` (skip `.trash/`) → `List<AnkiCard>` |
| `saveCard(card)` | Patch existing file or create new |
| `createNewCard(...)` | Build slug filename, write new file (no `anki_id` yet) |
| `updateAnkiId(path, id)` | Write `anki_id` into existing frontmatter in-place |
| `trashCard(path)` | Move file to `Interesting/Anki/.trash/` |
| `createFromAnki(ankiNote)` | Anki→MD: create new `.md` from AnkiConnect note data |

**Patch behavior:** `_patchCardContent()` rewrites only semantic sections; all extra sections preserved verbatim — mirrors `MarkdownStorageService._patchEntityContent()`.

---

### `AnkiSyncService` (`lib/features/anki/services/anki_sync_service.dart`)

Sync orchestrator. `sync()` → `AnkiSyncResult`.

```dart
class AnkiSyncResult {
  final int createdInAnki;   // new MD cards pushed to Anki
  final int updatedInAnki;   // MD→Anki content updates
  final int createdMarkdown; // Anki→MD new files created
  final int updatedMarkdown; // Anki→MD content updates
  final int trashed;         // MD files moved to .trash/
  final int skipped;         // no change needed
  final String? error;       // null = success
}
```

---

## Sync Algorithm

```
1. AnkiStorageService.loadCards()            → List<AnkiCard>
2. Split: withId (have anki_id) / withoutId
3. AnkiConnectService.findNotes('deck:*')    → all Anki note IDs
4. AnkiConnectService.notesInfo(ids)         → full note data (batched 50/request)
5. Build ankiById map: ankiId → ankiNote

── MD → Anki: new cards ──────────────────────────────────────────
6. For each card in withoutId:
     addNote() → noteId
     updateAnkiId(filePath, noteId)
     createdInAnki++

── MD ↔ Anki: existing cards ─────────────────────────────────────
7. For each card in withId:
     a. Not found in Anki          → trashCard(); trashed++; continue
     b. Δt = card.updatedAt − mod×1000ms; |Δt| ≤ 5s → skipped++
     c. Δt > 5s (MD newer)        → updateNote() [+ changeDeck if needed]; updatedInAnki++
     d. Δt < −5s (Anki newer)     → saveCard(applyAnkiNote(card, ankiNote)); updatedMarkdown++

── Anki → MD: new notes ──────────────────────────────────────────
8. For each ankiNote not matched by any withId card:
     createFromAnki(ankiNote)
     createdMarkdown++

9. Return AnkiSyncResult
```

---

## Conflict Resolution

`last_modified_wins` with 5-second tolerance.

- Markdown side: `card.updatedAt` (ISO 8601 → `DateTime`)
- Anki side: `ankiNote['mod']` (Unix seconds) → `DateTime.fromMillisecondsSinceEpoch(mod * 1000)`

When Anki wins, `_applyAnkiNote()` returns a new `AnkiCard` with Anki's fields + Anki's timestamp. `saveCard()` writes it — the next sync will see them as equal.

---

## Deletion Handling

Cards are **never hard-deleted** from Markdown.

| Trigger | Outcome |
|---------|---------|
| Card deleted from Anki (anki_id in MD, not returned by `notesInfo`) | MD file moved to `Interesting/Anki/.trash/` |
| Card deleted from app UI (future) | move to `.trash/` before removing from list |

`.trash/` is never auto-purged — user inspects and cleans it manually via file manager or Obsidian.

---

## What Is NOT Synced

Anki review metadata is **never written to Markdown**:

- intervals, ease factors, due dates
- review history, scheduling state

Only semantic content syncs: `Front`/`Back`/`Text`, tags, deck name.

---

## UI

### `AnkiScreen` (`lib/features/anki/screens/anki_screen.dart`)

Accessible via the **More** overflow menu (PopupMenuButton) in HomeScreen AppBar → "Anki". Card browser: note type chip (Basic/Cloze), deck, front/text preview, tags, unsynced indicator (cloud_off). AppBar Sync button → `AnkiSyncService.sync()` → SnackBar. FAB → new card.

### `AnkiCardEditorScreen` (`lib/features/anki/screens/anki_card_editor_screen.dart`)

- Note type toggle (Basic / Cloze ChoiceChips)
- Deck field with `Autocomplete` populated from `AnkiConnectService.deckNames()`
- Front + Back TextFields (Basic) or Text TextField (Cloze)
- Tags as comma-separated string
- Discard guard via `PopScope` (`_dirty` flag)
- Save → `AnkiStorageService.saveCard()` (existing) or `createNewCard()` (new)

### Settings section

`SettingsScreen` has an "Anki" section below Letterboxd:
- AnkiConnect URL text field (persisted; SharedPreferences key `'anki_connect_url'`)
- Test Connection button → `AnkiConnectService.testConnection()` → green/red status
