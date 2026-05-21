# Books Subsystem

Books are **canonical semantic objects** — Markdown files in `Interesting/Books/` that serve as convergence points for multiple external systems (Readwise highlights, Hardcover reading states) and local user prose. Each file is owned by neither external system; both enrich the same Markdown object.

---

## Field ownership

Only the owning system overwrites a field. This is what prevents enrichment systems from clobbering each other.

| Field | Owner |
|-------|-------|
| `type`, `alias`, `title`, `authors`, `isbn`, `updated_at` | `BookStorageService` |
| `readwise_id`, `num_highlights`, `last_highlight_at` | `ReadwiseService` |
| `hardcover_id`, `status`, `rating`, `started_at`, `finished_at` | `HardcoverSyncService` |
| All `##` sections except `## Highlights` | User (preserved verbatim) |
| `## Highlights` content | `ReadwiseService` (append-only) |

---

## Frontmatter schema

```yaml
---
type: book
alias: the-beginning-of-infinity-david-deutsch   # stable slug, immutable after creation
title: The Beginning of Infinity
authors:
  - David Deutsch
isbn: "9780713992748"                             # quoted; omitted if unknown
hardcover_id: 12345                               # omitted if not linked
readwise_id: 67890                                # omitted if not linked
status: read                                      # want_to_read | reading | read | paused | dnf
rating: 4.5
started_at: 2024-01-15
finished_at: 2024-03-20
num_highlights: 42
last_highlight_at: 2024-03-18T10:30:00.000Z
updated_at: 2024-03-20T08:00:00.000Z
---
```

Optional fields are omitted (not written as `null`) until populated by their owning system.

---

## Identity and reconciliation

`alias` is the stable in-file identity anchor, generated once at creation from `slugify(title)` (disambiguated with author slug or numeric suffix if needed). It is **immutable after creation**.

When any import source brings in a book, `BookStorageService.reconcile()` checks for an existing file in this priority order before creating a new one:

1. `hardcover_id` — exact integer match
2. `readwise_id` — exact integer match
3. `isbn` — normalized (hyphens stripped, lowercase)
4. `slugify(title)` — title slug equality

If a match is found but the arriving source's ID is absent from the matched file, it is patched in immediately to cement the link. This is how a Readwise-imported book and a Hardcover-synced book converge on the same file without creating a duplicate.

---

## Migration from legacy format

Files with `type: book_highlights` (pre-consolidation Readwise schema) are **lazily migrated** on first load by `BookStorageService.loadBooks()`: type renamed, `source: readwise` removed, `author: string` split into `authors: [list]`, `alias` generated in-place. The body is preserved unchanged.

---

## `BookStorageService` (`lib/features/books/services/book_storage_service.dart`)

All-static. The only service that creates or reads canonical book files.

| Method | Description |
|--------|-------------|
| `loadBooks(vaultPath)` | Load all book files; lazy-migrate legacy files |
| `reconcile(vaultPath, {hardcoverId, readwiseId, isbn, title})` | Find existing file by any anchor in priority order |
| `patchFields(filePath, updates)` | Overwrite only specified frontmatter keys; preserve body |
| `createBook(vaultPath, book)` | Create new canonical file; return path |
| `generateAlias(title, authors, {existing})` | Collision-safe alias generation |

`patchFields` is the minimal-patch primitive. Both `ReadwiseService` and `HardcoverSyncService` call it to write only their owned fields without disturbing the other's data.

---

## `HardcoverService` (`lib/features/books/services/hardcover_service.dart`)

All-static, all-catch-null, never throws. GraphQL client for the Hardcover API.

- **Endpoint**: `https://api.hardcover.app/v1/graphql`
- **Auth**: `Authorization: Bearer {token}`
- **Token key**: `hardcover_api_token` (SharedPreferences)

| Method | What it does | On failure |
|--------|-------------|------------|
| `getToken()` / `setToken()` / `clearToken()` | SharedPreferences token management | — |
| `testConnection(token)` | `query { me { id } }` — returns `String?` (null = ok) | Returns error description |
| `fetchUserBooks(token)` | Full user library: `user_books` with book title, contributors, status, rating, dates | Returns `(null, errorString)` |
| `searchBooks(token, query)` | Title search via `_ilike` on `books` table, limit 10 | Returns `null` |
| `updateUserBook(token, userBookId, statusId, rating)` | Push status/rating back to Hardcover | Returns `false` |
| `insertUserBook(token, bookId, statusId)` | Add book to user's Hardcover library | Returns `null` |

