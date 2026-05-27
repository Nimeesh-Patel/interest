# Bookmarks Subsystem

## Purpose

X bookmark ingestion via Android's share sheet. When the user shares a tweet URL from the X app, the app fetches tweet metadata via the Twitter oEmbed API and writes one plain Markdown file to `Interesting/Bookmarks/`. Bookmarks are ordinary vault notes — they are not indexed, synced, or managed by the app after creation.

---

## Ingestion pipeline

```
Android share intent (ACTION_SEND / text/plain)
  → MainActivity.kt               — extracts URL; passes to Flutter via MethodChannel
  → HomeScreen._ingestShareUrl()  — drives the two-phase flow
      → XBookmarkService.fetchMetadata()   — validate URL + fetch oEmbed
      → showInputDialog()                  — "Save bookmark" / "Skip" dialog
      → XBookmarkStorageService.save()     — write vault file
```

**`XBookmarkService.fetchMetadata(tweetUrl)`** returns a Dart record `(String? error, XBookmarkFetchResult? result)`:

1. Validates that the URL's host is `x.com`, `twitter.com`, `www.x.com`, or `www.twitter.com`. Any other host → `('Not a valid X link', null)`.
2. Extracts the tweet ID via `/status/(\d+)`. No match → `('Not a valid X link', null)`.
3. Fetches `https://publish.twitter.com/oembed?url=<encoded>&omit_script=true` with an 8-second timeout.
4. On HTTP 200: parses `author_name`, `author_url`, `url` (→ `sourceUrl`), and `html` (HTML-stripped and entity-decoded → `tweetText`).

**If oEmbed fails** (network unavailable, non-200, timeout, parse error): returns `(null, XBookmarkFetchResult(tweetId, tweetUrl))` — a degraded result with all metadata fields null. The write still proceeds; the resulting file contains only `alias` and `date` in frontmatter and no body.

`XBookmarkService` never throws. All failures are absorbed; degraded data is preferred over an error.

---

## Filename resolution

After `fetchMetadata` succeeds, `HomeScreen._ingestShareUrl` shows a dialog:

- **Title**: "Save bookmark"
- **Input**: optional text field ("Note name (optional)")
- **Buttons**: Save / Skip

**If the user provides a name**: the name is passed through `slugify()` from `md_utils.dart` — lowercase, spaces to hyphens, non-alphanumeric characters stripped.

**If the user skips** (or submits empty): the first seven whitespace-separated words of `tweetText` are joined and slugified. If `tweetText` is null (degraded case), falls back to `x-<tweetId>`.

The resulting base slug is then passed to `XBookmarkStorageService.uniqueSlug(base, dirPath)` to guarantee no existing file is overwritten (see [§ Dedup](#dedup)).

---

## Vault note format

Files are written to `Interesting/Bookmarks/<slug>.md`.

**Frontmatter fields** (in declaration order):

| Field | Value | Omitted when |
|---|---|---|
| `alias` | slug (user-chosen or auto-generated) | never |
| `author` | oEmbed `author_name` | oEmbed unavailable |
| `author_url` | oEmbed `author_url` | oEmbed unavailable |
| `source_url` | oEmbed `url` (canonical tweet URL) | oEmbed unavailable |
| `date` | UTC date at write time, `YYYY-MM-DD` | never |

`buildFrontmatterBlock()` from `md_utils.dart` handles all YAML quoting. Fields with null or empty values are omitted entirely.

**Body**: tweet text followed by an attribution line.

```
<tweetText>

— [<author_name>](<author_url>) · [source](<source_url>)
```

The attribution line is omitted if `authorName` is null. The `author_url` and `source_url` parts degrade gracefully: if `authorUrl` is null, the author name is written as plain text; if `sourceUrl` is null, `source` is written as plain text.

**Example** — user shared `https://x.com/QuotePopper/status/2059645404581417036` and named the note "popper on falsification":

```markdown
---
alias: popper-on-falsification
author: Karl Popper Quotes
author_url: "https://twitter.com/QuotePopper"
source_url: "https://twitter.com/QuotePopper/status/2059645404581417036"
date: 2026-05-27
---
The criterion of the scientific status of a theory is its falsifiability, or refutability, or testability.

— [Karl Popper Quotes](https://twitter.com/QuotePopper) · [source](https://twitter.com/QuotePopper/status/2059645404581417036)
```

**Degraded example** — same URL, oEmbed unavailable:

```markdown
---
alias: popper-on-falsification
date: 2026-05-27
---
```

---

## Dedup

`XBookmarkStorageService.uniqueSlug(base, dirPath)` checks the filesystem synchronously before write:

- If `<base>.md` does not exist → returns `base` unchanged.
- If it does exist → tries `<base>-2.md`, `<base>-3.md`, … until a free slot is found.

The returned slug is then used as both the filename and the `alias` frontmatter value. This means two bookmarks saved with the same user-chosen name produce `name.md` and `name-2.md` with distinct `alias` values — no file is ever overwritten.

`XBookmarkStorageService.save()` also checks `File(filePath).exists()` before writing as a final guard.

---

## What is not implemented

- No `BookmarksScreen`. Bookmarks are plain vault files; there is no list, search, or detail view for them within the app.
- No sync scheduler. Ingestion is user-triggered via the share sheet; nothing polls or re-fetches.
- No deletion UI. Bookmarks are deleted by editing the vault directly.
- No `BookmarksScreen` tab or navigation entry.
- Bookmarks do not appear in the Notes/Resurface tab unless the user manually adds a `***` separator to the file — the Resurface scanner only surfaces notes that contain the separator.

---

## Boundaries (do not violate)

- `XBookmarkStorageService` writes only to `Interesting/Bookmarks/`. It must never write outside this directory.
- `XBookmarkService.fetchMetadata` must never throw. Degraded result preferred over exception.
- The oEmbed endpoint (`publish.twitter.com/oembed`) is the only network call in this subsystem. Do not add fallback scrapers or alternative APIs.
- Do not add scheduling, sync history, deck assignment, or any persistent card state to this subsystem.
