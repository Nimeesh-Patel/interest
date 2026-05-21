# Books Subsystem

Books are **canonical semantic objects** — Markdown files in `Interesting/Books/` that serve as convergence points for multiple external systems (Readwise highlights, Hardcover reading states) and local user prose. Each file is owned by neither external system; both enrich the same Markdown object.

---

## Ontology

A book file is the single source of truth for a semantic book. Multiple enrichment systems patch it; none owns it.

**Field ownership** — only the owning system overwrites a field:

| Field | Owner |
|-------|-------|
| `type`, `alias`, `title`, `authors`, `isbn`, `updated_at` | `BookStorageService` |
| `readwise_id`, `num_highlights`, `last_highlight_at` | `ReadwiseService` |
| `hardcover_id`, `status`, `rating`, `started_at`, `finished_at` | `HardcoverSyncService` |
| All `##` sections except `## Highlights` | User (preserved verbatim) |
| `## Highlights` content | `ReadwiseService` (append-only) |

---

## Frontmatter Schema

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

## Identity and Reconciliation

`alias` is the stable in-file identity anchor, generated once at creation from `slugify(title)` (disambiguated with author slug or numeric suffix if needed). It is **immutable after creation**.

When any import source brings in a book, `BookStorageService.reconcile()` checks for an existing file in this priority order before creating a new one:

1. `hardcover_id` — exact integer match
2. `readwise_id` — exact integer match
3. `isbn` — normalized (hyphens stripped, lowercase) — reachable only if `isbn` was set manually or by a future source; Hardcover API does not expose ISBN on the `books` type
4. `slugify(title)` — title slug equality

If a match is found but the arriving source's ID is absent from the matched file, it is patched in immediately to cement the link.

---

## Migration from Legacy Format

Files with `type: book_highlights` (the pre-consolidation Readwise schema) are **lazily migrated** on first load by `BookStorageService.loadBooks()`:

- `type: book_highlights` → `type: book`
- `source: readwise` field removed
- `author: string` → `authors: [list]` (split on `, `)
- `alias` generated and written in-place

The body (highlights, user sections) is preserved unchanged.

---

## File Location

`Interesting/Books/<sanitized-title>.md` — one file per book.

Filename derived via `sanitizeFilename(title)`. Files are NOT loaded by `MarkdownStorageService` and do not currently participate in the entity graph. `alias` is present to enable future graph participation without a migration.

---

## `BookStorageService` (`lib/features/books/services/book_storage_service.dart`)

All-static. Owns all canonical book file I/O.

| Method | Description |
|--------|-------------|
| `loadBooks(vaultPath)` | Load all book files; lazy-migrate legacy files |
| `reconcile(vaultPath, {hardcoverId, readwiseId, isbn, title})` | Find existing file by any anchor |
| `patchFields(filePath, updates)` | Overwrite only specified frontmatter keys; preserve body |
| `createBook(vaultPath, book)` | Create new canonical file; return path |
| `generateAlias(title, authors, {existing})` | Collision-safe alias generation |

**`patchFields` is the minimal-patch primitive.** Both `ReadwiseService` and `HardcoverSyncService` call it to write only their owned fields without disturbing the other's data.

---

## `HardcoverService` (`lib/features/books/services/hardcover_service.dart`)

All-static, all-catch-null, never throws. GraphQL client for the Hardcover API.

- **Endpoint**: `https://api.hardcover.app/v1/graphql`
- **Auth**: `Authorization: Bearer {token}`
- **Token key**: `hardcover_api_token` (SharedPreferences)
- **Rate limit**: 60 req/min

| Method | Description |
|--------|-------------|
| `getToken()` / `setToken()` / `clearToken()` | SharedPreferences token management |
| `testConnection(token)` | `query { me { id } }` — returns `String?` (null = success, error description on failure) |
| `fetchUserBooks(token)` | Returns `(List<HardcoverBook>?, String?)` — error string propagated to sync result |
| `searchBooks(token, query)` | Title search via `books(where: {title: {_ilike: $query}})` |
| `updateUserBook(token, userBookId, statusId, rating)` | Push status/rating mutation |
| `insertUserBook(token, bookId, statusId)` | Add book to Hardcover library |

### GraphQL operations

**Connectivity check** (`testConnection`)
```graphql
query { me { id } }
```

**Fetch user library** (`fetchUserBooks`) — response shape: `data.me[0].user_books[*]`
```graphql
query GetMyBooks {
  me {
    user_books {
      id
      status_id
      rating
      date_added
      first_started_reading_date
      last_read_date
      book {
        id
        title
        cached_contributors
      }
    }
  }
}
```

**Search books by title** (`searchBooks`) — response shape: `data.books[*]`
```graphql
query SearchBooks($query: String!) {
  books(where: {title: {_ilike: $query}}, limit: 10) {
    id
    title
    cached_contributors
  }
}
```
`searchBooks` returns bare `book` objects, not `user_book` wrappers. `fromJson` is called with a synthetic wrapper (`id: 0, status_id: 1, ...`) to reuse the same parser.

**Update reading state** (`updateUserBook`) — takes `userBookId` (the `user_books.id`, not `books.id`)
```graphql
mutation UpdateUserBook($id: Int!, $statusId: Int!, $rating: numeric) {
  update_user_book(
    where: {id: {_eq: $id}},
    _set: {status_id: $statusId, rating: $rating}
  ) {
    returning { id }
  }
}
```