`fetchUserBooks` uses `_graphqlDebug` (propagates the error string); all other methods use `_graphql` (silent null on failure).

### `HardcoverBook` model (`lib/features/books/models/hardcover_book.dart`)

| Field | Source |
|-------|--------|
| `userBookId` | `user_books.id` — used in mutations |
| `bookId` | `book.id` — Hardcover's canonical book ID, used as local identity anchor |
| `title`, `authors` | `book.title`, `book.cached_contributors` (scalar JSON) |
| `statusId` | `user_books.status_id` (1–5); `statusSlug` getter converts to string |
| `rating` | `user_books.rating` (`double?`) |
| `firstStartedReadingDate`, `lastReadDate` | `user_books` date fields |

### Hardcover API schema quirks (do not regress)

These were discovered through runtime failures:

- **`me` is a `List`**, not a single object. Parse as `(data['me'] as List?)?.first`.
- **`cached_contributors` is `json!` (scalar)**, not a nested GraphQL type. Do NOT subselect `{ author { name } }` — query it bare and cast the decoded value to `List<dynamic>` in Dart.
- **`isbn_13` does not exist on the `books` type**. ISBN is on `editions`, not `books`. Do not add it to any query against `books`.

### Status ID mapping

| ID | Slug |
|----|------|
| 1 | `want_to_read` |
| 2 | `reading` |
| 3 | `read` |
| 4 | `paused` |
| 5 | `dnf` |

---

## `HardcoverSyncService` (`lib/features/books/services/hardcover_sync_service.dart`)

Bidirectional sync. Explicit only — no background polling. Single entry point: `sync()`.

```
sync() →
  Fetch all user_books from Hardcover API
  Load all local book files (with lazy migration)
  Build lookup: hardcover_id → local Book

  Pass 1: Hardcover → Markdown
    For each HC book:
      - Find local match (hardcover_id lookup → title-slug fallback)
      - No match: createBook() with HC metadata → importedFromHardcover++
      - Match: patchFields() with HC-owned fields only
          - First time linking (no prior hardcover_id) → linkedToHardcover++
          - Already linked → updatedFromHardcover++

  Pass 2: Markdown → Hardcover
    Reload local books (picks up hardcover_ids written in pass 1)
    For each local book with hardcover_id:
      - Compare status + rating against HC record
      - Changed: updateUserBook() → pushedToHardcover++
      - Unchanged: skipped++

  Return HardcoverSyncResult
```

`HardcoverSyncResult` counters: `importedFromHardcover`, `updatedFromHardcover`, `linkedToHardcover`, `pushedToHardcover`, `skipped`, `error`.

---

## Readwise coexistence

`ReadwiseService` calls through `BookStorageService` exclusively: `reconcile()` to find or create the file, `patchFields()` for its owned fields only, and `_appendHighlights()` to append new `^rw{id}` blocks to `## Highlights`. It never touches Hardcover-owned fields, and vice versa. User sections are preserved by both.

---

## `HardcoverScreen` (`lib/features/books/screens/hardcover_screen.dart`)

Middle tab in the `HomeScreen` bottom navigation bar (Entities | **Hardcover** | ToDos).

- Lists all books in `Interesting/Books/` with status chips, rating, and HC/RW source badges
- AppBar sync button (in `HomeScreen`) calls `HardcoverScreenState.sync()`
- Search FAB (in `HomeScreen`) calls `HardcoverScreenState.openSearchSheet()` — opens a bottom sheet to search Hardcover by title, pick a reading status, and add the book to both the vault and the user's Hardcover library

---

## Boundaries (do not violate)

- `BookStorageService` is the only service that creates or reads canonical book files
- Each service patches only its owned fields — never overwrite fields owned by another service
- No auto-sync, no background polling
- Books stay in `Interesting/Books/` — do not merge into `Interesting/Entities/`
- `alias` is immutable after creation — never regenerate
- `## Highlights` is append-only — never delete or reorder existing highlight blocks
- `^rw{id}` block IDs are the Readwise deduplication mechanism — do not change format
- **Author–entity linking (future)**: when ready, extend the `GetMyBooks` query to include `contributions { author { id, name } }` for stable Hardcover author IDs, add `author_entity_aliases` to book frontmatter, and cross-reference against `Entity` objects in the People category. Nothing in the current model blocks this.
