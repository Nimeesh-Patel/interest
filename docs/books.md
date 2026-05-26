# Books Subsystem

## Purpose

Model books as canonical Markdown objects that multiple independent systems can enrich without conflict. Readwise owns highlights. Hardcover owns reading state. ReadEra owns a separate highlight section. The user owns all other prose. None of them own the file — `BookStorageService` does.

## Architectural role

Books are **convergence objects**. The same `.md` file is the integration point for data arriving from multiple sources on different schedules. No source needs to know about the others. Field ownership strictly partitions the file into non-overlapping territories. The Markdown file is the integration bus.

This model is the correct response to the problem: "multiple enrichment sources need to enrich the same document without clobbering each other." The alternative — keeping sources in separate files and merging on display — creates a hidden database problem (where is the canonical state?). The convergence model keeps Markdown canonical.

## Ontology

- **Book**: a Markdown file in `Interesting/Books/` with `type: book`. It is the canonical record. External system IDs (`hardcover_id`, `readwise_id`) and user prose coexist in the same file.
- **Field ownership**: each field belongs to exactly one system. Writing a field you don't own corrupts state silently. The ownership table is the invariant.
- **`patchFields()`**: the minimal-patch primitive. Writes only specified frontmatter keys; leaves everything else untouched. All enrichment writes call this.
- **Reconciliation**: before creating a new file, check for an existing one by `hardcover_id → readwise_id → isbn → title slug`. This prevents duplicates when the same book arrives from multiple sources.

## Non-goals

- Books do not participate in the entity graph (no `alias`-based wikilinks yet; not `type: entity`).
- `BookStorageService` does not arbitrate between conflicting field values from different sources. If Hardcover and Readwise both claim authorship of a field, that is a schema design error — fix field ownership, not the service.

---

Books are **canonical semantic objects** — Markdown files in `Interesting/Books/` that serve as convergence points for multiple external systems (Readwise highlights, Hardcover reading states, ReadEra highlights) and local user prose. No external system owns the file; each enriches the same Markdown object independently.

---

## Field ownership

Only the owning system overwrites a field. This prevents enrichment sources from clobbering each other.

| Field | Owner |
|-------|-------|
| `type`, `alias`, `title`, `authors`, `isbn`, `updated_at` | `BookStorageService` |
| `readwise_id`, `num_highlights`, `last_highlight_at` | `ReadwiseService` |
| `hardcover_id`, `status`, `rating`, `started_at`, `finished_at` | `HardcoverSyncService` |
| `## Highlights` content | `ReadwiseService` (append-only, `^rw{id}` dedup) |
| `## Highlights (ReadEra)` content | `ReaderaIngestionService` (append-only, `^re{uuid}` dedup) |
| All other `##` sections | User (preserved verbatim) |

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

When any import source brings in a book, `BookStorageService.reconcile()` checks for an existing file before creating a new one:

```
Priority: hardcover_id → readwise_id → isbn (normalized) → slugify(title)
```

If a match is found but the arriving source's ID is absent from the matched file, it is patched in immediately to cement the link. This is how a Readwise-imported book and a Hardcover-synced book converge on the same file without creating a duplicate. ReadEra uses title-slug matching only (no external ID system).

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
| `appendReaderaHighlights(filePath, highlights)` | Append ReadEra highlights to `## Highlights (ReadEra)` section |
| `generateAlias(title, authors, {existing})` | Collision-safe alias generation |

`patchFields` is the minimal-patch primitive. All enrichment services call it to write only their owned fields without disturbing others. `appendReaderaHighlights` is the section-aware append primitive for ReadEra; the analogous Readwise primitive is `ReadwiseService._appendHighlights()` (private, co-located with its service).

---

## `HardcoverService` (`lib/features/books/services/hardcover_service.dart`)

All-static, all-catch-null, never throws. GraphQL client for the Hardcover API.

- **Endpoint**: `https://api.hardcover.app/v1/graphql`
- **Auth**: `Authorization: Bearer {token}`
- **Token**: in `integrations.md` via `IntegrationsConfigService`

| Method | What it does | On failure |
|--------|-------------|------------|
| `getToken(vaultPath)` / `setToken(vaultPath, token)` | integrations.md token management | — |
| `testConnection(token)` | `query { me { id } }` — returns `String?` (null = ok) | Returns error description |
| `fetchUserBooks(token)` | Full user library via GraphQL | Returns `(null, errorString)` |
| `searchBooks(token, query)` | Title search, limit 10 | Returns `null` |
| `updateUserBook(token, userBookId, statusId, rating)` | Push status/rating to Hardcover | Returns `false` |
| `insertUserBook(token, bookId, statusId)` | Add book to user's Hardcover library | Returns `null` |

### `HardcoverBook` model (`lib/features/books/models/hardcover_book.dart`)

| Field | Source |
|-------|--------|
| `userBookId` | `user_books.id` — used in mutations |
| `bookId` | `book.id` — Hardcover's canonical book ID |
| `title`, `authors` | `book.title`, `book.cached_contributors` (scalar JSON) |
| `statusId` | `user_books.status_id` (1–5); `statusSlug` getter maps to string |
| `rating` | `user_books.rating` (`double?`) |
| `firstStartedReadingDate`, `lastReadDate` | `user_books` date fields |

### Hardcover API schema quirks (do not regress)

- **`me` is a `List`**, not a single object. Parse as `(data['me'] as List?)?.first`.
- **`cached_contributors` is `json!` (scalar)**. Do NOT subselect `{ author { name } }` — query it bare and cast the decoded value to `List<dynamic>`.
- **`isbn_13` does not exist on the `books` type**. ISBN is on `editions`. Do not add it to any query against `books`.

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

## `HardcoverScreen` (`lib/features/books/screens/hardcover_screen.dart`)

Middle tab in the `HomeScreen` bottom navigation bar (Entities | **Hardcover** | ToDos).

- Lists all books in `Interesting/Books/` with status chips, rating, and HC/RW source badges
- AppBar sync button (in `HomeScreen`) calls `HardcoverScreenState.sync()`
- Search FAB (in `HomeScreen`) calls `HardcoverScreenState.openSearchSheet()` — opens a bottom sheet to search Hardcover by title, pick a reading status, and add the book to both the vault and the user's Hardcover library

---

## Enrichment source coexistence

Each enrichment source calls through `BookStorageService` exclusively and patches only its owned fields:

- **Readwise**: `reconcile()` → find/create file → `patchFields({readwise_id, num_highlights, last_highlight_at})` → append `^rw{id}` blocks to `## Highlights`
- **Hardcover**: `reconcile()` → find/create file → `patchFields({hardcover_id, status, rating, started_at, finished_at})`
- **ReadEra**: `reconcile(title)` → find/create file → `appendReaderaHighlights()` → `patchFields({updated_at})`

No source touches another source's fields. User sections are preserved by all. Full ReadEra details: [docs/readera.md](readera.md).

---

## Boundaries (do not violate)

- `BookStorageService` is the only service that creates or reads canonical book files
- Each service patches only its owned fields — never overwrite fields owned by another service
- No auto-sync, no background polling
- Books stay in `Interesting/Books/` — do not merge into `Interesting/Entities/`
- `alias` is immutable after creation — never regenerate
- `## Highlights` is append-only — never delete or reorder existing `^rw{id}` blocks
- `## Highlights (ReadEra)` is append-only — never delete or reorder existing `^re{uuid}` blocks
- `^rw{id}` and `^re{uuid}` block ID formats are fixed deduplication mechanisms — do not change
