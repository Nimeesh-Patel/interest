# Entity Tracker

A filesystem-native semantic knowledge layer: all data lives as plain Markdown files in a user-chosen vault folder. The app is a projection over that vault — it reads, patches, and navigates Markdown without owning it. Compatible with Obsidian; readable by any text editor. Single-user Android app. No database, no cloud, no auth.

**The central design bet:** Markdown is the database. A parallel SQLite or JSON store would create dual-truth — when they diverge (and they always do eventually), there is no canonical answer. Eliminating the second store eliminates the divergence problem entirely.

## Vault layout

```
<vault>/
  Interesting/
    Entities/     — one .md file per entity
    Boards/       — one .md file per board (wikilink list of members)
    Templates/    — category templates; seeded on first launch; user-editable
    Anki/         — one .md file per Anki card
      .trash/     — soft-deleted cards
    Tasks/        — one .md file per task topic; pure Markdown, no frontmatter
```

All subdirectories are created on first launch. All other files in the vault are ignored.

## Semantic storage model

### Identity

Every entity has an immutable `alias` in its YAML frontmatter — the entity's stable id, used in all EntityLinks and board memberships. Filenames change on rename; the alias never does. Without this invariant, every rename would silently orphan all wikilinks and board memberships pointing to the renamed entity.

### The patch-not-rebuild contract

When the app saves an entity, it **patches** the existing file — it does not rebuild it from scratch. Patching means:
- Frontmatter is rebuilt from current entity data
- App-owned semantic sections are rewritten from current entity data
- Every other `##` section the user wrote is preserved character-for-character

If the app rebuilt the whole file from entity data, it would silently erase any prose the user had written outside the app's semantic sections on every save. The patch contract makes the app a safe cohabitant of the user's Markdown.

New entities: a category template is instantiated once at creation (`{{title}}` → name), then patched on every subsequent save. Re-templating is never done — it would destroy user sections.

### Semantic sections

The app owns three sections, defined in `_semanticSections` in `markdown_storage_service.dart`:

```dart
const Map<String, SectionType> _semanticSections = {
  'Why Interesting': SectionType.list,
  'Related':         SectionType.wikilinks,
  'Sources':         SectionType.list,
};
```

Only these are rewritten on save. Any other `##` section is user territory.

Wikilinks (`[[EntityName]]`) are scanned from the **entire Markdown body** — not just `## Related`. A link in any prose section creates the same graph edge as one in `## Related`. `## Related` is the curated list written back on save; links in other sections are preserved verbatim and still wire the graph.

### AppData and save semantics

```dart
typedef AppData = ({
  List<Entity> entities,
  List<Category> categories,
  List<String> tags,
  List<EntityLink> entityLinks,
  List<Board> boards,
  List<BoardEntity> boardEntities,
});
```

Loaded once at startup. Mutated in-place. `saveData()` fired after every mutation. Core entity fields (name, category, tags, score, notes, links) are not auto-saved during editing — save is deferred to the explicit Save button. This is required for Cancel to be atomic: Cancel restores from a pre-edit snapshot; any auto-save during editing would make the pre-edit state unrecoverable.

Join-table mutations (board memberships, entity links) save immediately because they mutate shared lists the entity snapshot does not cover.

### Entity file format

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

### Board and template file formats

```markdown
# Flat Hierarchy Solution

- [[David Deutsch]]
- [[Browser]]
- [[Untidiness]]
```

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

Five templates are seeded on first launch (`default`, `person`, `product`, `idea`, `movie`). Users can edit, delete, or create templates from within the app. `{{title}}` is the only supported placeholder.

## Architecture

```
lib/
  main.dart                — permission gate + routing
  core/                    — vault path (SharedPreferences) + directory bootstrap
  shared/markdown/         — pure Markdown parsing (md_utils) + filesystem I/O (md_io)
  shared/widgets/          — 6 reusable UI primitives
  features/
    entities/              — core storage (MarkdownStorageService), Entity, EntityScreen
    boards/                — Board model, BoardDetailScreen (membership derived at load time)
    tasks/                 — TaskBlock tree, TaskStorageService (no frontmatter, hard-delete)
    anki/                  — AnkiCard, three services (connect/storage/sync), two screens
    templates/, settings/  — self-contained, no MarkdownStorageService dependency
  screens/home_screen.dart — BottomNavigationBar shell (owns state for all three tabs)
```

