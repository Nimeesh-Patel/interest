# Refactor Audit

Audit of the vault-native knowledge layer codebase. Records what holds up, what has drifted, and what is being fixed. Each inconsistency below has a corresponding fix tracked in the implementation plan.

---

## Strengths

**Patch-not-rebuild.** `MarkdownStorageService._patchEntityContent()` surgically rewrites only the semantic sections registered in `_semanticSections`. User prose in custom `##` blocks is never touched.

**Semantic section registry as app/user boundary.** The `_semanticSections` const is the single source of truth for which H2 sections the app owns. Any name outside it is user territory.

**Vault-native config.** Integration tokens, RSS feeds, and Resurface exclusion lists live in `integrations.md` and travel with the vault. SharedPreferences is bootstrap-only.

**Field ownership across multi-writer book files.** Readwise, Hardcover, and ReadEra each patch only their own frontmatter keys via `BookStorageService.patchFields()`. No service overwrites another's fields. Verified by inspection.

**Append-only highlight deduplication.** Readwise uses `^rw{id}` anchors; ReadEra uses `^re{uuid}` anchors. Re-import never duplicates content.

**Alias immutability enforced at save time.** `entity_screen.dart._saveEdit()` does not regenerate the alias on rename. Graph identity is stable.

**VaultService path constants.** No service hardcodes `Interesting/` string literals. All directory paths go through `VaultService` static accessors.

**Documentation accuracy.** All four major subsystem docs (`resurface.md`, `ankidroid.md`, `books.md`, `projects.md`) accurately describe their implementation. Verified by cross-reading code and docs.

---

## Invariants

These five rules define system identity. Any change that violates one changes what the system is.

1. **Markdown is the database.** No SQLite, no parallel JSON alongside `.md` files.
2. **`alias` is immutable after creation.** `entity.id == alias`; never regenerate on rename.
3. **Patch-not-rebuild.** Existing entity files always patched, never regenerated from template.
4. **Semantic section registry is the app/user boundary.** Only keys in `_semanticSections` are rewritten on save.
5. **Full-body wikilink scan.** `extractWikilinks(body)` scans the whole Markdown body, not just `## Related`.

---

## Inconsistencies

These are the issues found by the audit. Each is numbered for tracking. All are now fixed or explicitly deferred.

| # | Location | Issue | Status |
|---|---|---|---|
| 1 | `ReviewLogService._extractFrontmatter()` | Manual `---` delimiter loop duplicates `splitFrontmatter()` from md_utils | **Fixed** |
| 2 | `ReviewLogService._serialize()` | Manual StringBuffer frontmatter builder — nested YAML structure precludes `buildFrontmatterBlock()` | **Deferred (intentional)** |
| 3 | `AnkiDroidService._stripFrontmatter()` | Manual `---` stripping duplicates `splitFrontmatter().body` | **Fixed** |
| 4 | `AnkiDroidService._prepareForAnki()` | Inline wikilink-stripping regex duplicates the pattern centralised in md_utils | **Fixed** |
| 5 | `LetterboxdAdapter._buildMovieMarkdown()` | Manual StringBuffer frontmatter builder — only adapter not using `buildFrontmatterBlock()` | **Fixed** |
| 6 | `LetterboxdAdapter._updateMovieFile()` | Same manual builder used for update path | **Fixed** |
| 7 | CLAUDE.md Write paths table | Missing `TemplatesScreen`/`TemplateEditorScreen` and `ReviewLogService` rows | **Fixed** |
| 8 | CLAUDE.md subsystem blocks | `ReviewLogService` subsystem undescribed | **Fixed** |
| 9 | `WikilinkText` widget | Own `[[...]]` regex, does not handle pipe aliases | **Deferred (UI-only, by design)** |
| 10 | `test/widget_test.dart` | Empty stub — zero test coverage across entire codebase | **Partially addressed (md_utils tests added)** |

### Deferred explanations

**#2 — `ReviewLogService._serialize()` kept manual.** The review log uses nested YAML (a `settings:` map and a `reviews:` list with per-entry sub-maps). `buildFrontmatterBlock()` is a flat key→value builder and cannot express this structure. The manual serializer is correct and intentional; do not migrate it.

**#9 — `WikilinkText` regex.** The widget intentionally renders only `[[Target]]` form (no display alias) because its use context (task text) never produces piped wikilinks. Adding alias support would require changing rendering behavior, not just the regex.

---

## Not violations

These patterns look like violations on first glance but are documented and intentional.

| Pattern | Why it is correct |
|---|---|
| `LetterboxdAdapter` writes `.md` files to vault root, not `Interesting/Entities/` | Movies belong at vault root alongside user entity files; Letterboxd is a movie category. Documented in CLAUDE.md Write paths table. |
| `NoteEditScreen` writes directly to the vault file it receives | It is a raw file editor; no storage service intermediary by design. Documented in CLAUDE.md Write paths table. |
| `TemplatesScreen` / `TemplateEditorScreen` write directly | Template files are raw user-created Markdown; no structured schema to enforce. |
| `ProjectListDetailScreen` writes directly | This is the task file editor screen (`TaskFileScreen`); writes to exactly the file it was given. |
| `ReviewLogService._serialize()` uses manual YAML | Nested structure is required; `buildFrontmatterBlock()` is flat-only. |

---

## Tests gap

No tests exist. The empty `test/widget_test.dart` stub is the only test file.

**Priority areas for first tests (pure functions, no I/O, no Flutter context):**

- `md_utils.dart`: `splitFrontmatter`, `splitFrontBack`, `extractWikilinks`, `plainTextWikilinks`, `buildFrontmatterBlock`, `slugify`, `generateUniqueId`
- Storage service contracts: entity preamble preservation, rename collision no-write, service no-throw
- Field ownership: multi-writer book file simulation

First batch of tests added in this refactor: `test/md_utils_test.dart` covering all md_utils pure functions.
