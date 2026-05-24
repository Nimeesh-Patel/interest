# ReadEra Subsystem

Import-only enrichment source for canonical book objects. Parses a ReadEra `.bak` backup file and merges highlights into existing `Interesting/Books/*.md` files. ReadEra is one of several systems that enrich the same canonical book container — it patches only its owned section and never touches Readwise or Hardcover data.

Full book ontology, schema, and field-ownership rules: [docs/books.md](books.md).

---

## Backup format

A ReadEra `.bak` file is a **ZIP archive** containing:

| File | Role |
|------|------|
| `library.json` | All books and highlights — the only file parsed |
| `meta.json` | Backup metadata (app version, date) |
| `prefs.xml`, `search-history.xml` | Ignored |

`library.json` structure:

```
root.docs[]            — one entry per book
  .data                — book metadata
    doc_sha1           — content hash (stable book identifier within the backup)
    doc_title          — book title
    doc_authors        — author string (may be comma-separated)
  .citations[]         — highlights for this book
    note_uri           — UUID — stable deduplication key
    note_body          — highlighted text
    note_page          — page number (int, may be absent)
    note_insert_time   — Unix millisecond timestamp
    note_type          — always 3 (selected passage)
```

Books with an empty `doc_title` are skipped (files where metadata extraction failed).

---

## Markdown output

Highlights are written into a `## Highlights (ReadEra)` section — separate from Readwise's `## Highlights`. Both sections coexist in the same book file.

```markdown
## Highlights (ReadEra)

> Highlighted text from the book.

^recc307469-e975-48c1-be41-7cad4eda1fde
Page 6 · Added: 2024-01-12

---

> Another selected passage.

^re3f8a1b2c-...
Page 42 · Added: 2025-03-07

---
```

**Deduplication anchor:** `^re{note_uri}` (UUID). On re-import, the file is scanned with `RegExp(r'\^re([a-f0-9\-]{36})')` to find already-imported highlights — only new ones are appended.

**No ReadEra-specific frontmatter fields.** `updated_at` is stamped on import via `BookStorageService.patchFields()`.

---

## Services

### `ReaderaParser` (`lib/features/readera/services/readera_parser.dart`)

All-static. Opens the `.bak` as a ZIP via `package:archive`, extracts `library.json`, parses it into models.

Returns `ReaderaParseResult` (named record):
```dart
({List<ReaderaBook> books, List<ReaderaHighlight> highlights, String? error})
```

Defensive: if `library.json` is absent, returns a descriptive error string with the actual filenames found. Never throws.

### `ReaderaIngestionService` (`lib/features/readera/services/readera_ingestion_service.dart`)

All-static. Orchestrates the full import pipeline:

1. `ReaderaParser.parse(bakFilePath)` → books + highlights
2. Index highlights by `bookId` (doc_sha1) for O(1) lookup
3. For each book: `BookStorageService.reconcile(vaultPath, title: title)` — title-slug matching only (no ISBN in ReadEra exports)
4. No match → `BookStorageService.createBook()`
5. Scan file for existing `^re{uuid}` anchors → compute new-only set
6. `BookStorageService.appendReaderaHighlights(filePath, newHighlights)`
7. `BookStorageService.patchFields(filePath, {'updated_at': now})`

Returns `ImportResult(created, updated, skipped, error)` — same type used by RSS ingestion.

---

## Models

### `ReaderaBook` (`lib/features/readera/models/readera_book.dart`)

| Field | Source |
|-------|--------|
| `id` | `doc_sha1` — content hash, used to group highlights with their book |
| `title` | `doc_title` |
| `author` | `doc_authors` (raw string; split on `', '` when building `Book.authors`) |

### `ReaderaHighlight` (`lib/features/readera/models/readera_highlight.dart`)

| Field | Source |
|-------|--------|
| `id` | `note_uri` (UUID) — dedup anchor |
| `bookId` | `doc_sha1` of parent book |
| `text` | `note_body` |
| `page` | `note_page` (`int?`) |
| `createdAt` | `note_insert_time` converted from Unix ms to ISO 8601 |

---

## UI

Settings screen → **ReadEra** section → **Import from .bak** button.

Tapping opens a file picker (`file_picker`, extension filter: `bak`). On selection: `ReaderaIngestionService.ingest()` → SnackBar with `result.summary`.

No configuration required — no token, no API, no stored state.

---

## Boundaries (do not violate)

- Write only via `BookStorageService` — never direct file I/O to `Interesting/Books/`
- Patch only `updated_at` in frontmatter — never touch Readwise or Hardcover owned fields
- `## Highlights (ReadEra)` is append-only — never delete or reorder existing `^re{uuid}` blocks
- `^re{uuid}` format is the deduplication mechanism — do not change
- No auto-import, no background polling, no config stored in `integrations.md`