`lib/shared/markdown/md_utils.dart` is the single location for all Markdown parsing logic — frontmatter splitting, section parsing, wikilink extraction, slugify, sanitizeFilename, timestamp helpers. Services and screens import from there; they never reimplement parsing inline.

## Subsystems

**Entities + graph.** Each entity is a node in a semantic graph. Categories are not stored separately — they are derived from distinct `category` frontmatter values at load time. Board membership lives in the board's `.md` file as a wikilink list, not in entity frontmatter. This localizes mutations: changing a board's membership requires rewriting only the board file, not every member entity.

**Tasks.** Task files are ephemeral working lists, not knowledge nodes. They have no `alias` and cannot participate in the entity graph. Deletion is hard (no trash) because there is no identity to preserve. The in-memory `TaskBlock` tree is a parsed projection; Markdown files remain canonical. `parseNodes()` is pure and stateless — it must be called on freshly loaded lines, never cached across reloads. Full details: [docs/tasks.md](docs/tasks.md).

**Anki.** The one bidirectional integration. Markdown owns semantic content (front/back/text, tags, deck); Anki owns review scheduling (intervals, ease, due dates — never written to Markdown). `anki_id` is the immutable identity anchor, analogous to entity `alias`. Deletion is soft (`.trash/`) because a hard-deleted card re-synced would be recreated from Anki with a new `anki_id`, breaking the identity chain permanently. Full details: [docs/anki.md](docs/anki.md).

**Letterboxd.** Ingestion-only: RSS → Movie entities written directly to `Interesting/Entities/`, bypassing `saveData()`. The bypass is intentional — `saveData()` rebuilds semantic sections from the in-memory entity model, which doesn't include `## Thoughts` at import time; routing through `saveData()` would erase the imported review content immediately after writing it.

**Grokipedia.** Read-only projection: the app searches for an article matching the entity name and displays it inline. Nothing is written to the vault. All network calls are all-catch-null; any failure degrades gracefully to "No article found."

**Android widget.** A native Android Activity (no Flutter engine at runtime). It reads the vault path directly from `FlutterSharedPreferences` using the `flutter.vault_path` key — the prefix Flutter's shared_preferences plugin uses — because VaultService and all Flutter APIs are unavailable outside the Flutter engine. Always writes `category: Default`.

**Obsidian launch ergonomics.** A single AppBar action (`Icons.sync` in `home_screen.dart`) that launches the Obsidian app via `launchUrl(Uri.parse('obsidian://'), mode: LaunchMode.externalApplication)`. Purpose: Obsidian Sync only activates when Obsidian is foregrounded; this eliminates the manual switch after editing. The app itself remains sync-agnostic — it fires the URI and returns. Snackbar on failure (app not installed). No sync logic, no background launch, no state monitoring.

## Running

```
flutter pub get
flutter run -d android
```

First launch shows a vault folder picker. Select any folder (e.g. your Obsidian vault root). The app creates all `Interesting/` subdirectories and seeds five default templates.

**Android:** Requires "All Files Access" (`MANAGE_EXTERNAL_STORAGE`) on Android 11+. A permission gate screen appears on first launch; the gate re-checks on every app resume.

## Dependencies

- `path_provider` — app documents dir (JSON migration check)
- `file_picker` — vault folder picker (first launch)
- `yaml` — YAML frontmatter parsing
- `shared_preferences` — vault path and settings persistence
- `path` — cross-platform path manipulation
- `permission_handler` — Android All Files Access gate
- `http` — Letterboxd RSS, AnkiConnect, Grokipedia (user-triggered or non-blocking; no background polling)
- `xml` — RSS/XML parsing (Letterboxd)
- `url_launcher` — opens Grokipedia article URLs in external browser; launches Obsidian via `obsidian://` URI scheme
