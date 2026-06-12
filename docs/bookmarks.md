# Bookmarks Subsystem

## Purpose

X bookmark ingestion via Android's share sheet. When the user shares a tweet URL from the X app, the app fetches tweet metadata and writes one plain Markdown file to the vault root. Bookmarks are ordinary vault notes — they are not indexed, synced, or managed by the app after creation.

---

## Ingestion pipeline

```
Android share intent (ACTION_SEND / text/plain)
  → MainActivity.kt               — extracts URL; passes to Flutter via MethodChannel
  → HomeScreen._ingestShareUrl()  — drives the two-phase flow
      → XBookmarkService.fetchMetadata()   — validate URL + fetch tweet text
      → showInputDialog()                  — "Save bookmark" / "Skip" dialog
      → XBookmarkStorageService.save()     — write vault file
```

**`XBookmarkService.fetchMetadata(tweetUrl)`** returns a Dart record `(String? error, XBookmarkFetchResult? result)`:

1. Validates that the URL's host is `x.com`, `twitter.com`, `www.x.com`, or `www.twitter.com`. Any other host → `('Not a valid X link', null)`.
2. Extracts the tweet ID via `/status/(\d+)` and screen name via `/([^/]+)/status/\d+`. No ID match → `('Not a valid X link', null)`.
3. Four-step fetch pipeline (each step with an 8-second timeout):

**Step 1 — nitter** (tried first; up to 3 hardcoded instances sequentially: `nitter.net`, `nitter.privacydev.net`, `nitter.poast.org`)
`GET https://<instance>/<screenName>/status/<tweetId>`
On HTTP 200: regex-extracts the `.tweet-content.media-body` div, strips HTML and entity-decodes, applies `_cleanBody`. Also tries to extract the author display name from `.fullname`; falls back to `screenName`. Sets `truncated = false`. Returns on first instance that yields non-empty text.

**Step 2 — syndication API** `GET https://cdn.syndication.twimg.com/tweet-result?id=<tweetId>`
Reached only if all nitter instances fail. On HTTP 200 with a valid `text` and `user` object: uses `text` (after `_cleanBody`) as `tweetText`, `user.name` as `authorName`, constructs `authorUrl` as `https://twitter.com/<user.screen_name>`. Sets `truncated = false`.

**Step 3 — oEmbed fallback** `GET https://publish.twitter.com/oembed?url=<encoded>&omit_script=true`
Reached only if Step 2 fails. On HTTP 200: parses `author_name`, `author_url`, `url` (→ `sourceUrl`), and `html` (HTML-stripped, entity-decoded, then `_cleanBody` applied → `tweetText`). Sets `truncated = true`.

**Step 4 — all failed**
Returns a degraded `XBookmarkFetchResult` with all metadata null. Sets `truncated = true`. The write still proceeds; the resulting file contains only `alias`, `date`, and `truncated` in frontmatter and no body.

`_cleanBody` strips the oEmbed-style attribution tail (`— Author (@handle) Month Day, Year`) from the end of any fetched text and trims trailing whitespace.

`XBookmarkService` never throws. All failures are absorbed; degraded data is preferred over an error.

---

## Filename resolution

After `fetchMetadata` succeeds, `HomeScreen._ingestShareUrl` shows a dialog:

- **Title**: "Save bookmark"
- **Input**: optional text field ("Note name (optional)")
- **Buttons**: Save / Skip

**If the user provides a name**: that name is the base.

**If the user skips** (or submits empty): the first seven whitespace-separated words of `tweetText` are joined with spaces. If `tweetText` is null (degraded case), falls back to `x-<tweetId>`.

