# Entities subsystem

## Purpose

The entity subsystem is the core semantic graph of the vault. It models named things the user finds meaningful — people, ideas, products, concepts, films — as nodes in a graph, with edges derived from wikilinks. The primary semantic questions this subsystem answers: what exists, how things relate, and what is interesting about them.

## Architectural role

Entities are the canonical semantic objects of the `Interesting/` namespace. All other subsystems (Lists, Anki cards, Books) are adjacent or enrichment layers; entities are the center of gravity. The entity graph is an **inferred graph** — edges are not stored, they are derived from wikilink scans on every load.

## Ontology

- **Entity**: a named epistemic node. Has an `alias` (immutable identity), a `category` (free-form grouping), optional `tags`, an optional `score`, and three app-owned semantic sections (`Why Interesting`, `Related`, `Sources`).
- **Category**: not a stored object — derived at load time from distinct `category` values across all entity files. There is no category table.
- **EntityLink**: a directed graph edge inferred from `[[wikilink]]` syntax anywhere in the entity body. Not stored; rebuilt on every load.
- **Tag**: a flat label, stored as a YAML list in frontmatter. Tags are aggregated into a global tag list at load time.

## Non-goals

- Entities are not tasks. They have no completion state, no due dates.
- Entities are not books. Books have a separate schema and write path.
- The entity graph is not a general-purpose knowledge base with typed relations. All edges are untyped wikilinks; semantic typing lives in the user's prose.

---

Core subsystem. Entities live in `Interesting/Entities/` as `.md` files. The in-memory model is a parsed projection over those files. `MarkdownStorageService` is the single I/O layer. For architectural invariants (immutable alias, patch-not-rebuild, semantic sections, full-body wikilink scan) see [CLAUDE.md](../CLAUDE.md).

---

## File formats

### Entity file — `Interesting/Entities/<filename>.md`

```markdown
---
alias: david-deutsch
category: People
score: 10.0
tags:
  - epistemology
  - physics
created_at: 2026-05-07T12:00:00.000Z
updated_at: 2026-05-07T12:00:00.000Z
---
# David Deutsch

## Why Interesting

- Developed constructor theory and extended Popperian epistemology.

## Related

- [[Karl Popper]]
- [[Alan Turing]]

## Sources

- https://en.wikipedia.org/wiki/David_Deutsch

## Background

Any section the user adds here is preserved verbatim on every save.
```

**Frontmatter fields:**

| Field | Required | Notes |
|-------|----------|-------|
| `alias` | Yes | Immutable identity anchor; slugified from name at creation; never regenerated |
| `category` | Yes | Free-form string; categories derived at load time from distinct values across all entities |
| `score` | No | Float 0.0–10.0 |
| `tags` | No | YAML list |
| `created_at` | Yes | ISO 8601 UTC; set once at creation |
| `updated_at` | Yes | ISO 8601 UTC; stamped on every `_save()` in `entity_screen.dart` |
| `watched_date` | No | Movie-specific |
| `letterboxd_url` | No | Movie-specific |
| `tmdb_id` | No | Movie-specific |

Adding a new category-specific field requires updating both `_parseEntityFile` and `_buildFrontmatter` in `markdown_storage_service.dart`.

### Template file — `Interesting/Templates/<name>.md`

```markdown
---
category: Default
template: true
---
# {{title}}

## Why Interesting

## Related

## Sources
```

Five templates seeded on first launch: `default`, `person`, `product`, `idea`, `movie`. Template is instantiated once at entity creation (`{{title}}` → name). Never re-applied on subsequent saves — re-templating would destroy user sections.

---

## In-memory model

Four lists load on startup and stay in memory:

| List | Derived from |
|------|-------------|
| `entities` | `Interesting/Entities/*.md` frontmatter + body |
| `categories` | distinct `entity.category` values across all entities |
| `tags` | all entity tag values, deduplicated |
| `entityLinks` | `extractWikilinks(body)` over all entity files (full-body scan) |

`saveData()` snapshots all four lists before the async gap to prevent partial-save races.

---

## MarkdownStorageService (`lib/features/entities/services/markdown_storage_service.dart`)

All-static service. The sole I/O layer for entities.

**Public methods:**

| Method | Description |
|--------|-------------|
| `loadData()` | Scans `Interesting/Entities/`; returns all four lists |
| `saveData(...)` | Writes entity files; snapshots all lists before the async gap |
| `sortEntities(entities, sortOrder)` | All entity list sorting routes through here — never sort inline |
| `linkExists(from, to, links)` | Checks for an existing entity link in either direction |
| `generateLinkId(from, to)` | Deterministic, direction-independent link ID |
| `getRelatedEntities(id, links, entities)` | Traverses link graph for related nodes |

**Internal:**

| Method | Role |
|--------|------|
| `_parseEntityFile(file)` | Parses frontmatter + body into `Entity`; runs full-body wikilink scan |
| `_patchEntityContent(file, entity)` | Patches file in-place (CLAUDE.md invariant 3) |
| `_buildFrontmatter(entity)` | Builds YAML frontmatter string including movie-specific fields |
| `_semanticSections` | `const Map` — the app/user section boundary (CLAUDE.md invariant 4) |

**Sort routing rule:** All entity list sort dropdowns must call `sortEntities(entities, sortOrder)`. New sort option: add a `case` to `sortEntities` first, then add a `DropdownMenuItem` in the screen. Entity pickers (not sort dropdowns) may sort A→Z inline.

---

## EntityScreen (`lib/features/entities/screens/entity_screen.dart`)

### Display / edit mode

`_isEditMode` boolean (default `false`). Display mode is the default — data rendered read-only. Edit mode toggled via AppBar button. Save / Cancel buttons appear in AppBar only during edit mode.

### Snapshot and rollback

`_enterEditMode()` deep-copies `_entity` into `_snapshot`. `_cancelEdit()` restores `_entity` from `_snapshot` atomically — no file I/O on cancel. This makes Save deferred and Cancel lossless (CLAUDE.md § Save semantics).

`_save()` calls `saveData()` and stamps `updated_at`. `_saveEdit()` calls `_save()` and exits edit mode.

### Inline edit auto-save

Notes and links can be edited inline within edit mode. Both save on `onSubmitted` and `onTapOutside`. These inline commits mutate the in-memory `_entity` but do **not** call `_save()` — the full disk write is still deferred to the Save button.

### EntityLink mutations (immediate save)

Entity links (`_createEntityLink`, `_deleteEntityLink`) call `_save()` immediately — they mutate shared link state that the snapshot does not cover.

### Modals

- `_showLinkSearch()` — `showModalBottomSheet` with `isScrollControlled: true` + `MediaQuery.viewInsets.bottom` outer padding; height `screenHeight * 0.55`; searchable entity list

### Grokipedia section

External knowledge panel (display mode only). State (`_grokArticle`, `_grokSearched`, `_grokSummaryExpanded`, `_grokSummaryFetching`, `_grokFetchedSummary`) lives entirely in `_EntityScreenState` — never written to the vault.

---

## Boundaries (do not violate)

- `alias` is never regenerated after creation — see CLAUDE.md invariant 2
- Files are always patched, never rebuilt from scratch — see CLAUDE.md invariant 3
- Only `_semanticSections` keys are rewritten on save — see CLAUDE.md invariant 4
- `extractWikilinks(body)` scans the full Markdown body — see CLAUDE.md invariant 5
- All entity list sorting routes through `MarkdownStorageService.sortEntities()` — never inline-sort a list that has a sort dropdown
- Adding category-specific fields: update both `_parseEntityFile` and `_buildFrontmatter`
