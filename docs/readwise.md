# Readwise Subsystem

Highlight-ingestion integration: Readwise API → canonical book files in `Interesting/Books/`. One `.md` file per book — the same file that `HardcoverSyncService` and the user also enrich. `ReadwiseService` is an **enrichment consumer** of `BookStorageService`; it patches only its own fields and appends highlights without touching anything else.

Full book ontology, schema, and field-ownership rules: [docs/books.md](books.md).

---

## Setup

In the app: **Settings → Readwise → Access Token**

Enter your Readwise access token from [readwise.io/access_token](https://readwise.io/access_token). Stored locally in SharedPreferences; never uploaded anywhere.

Tap **Open Import Screen** (Settings) to open the import screen.

---

## Markdown File Format

### Location

`Interesting/Books/<sanitized-title>.md` — shared with Hardcover and user prose.

### Example

```markdown
---
type: book
alias: the-beginning-of-infinity-david-deutsch
title: "The Beginning of Infinity"
authors:
  - David Deutsch
readwise_id: 12345
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

### Readwise-owned frontmatter fields

| Field | Description |
|-------|-------------|
| `readwise_id` | Readwise book ID (integer) — identity anchor for this source |
| `num_highlights` | Highlight count from Readwise API (updated on re-import) |
| `last_highlight_at` | ISO 8601 UTC timestamp of most recent highlight |

All other frontmatter fields (`alias`, `type`, `title`, `authors`, `hardcover_id`, `status`, `rating`, etc.) belong to other owners and are never overwritten by `ReadwiseService`.

### Highlight block structure

```
> {highlight text}

**Note:** {note text}    ← only if note is non-empty

^rw{id}
Location: {location} · Tags: {tag1, tag2}    ← omit parts that are absent

---

```

`^rw{id}` is an Obsidian block-reference ID and the **deduplication key** — scanned across the full file before deciding which highlights to append on re-import.

---

## Service (`lib/features/readwise/services/readwise_service.dart`)

All-static, all-catch-null. Never throws.

### Token storage

| Method | Description |
|--------|-------------|
| `getToken()` | Reads from SharedPreferences key `readwise_access_token` |
| `setToken(token)` | Writes to SharedPreferences |
| `clearToken()` | Removes from SharedPreferences |

### API methods

Auth header: `Authorization: Token {token}`

| Method | Endpoint | Returns |
|--------|----------|---------|
| `fetchBooks(token)` | `GET /api/v2/books/?page_size=1000` | `List<ReadwiseBook>?` |
| `fetchHighlights(token, bookId)` | `GET /api/v2/highlights/?book_id={id}&page_size=1000` | `List<ReadwiseHighlight>?` |

Both paginate via `next` URL. Return `null` on any error.

### Import method

```dart
static Future<ImportResult> importBook(
  ReadwiseBook book,
  List<ReadwiseHighlight> highlights,
  String vaultPath,
)
```

**Logic:**
1. `BookStorageService.reconcile(readwiseId, title)` → find existing canonical file.
2. If not found → `BookStorageService.createBook()` → append all highlights.
3. If found → `BookStorageService.patchFields({readwise_id, num_highlights, last_highlight_at, updated_at})`, then scan for existing `^rw{id}` blocks and append only new highlights.

The `_patchBookFile` / `_buildFrontmatter` methods that previously rebuilt the whole frontmatter are removed. Readwise now patches only its owned fields.

---

## Models

### `ReadwiseBook` (`lib/features/readwise/models/readwise_book.dart`)

| Field | Type |
|-------|------|
| `id` | `int` |
| `title` | `String` |
| `author` | `String` (raw; may be comma-separated multi-author) |
| `category` | `String` — `'books'`, `'articles'`, etc. |
| `numHighlights` | `int` |
| `lastHighlightAt` | `String?` — ISO 8601 |

### `ReadwiseHighlight` (`lib/features/readwise/models/readwise_highlight.dart`)

| Field | Type |
|-------|------|
| `id` | `int` |
| `text` | `String` |
| `note` | `String?` |
| `location` | `String?` (null if 0 or absent) |
| `tags` | `List<String>` |

---

## UI (`lib/features/readwise/screens/readwise_screen.dart`)

Opened from Settings → Readwise → "Open Import Screen".

Book list with per-book Import button and AppBar Import All. Import result shown inline per book.

---

## Boundaries (do not violate)

- Use `BookStorageService.reconcile()` + `patchFields()` for all file I/O — never bypass with direct file writes
- Patch only Readwise-owned fields — never touch `hardcover_id`, `status`, `rating`, `started_at`, `finished_at`
- `## Highlights` is append-only — never delete or reorder existing blocks
- `^rw{id}` deduplication format is fixed — do not change
- No auto-sync, no background polling
