# Entities subsystem

## Purpose

An **entity is a plain Markdown note that belongs to a collection.** The subsystem answers two questions: *what collections exist and who belongs to them*, and *how do notes relate* (backlinks). It does not own note content — the body is the user's territory, edited as Markdown.

This is the evolved model. The original "entity is a structured document with `Why Interesting` / `Related` / `Sources` sections" view was retired in June 2026; enforcing a body shape both corrupted notes and added no value once entities became collection members. **No body structure is imposed at all** — a new note is created with frontmatter only and an empty body (not even an `# Name`).

The user-facing screen is called **Collections** (tab 2). Internally the in-memory model for a collection member is still `Entity`; "entity" and "collection member" are the same thing. A Collection here is the Interest-app analogue of an Anki **Deck** — but an app-first concept, independent of (and orthogonal to) the `category:`/deck a Problem Note uses for AnkiDroid.

## Ontology

- **Entity**: any vault note whose frontmatter has a `collection:` key. Carries `collection` (grouping), optional `tags`, optional `score`, and a `sourcePath`. Its `id` is the `alias:` value if present, else the filename slug. Its `name` is the filename. Nothing else is required — not even timestamps.
- **Collection**: not a stored object — derived at load time from the distinct `collection:` values across all entity notes. There is no collection table, and none is invented (no default "People").
- **Backlinks**: connections are not a stored graph. Forward `[[wikilinks]]` render as tappable links in the body; incoming links are listed live by the shared `BacklinksSection` (`ResurfaceService.getBacklinks`). Read-only — links are made by writing `[[wikilinks]]` in the body.
- **Tag**: a flat label stored as a YAML list in frontmatter.

## Orthogonality (important)

Entity-ness and Problem-Note-ness are independent axes:

| | predicate | what it grants |
|---|---|---|
| **Entity** | `collection:` in frontmatter | collection membership + backlinks |
| **Problem Note** | `***` in body | AnkiDroid sync (deck = `category:`, default `Default`) |

A note can be **both** (a `collection:` note that also has a `***` front/back). Because the app patches only frontmatter and never the body, saving such a note as an entity preserves its `***` content. `alias` and `category` are orthogonal to entity-ness.

## Non-goals

- Entities are not tasks, books, or articles — those have separate schemas and write paths.
- The graph is not typed; all edges are untyped wikilinks. Semantic typing lives in the user's prose.

---

## Entity discovery (do not loosen)

A vault `.md` file is an entity **iff its frontmatter contains `collection:`** — encoded once in `EntityFileParser.isEntityFrontmatter()` and used by every scan in `MarkdownStorageService`.

WHY `collection`, not `category`/`alias`: `category:` is a Problem-Note property (the AnkiDroid deck). In June 2026 entity discovery keyed on `category:` (alone, then briefly `category:`+`alias:`); problem notes carry `category:`, so they were loaded as entities and the bulk save rewrote them in entity format — destroying body, `***`, and idea text (signature: `alias`/`created_at`/`updated_at` added, `up:`/`anki_note_id:` dropped, body reduced to a lone `# Title`). `collection:` is owned solely by the entity layer, so it cannot collide with problem notes, bookmarks, books, or articles.

**Diagnostics:** `EntityFileParser.isCorruptedHusk()` and `MarkdownStorageService.findCorruptedNotes(vaultPath)` (plus a `kDebugMode` log on every `loadData`) report notes matching the old corruption signature. Detection only — they never restore or rewrite. A legitimately empty note is indistinguishable from a husk, so treat matches as candidates.

---

## File format

Entity files live in the vault root alongside other notes. The `Interesting/Entities/` directory is no longer created.

### Entity note — vault root `<filename>.md`

