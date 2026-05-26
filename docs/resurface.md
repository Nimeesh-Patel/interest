# Resurface Subsystem

## Purpose

Vault-wide semantic resurfacing viewer. Scans notes across the broader vault for `***` horizontal-rule separators and projects them into lightweight front/back pairs — surfacing problem-situation structures already latent in the user's notes, without modifying them.

This is a **read-only semantic projection**. The vault is never modified.

---

## Architectural role

The resurfacing viewer sits at the read-only projection end of the architecture: it discovers structure already encoded in notes, rather than imposing structure from outside.

```
vault notes (unchanged)
  → ResurfaceService.scan()       — recursive read + separator extraction
  → List<ResurfaceCard>           — in-memory projection, shuffled
  → ResurfaceScreen               — viewer UI; discarded on close
```

Nothing about the session is written to the vault or to SharedPreferences.

---

## Ontology

A `ResurfaceCard` is a transient view derived from a single note at read time. It has no identity anchor and is not stored or indexed.

| Field | Value |
|---|---|
| `sourcePath` | Absolute path to the source file |
| `sourceFile` | Basename of the source file (e.g. `epistemology.md`) |
| `front` | Content above the first `***` separator, trimmed |
| `back` | Content below the first `***` separator, trimmed |

---

## Separator detection

**Trigger:** a line matching `^\*{3,}\s*$` — three or more asterisks, optional trailing whitespace, nothing else on the line.

**Only the first matching separator is used.** If a note contains multiple `***` lines, extraction stops at the first one.

**Code-fence exclusion:** the scanner tracks code fence state. Any line whose left-trimmed content starts with ` ``` ` toggles `inCodeFence`. A `***` line inside a code fence is not treated as a separator.

**Empty-block guard:** if either `front` or `back` is empty after trimming, no card is produced. A `***` at the very start of the body (empty front) or at the very end (empty back) is silently skipped.

**YAML frontmatter:** `splitFrontmatter()` strips the YAML block before scanning. A `---` delimiter in the frontmatter is invisible to the extractor. `***` is used — not `---` — to avoid visual ambiguity with frontmatter delimiters when authoring.

**Exception handling:** any file that cannot be read, or whose content causes a parse error, is silently skipped. `ResurfaceService` never throws.

---

## Vault scan scope

`ResurfaceService.scan()` calls `Directory(vaultPath).list(recursive: true)` and processes every `.md` file found.

**Excluded folders:** any file whose relative path contains a segment matching an excluded folder name is skipped. Matching is exact and segment-based — the full path is split on the OS separator, the filename (last segment) is dropped, and each remaining segment is checked against the exclusion list.

Default excluded folders: `Interesting`, `.obsidian`, `Templates`, `Attachments`.

- `Interesting` is excluded because it contains the app's structured semantic objects (entities, books, Anki cards) — schema-driven files with YAML frontmatter and semantic sections that are not the raw epistemic material the resurfacing viewer is designed for.
- `.obsidian` and `Templates` and `Attachments` are excluded because they contain configuration, templates, and binary assets rather than notes.

**Changing the exclusion list:** Settings → Resurface. Stored in `Interesting/System/integrations.md` under `## Resurface → excluded_folders:` via `IntegrationsConfigService`. The default list is used if the section is absent or empty.

---

## ResurfaceService API

```dart
class ResurfaceService {
  static Future<List<ResurfaceCard>> scan(
    String vaultPath, {
    List<String> excludedFolders = _defaultExcludedFolders,
  }) async
}
```

`scan()` is the only public method. It returns all `ResurfaceCard` projections found across the vault, in filesystem iteration order (the caller is responsible for shuffling). Returns an empty list on any top-level I/O error; never throws.

`_extractFrontBack()` is private. It takes a file path and raw file content and returns a `ResurfaceCard?`. Returns `null` on any of: no separator found, empty front, empty back, any exception during parsing.

---

## ResurfaceScreen behaviour

### Load

On `initState`, the screen calls `VaultService.getVaultPath()` then `IntegrationsConfigService.load()` to read the excluded folders, then `ResurfaceService.scan()`. The resulting card list is shuffled in memory before display. The shuffle is not seeded — order is random each session.

### States

| Condition | Displayed |
|---|---|
| Vault path not configured | `EmptyState` with error message |
| Scan complete, zero cards | `EmptyState` with hint to add a `***` separator |
| Scan in progress | `CircularProgressIndicator` |
| Cards loaded | Viewer (see below) |

### Viewer layout

- **AppBar**: title "Resurface"; counter `N / total` in the trailing position (hidden while loading or when no cards).
- **Source title**: the filename without extension, rendered as an H1 heading above the front content.
- **Front**: always visible once a card is displayed. Rendered via `MarkdownBody`.
- **Back**: hidden on initial display. A centred italic "tap to reveal" hint appears in its place. Tap anywhere on the screen to reveal the back. Tapping again hides it.
- **Divider**: a 1px horizontal rule appears between front and back when the back is revealed.
- **Navigation**: prev/next `IconButton`s at the bottom. Prev is disabled at index 0; next is disabled at the last card. Swipe left (velocity < −200) advances; swipe right (velocity > +200) retreats. Navigation resets `_backRevealed` to `false`.

### Session state

The screen holds: `_cards` (shuffled list), `_currentIndex`, `_backRevealed`, `_loading`, `_error`. All state is session-only. Closing the screen discards it entirely.

### Markdown rendering

All content — source title, front, back — is rendered via `flutter_markdown`'s `MarkdownBody` with explicit heading sizes (H1: 26px bold; H2: 19px semi-bold; H3: 16px semi-bold; body: 15px). The back uses `Colors.grey.shade800` as the text colour; the front and title use the theme's `onSurface` colour.

---

## What is not implemented

- No scheduler, no review intervals, no due dates, no FSRS.
- No review history. The session is stateless; which cards were seen is not recorded anywhere.
- No mutation of vault files. The vault is opened read-only.
- No card authoring. There is no UI for creating or editing notes from within this screen.
- No ordering beyond the in-session shuffle. The shuffle is not persisted.
- No per-card actions (mark known, snooze, rate). The only interactions are tap-to-reveal and prev/next navigation.

---

## Boundaries (do not violate)

- `ResurfaceService` must never write to any file.
- `_extractFrontBack` must return `null` rather than throw on any malformed input.
- The separator pattern `^\*{3,}\s*$` must not be silently expanded to match `---` or `___`.
- Folder exclusion is segment-exact: `Interesting` must not match `interesting-notes` or similar.
- Card order must not be persisted between sessions.