The base is then passed to `XBookmarkStorageService.uniqueSlug(base, dirPath)`, which **slugifies it** (lowercase, spaces → hyphens, non-alphanumerics stripped, via `generateUniqueId`/`slugify` in `md_utils.dart`) and guarantees no existing file is overwritten (see [§ Dedup](#dedup)). So "Popper on Falsification" becomes `popper-on-falsification.md`.

---

## Vault note format

Files are written to `<vault>/<name>.md` (vault root).

**Frontmatter fields** (in declaration order):

| Field | Value | Omitted when |
|---|---|---|
| `alias` | name (user-chosen or auto-generated, with spaces) | never |
| `author` | author display name | fetch failed |
| `author_url` | author profile URL | fetch failed |
| `source_url` | canonical tweet URL | fetch failed |
| `date` | UTC date at write time, `YYYY-MM-DD` | never |
| `truncated` | `true` — text may be incomplete | nitter or syndication succeeded |

`buildFrontmatterBlock()` from `md_utils.dart` handles all YAML quoting. Fields with null or empty values are omitted entirely.

**Body**: the note uses a `***` Resurface separator. The front side (above `***`) is left empty for the user to fill as a problem statement. The back side contains the tweet text and attribution. Note: because `splitFrontBack()` requires non-empty content on *both* sides, a bookmark is **not** a problem note (and does not appear in the deck list or sync to AnkiDroid) until the user writes a front side. Until then it is reachable like any other vault note — via search, Recent Notes, and backlinks.

```
<empty front side>

***

<tweetText>

— [<author_name>](<author_url>) · [source](<source_url>)
```

The attribution line is omitted if `authorName` is null. The `author_url` and `source_url` parts degrade gracefully: if `authorUrl` is null, the author name is written as plain text; if `sourceUrl` is null, `source` is written as plain text. Degraded notes (no `tweetText`) have no `***` separator and will not appear in Resurface until the user adds content.

**Example** — user shared `https://x.com/QuotePopper/status/2059645404581417036` and named the note "Popper on falsification" (slugified to `popper-on-falsification`):

```markdown
---
alias: popper-on-falsification
author: Karl Popper Quotes
author_url: "https://twitter.com/QuotePopper"
source_url: "https://x.com/QuotePopper/status/2059645404581417036"
date: 2026-05-27
---

***

The criterion of the scientific status of a theory is its falsifiability, or refutability, or testability.

— [Karl Popper Quotes](https://twitter.com/QuotePopper) · [source](https://x.com/QuotePopper/status/2059645404581417036)
```

**Degraded example** — same URL, all APIs unavailable:

```markdown
---
alias: popper-on-falsification
date: 2026-05-27
truncated: true
---
```

---

## Dedup

`XBookmarkStorageService.uniqueSlug(base, dirPath)` slugifies `base` and checks the filesystem synchronously before write:

- If `<slug>.md` does not exist → returns the slug unchanged.
- If it does exist → tries `<slug>-2.md`, `<slug>-3.md`, … until a free slot is found.

The returned slug is then used as both the filename and the `alias` frontmatter value. Two bookmarks saved with the same name produce `slug.md` and `slug-2.md` with distinct `alias` values — no file is ever overwritten.

`XBookmarkStorageService.save()` also checks `File(filePath).exists()` before writing as a final guard.

---

## What is not implemented

- No `BookmarksScreen`. Bookmarks are plain vault files; there is no list, detail view, or deletion UI for them within the app — they are reached via note search/Recent Notes or edited in Obsidian.
- No sync scheduler. Ingestion is user-triggered via the share sheet; nothing polls or re-fetches.
- A bookmark does not surface as a review card on its own: its `***` separator has an empty front side, and the card extractor requires content on both sides. Writing a problem statement above the `***` promotes it to a problem note.

---

## Boundaries (do not violate)

- `XBookmarkStorageService` writes only to the vault root (`VaultService.bookmarksPath(vaultPath)`). It must never write outside this path.
- `XBookmarkService.fetchMetadata` must never throw. Degraded result preferred over exception.
- Four fetch steps are permitted: nitter (3 instances) → syndication → oEmbed → degraded. Do not add further fallbacks or scrapers.
- Do not add scheduling, sync history, deck assignment, or any persistent card state to this subsystem.