```markdown
---
collection: People
score: 9.0
tags:
  - epistemology
---
# David Deutsch

Anything the user wants: prose, [[Karl Popper]] wikilinks, their own
`##` headings, even a `***` front/back if this is also a problem note.
The app never rewrites this body.
```

**App-owned frontmatter keys** (`EntityFileWriter._knownOrder`): `collection`, `alias`, `tags`, `score`. Only `collection` is always written (`tags`/`score` when set); **every other key is preserved untouched** (`created_at`/`updated_at` if the user keeps them, `category`/deck, `anki_note_id`, `up`, user-defined keys). The app neither requires nor writes timestamps.

| Field | Required | Notes |
|-------|----------|-------|
| `collection` | Yes | The discriminator + grouping; collections derived from distinct values |
| `alias` | No | Stable `id` if present; legacy/optional. Not regenerated |
| `score` | No | Float 0.0–10.0 |
| `tags` | No | YAML list |
| `created_at` / `updated_at` | No | Optional; preserved if present, never written by the app. Used in-memory (defaulted to load time) only for date sorts |

---

## In-memory model

Three lists load on startup (`MarkdownStorageService.loadData`):

| List | Derived from |
|------|-------------|
| `entities` | vault `.md` files with `collection:` (frontmatter only; body read on demand) |
| `collections` | distinct `entity.collection` values |
| `tags` | all entity tag values, deduplicated |

There is no in-memory link/graph list — incoming links are fetched live by `BacklinksSection`.

---

## MarkdownStorageService (`lib/features/entities/services/markdown_storage_service.dart`)

The sole I/O layer for entities. Writes are **per-file** — there is no bulk save.

| Method | Description |
|--------|-------------|
| `loadData()` | Vault-wide scan (excl. `.obsidian`, `Templates`); entity iff frontmatter has `collection:`; returns the four lists |
| `saveEntity(entity)` | Creates the file if `sourcePath` is null (**only `collection:` frontmatter**, empty body — no `# Name`, no timestamps), else patches that file's frontmatter in place; body preserved. Sets `sourcePath` |
| `deleteEntity(entity)` | Deletes the one backing file |
| `renameCollection(members, newName)` | Patches each member file's `collection:` value |
| `sortEntities(entities, sortOrder)` | All entity sorting routes through here |
| `findCorruptedNotes(vaultPath)` | Diagnostic; lists June-2026 husk candidates |

`EntityFileParser.parseEntityFile` (frontmatter + full-body wikilink scan → `Entity`) and `EntityFileWriter.patchFrontmatter` / `buildNewEntity` (frontmatter-only, body-preserving) are pure string transforms; the service does the I/O.

---

## EntityScreen (`lib/features/entities/screens/entity_screen.dart`)

A note **viewer** built on the shared note-view primitives. Display mode renders: the title (filename), collection, tags, score, the note **body** via `noteMarkdownBody` (tappable `[[wikilinks]]`), `BacklinksSection` (what links here), and the Grokipedia panel. The AppBar offers **Open in Obsidian** (`obsidianUri` + `launchUrl`), **Edit note body**, and **Edit details**.

- **Edit details** (`tune` icon) → frontmatter-only edit mode (collection dropdown, tags, score). `Save` → `storage.saveEntity(_entity)`; `Cancel` restores the in-memory snapshot.
- **Edit note body** (`notes` icon) → pushes `NoteEditScreen(filePath: sourcePath)`; on return the body is re-read. This is the only way the body changes.
- **Grokipedia** state lives entirely in `_EntityScreenState` — never written to the vault.

The name (filename) is not edited here; renaming a note is a file-rename concern outside this screen.

---

## Boundaries (do not violate)

- Discovery keys on `collection:` only — see CLAUDE.md invariant 2.
- The app patches frontmatter, never the body — see CLAUDE.md invariant 3. No code path rewrites an entity body.
- Problem Note (`***`) and Entity (`collection:`) are orthogonal — see CLAUDE.md invariant 4. Never gate one predicate on the other.
- `extractWikilinks(body)` scans the full body — see CLAUDE.md invariant 5.
- All entity list sorting routes through `MarkdownStorageService.sortEntities()`.
- Preserve unknown frontmatter keys on save — only `EntityFileWriter._knownOrder` keys are app-owned.
