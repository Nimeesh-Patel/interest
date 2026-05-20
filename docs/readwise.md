# Readwise Subsystem

Ingestion-only integration: Readwise API → book highlight files in `Interesting/Books/`. One `.md` file per book. The app is a write-once, append-on-reimport layer — it never deletes or overwrites user edits.

**Why Books/ is separate from Entities/.** Readwise book files use a different schema (`type: book_highlights`, no `alias`) and are not loaded by `MarkdownStorageService`. Keeping them in their own directory avoids polluting the entity graph load, makes their origin unambiguous, and allows the entity subsystem and the Readwise subsystem to evolve independently.

---

## Setup

In the app: **Settings → Readwise → Access Token**

Enter your Readwise access token from [readwise.io/access_token](https://readwise.io/access_token). Stored locally in SharedPreferences; never uploaded anywhere.

Tap **Open Import Screen** (Settings) or the `book_outlined` AppBar icon to open the import screen.

---

## Markdown File Format

### Location

`Interesting/Books/<sanitized-title>.md` — one file per book, filename derived from book title via `sanitizeFilename()`.

### Example

```markdown
---
type: book_highlights
source: readwise
title: "The Beginning of Infinity"
author: David Deutsch
readwise_id: 12345
readwise_category: books
num_highlights: 42
last_highlight_at: 2024-01-15T10:30:00.000Z
updated_at: 2024-01-20T08:00:00.000Z
---

# The Beginning of Infinity

*David Deutsch*

## Highlights

> Problems are inevitable.

^rw112233
Location: 124 · Tags: epistemology, optimism

---

> The beginning of infinity is the beginning of the unlimited reach of knowledge.

^rw112244
Location: 201

---

## Notes

User-added sections are preserved verbatim on every re-import.
```

### Frontmatter fields

| Field | Description |
|-------|-------------|
| `type` | Always `book_highlights` — distinguishes from entity files |
| `source` | Always `readwise` |
| `title` | Book title (YAML-quoted if it contains `: `) |
| `author` | Author string from Readwise API |
| `readwise_id` | Readwise book ID (integer) — stable identity anchor |
| `readwise_category` | Readwise category: `books`, `articles`, `tweets`, etc. |
| `num_highlights` | Highlight count as reported by Readwise (updated on re-import) |
| `last_highlight_at` | ISO 8601 UTC timestamp of most recent highlight (updated on re-import) |
| `updated_at` | ISO 8601 UTC timestamp of last import by this app |

### Highlight block structure

Each highlight is rendered as:

```
> {highlight text}

**Note:** {note text}    ← only if note is non-empty

^rw{id}
Location: {location} · Tags: {tag1, tag2}    ← omit parts that are absent

---

```

- `^rw{id}` is an Obsidian block-reference ID on its own line after the blockquote. It is the **deduplication key** used on re-import — `ReadwiseService._patchBookFile` scans for all `^rw(\d+)` matches in the existing file before deciding which highlights to append.
- Each block ends with a `---` separator followed by a blank line for visual clarity.
- `## Highlights` is app-owned: re-import appends to it. All other `##` sections are user territory — preserved verbatim.

---

## Service (`lib/features/readwise/services/readwise_service.dart`)

All-static, all-catch-null. Never throws. Follows `LetterboxdService` / `AnkiConnectService` pattern.

### Token storage

| Method | Description |
|--------|-------------|
| `getToken()` | Reads from SharedPreferences key `readwise_access_token` |
| `setToken(token)` | Writes to SharedPreferences |
| `clearToken()` | Removes from SharedPreferences |

### API methods

Auth header on every request: `Authorization: Token {token}`

| Method | Endpoint | Returns |
|--------|----------|---------|
| `fetchBooks(token)` | `GET /api/v2/books/?page_size=1000` | `List<ReadwiseBook>?` |
| `fetchHighlights(token, bookId)` | `GET /api/v2/highlights/?book_id={id}&page_size=1000` | `List<ReadwiseHighlight>?` |

Both methods handle pagination by following `next` URL until null. Return `null` on any error (network, non-200 status, parse failure).

### Import method

```dart
static Future<ImportResult> importBook(
  ReadwiseBook book,
  List<ReadwiseHighlight> highlights,
  String vaultPath,
)
```

Returns `ImportResult` (reused from `LetterboxdService`): `created=1` for new file, `updated=1` for patched file.

**Logic:**
1. Ensure `VaultService.booksPath(vaultPath)` exists.
2. Compute filename: `${sanitizeFilename(book.title)}.md`.
3. If file does not exist → `_buildBookMarkdown(book, highlights)` → write.
4. If file exists → `_patchBookFile(existingContent, book, highlights)` → write.

### Patch algorithm (`_patchBookFile`)

1. `splitFrontmatter(existing)` → YAML + body. If malformed → rebuild from scratch.
2. Regex-scan full file for `\^rw(\d+)` → `Set<int> existingIds`.
3. Filter `highlights` to those whose `id` ∉ `existingIds`.
4. Rebuild frontmatter (update `num_highlights`, `last_highlight_at`, `updated_at`; all other fields from current `book` data).
5. Reconstruct body: preserve H1 + preamble (content between H1 and first H2); for `## Highlights` section append new highlight blocks after existing content; all other sections preserved verbatim from `parseSectionsH2`.
6. Return patched string.

---

## Models

### `ReadwiseBook` (`lib/features/readwise/models/readwise_book.dart`)

| Field | Type | Source |
|-------|------|--------|
| `id` | `int` | `json['id']` |
| `title` | `String` | `json['title']` |
| `author` | `String` | `json['author']` |
| `category` | `String` | `json['category']` — `'books'`, `'articles'`, etc. |
| `numHighlights` | `int` | `json['num_highlights']` |
| `lastHighlightAt` | `String?` | `json['last_highlight_at']` — ISO 8601 |
| `coverImageUrl` | `String?` | `json['cover_image_url']` |
| `sourceUrl` | `String?` | `json['source_url']` |

### `ReadwiseHighlight` (`lib/features/readwise/models/readwise_highlight.dart`)

| Field | Type | Source |
|-------|------|--------|
| `id` | `int` | `json['id']` |
| `text` | `String` | `json['text']` |
| `note` | `String?` | `json['note']` |
| `location` | `String?` | `json['location'].toString()` (null if 0 or absent) |
| `highlightedAt` | `String?` | `json['highlighted_at']` |
| `tags` | `List<String>` | `json['tags'][*]['name']` |

---

## UI (`lib/features/readwise/screens/readwise_screen.dart`)

Opened from `SettingsScreen` → "Open Import Screen" button (bottom of Readwise section). There is no direct AppBar shortcut.

**Empty state:** shown when no token is configured — directs user to Settings.

**Book list:** one `ListTile` per book showing title, author, category chip, highlight count, last-highlight date. Per-book **Import** button. AppBar **Import All** icon (downloads + imports sequentially to avoid flooding the API).

**Import flow per book:**
1. `ReadwiseService.fetchHighlights(token, book.id)`
2. `VaultService.getVaultPath()`
3. `ReadwiseService.importBook(book, highlights, vaultPath)`
4. Show inline result: "Imported (N highlights)" / "Updated" / "Error: ..."

**Settings section** (`SettingsScreen`): masked token text field + Save Token button + "Open Import Screen" button. On save, token written to SharedPreferences immediately.

---

## Boundaries (do not violate)

- Book files live in `Interesting/Books/` only — never write to `Entities/`
- `MarkdownStorageService` never loads `Books/` files — they have no `alias` and are not entities
- Re-import is append-only — never delete or overwrite existing highlight blocks
- The `^rw{id}` block ID is the sole deduplication mechanism — do not change this format
- No auto-sync, no background polling, no scheduled tasks
- Do not implement: highlights → Anki cards, semantic wikilinking, concept extraction, graph integration, Reader API ingestion, popular highlights (Phase 1 scope)