**Add book to library** (`insertUserBook`) — returns new `user_books.id`
```graphql
mutation InsertUserBook($bookId: Int!, $statusId: Int!) {
  insert_user_book(object: {book_id: $bookId, status_id: $statusId}) {
    id
  }
}
```

### Transport layer

Two private HTTP helpers:

| Helper | When used | On failure |
|--------|-----------|------------|
| `_graphqlDebug` | `testConnection`, `fetchUserBooks` | Returns `(null, errorString)` |
| `_graphql` | All mutations, `searchBooks` | Returns `null` (silent) |

`_graphqlDebug` captures HTTP status codes, GraphQL `errors[*].message`, and caught exceptions as a human-readable string. `_graphql` discards all failure detail — appropriate for fire-and-forget mutations.

### `HardcoverBook` model (`lib/features/books/models/hardcover_book.dart`)

| Field | Source | Type |
|-------|--------|------|
| `userBookId` | `user_books.id` | `int` — used in mutations |
| `bookId` | `book.id` | `int` — Hardcover's canonical book ID |
| `title` | `book.title` | `String` |
| `authors` | `book.cached_contributors` (scalar JSON) | `List<String>` |
| `statusId` | `user_books.status_id` | `int` (1–5) |
| `rating` | `user_books.rating` | `double?` |
| `dateAdded` | `user_books.date_added` | `String?` |
| `firstStartedReadingDate` | `user_books.first_started_reading_date` | `String?` |
| `lastReadDate` | `user_books.last_read_date` | `String?` |

`cached_contributors` is parsed defensively: tries `entry['author']['name']` first, falls back to `entry['name']`.

### Hardcover API schema quirks (do not regress)

These were discovered through runtime failures and must be preserved as invariants:

- **`me` is a `List`**, not a single object. Hasura returns user-scoped queries as arrays even for single-user contexts. Parse as `(data['me'] as List?)?.first`, not `data['me'] as Map`.
- **`cached_contributors` is `json!` (scalar)**, not a nested object type. Do NOT use subselection syntax `{ author { name } }` — query it bare and parse the decoded value as `List<dynamic>` in Dart.
- **`isbn_13` does not exist on the `books` type**. ISBN is on `editions`, not `books`. Do not add it to any query against the `books` type.

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

Bidirectional sync. Explicit only — no background polling.

### Algorithm

```
sync() →
  1. Fetch all user_books from Hardcover API
  2. Load all local book files (with lazy migration)
  3. Build lookup: hardcover_id → local Book

  Pass 1: Hardcover → Markdown
    For each HC book:
      - Find local match (by hardcover_id → title slug; ISBN not available from HC API)
      - If no match: createBook() with HC metadata → importedFromHardcover++
      - If match: patchFields() with HC-owned fields only
          - wasLinked (no prior hardcover_id) → linkedToHardcover++
          - else → updatedFromHardcover++

  Pass 2: Markdown → Hardcover
    Reload local books (to pick up hardcover_ids from pass 1)
    For each local book with hardcover_id:
      - Compare status + rating against HC record
      - If changed: updateUserBook() → pushedToHardcover++
      - Else: skipped++

  Return HardcoverSyncResult
```

### Result fields

| Field | Meaning |
|-------|---------|
| `importedFromHardcover` | New book files created from Hardcover |
| `updatedFromHardcover` | Existing files patched with HC metadata |
| `linkedToHardcover` | Files that gained a `hardcover_id` for the first time |
| `pushedToHardcover` | Local status/rating changes pushed to HC |
| `skipped` | Linked books with no state difference |

---

## Readwise Coexistence

`ReadwiseService` delegates all file I/O to `BookStorageService`:

1. `reconcile(readwiseId, title)` — find or create the canonical file
2. `patchFields({readwise_id, num_highlights, last_highlight_at, updated_at})` — write only Readwise-owned fields
3. `_appendHighlights()` — append new `^rw{id}` blocks to `## Highlights`

Readwise never touches `hardcover_id`, `status`, `rating`, `started_at`, `finished_at`. Hardcover sync never touches `readwise_id`, `num_highlights`, `last_highlight_at`, or the highlights body. User sections (`## Thoughts`, `## Notes`, any custom `##`) are preserved by both.

---

## `HardcoverScreen` (`lib/features/books/screens/hardcover_screen.dart`)

Opened from `SettingsScreen` → "Open Hardcover Screen".

- Shows all books in `Interesting/Books/` with status chips, rating, and source badges (HC / RW)
- AppBar sync button → `HardcoverSyncService.sync()` → SnackBar result
- Empty state if no token; error state with retry if vault unreadable

---

## Boundaries (do not violate)

- `BookStorageService` is the only service that creates or reads canonical book files — `ReadwiseService` and `HardcoverSyncService` call through it
- Each service patches only its owned fields — never overwrite fields owned by another service
- No auto-sync, no background polling
- Books stay in `Interesting/Books/` — do not merge into `Interesting/Entities/` until graph participation is explicitly planned
- `alias` is immutable after creation — never regenerate
- `## Highlights` is append-only — never delete or reorder existing highlight blocks
- `^rw{id}` block IDs are the Readwise deduplication mechanism — do not change format
