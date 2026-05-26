# Resurface Subsystem

## Purpose

Vault-wide semantic resurfacing viewer. Scans notes across the broader vault (outside `Interesting/`) for `***` horizontal-rule separators and projects them into lightweight front/back pairs — surfacing problem-situation structures already latent in the user's notes, without modifying them.

This is a **read-only semantic projection**. The vault is not altered in any way.

---

## Architectural Role

The resurfacing viewer sits at the read-only projection end of the architecture: it discovers structure already encoded in notes, rather than imposing structure from outside.

```
vault notes (unchanged)
  → ResurfaceService.scan()         — recursive read + separator extraction
  → List<ResurfaceCard>             — in-memory projection
  → ResurfaceScreen                 — viewer UI
```

The projection is ephemeral: it is recomputed on every open and discarded on close. Nothing about the resurfacing session is written to the vault or to SharedPreferences.

---

## Ontology

### Canonical objects: the vault notes themselves

The Markdown files in the vault are the canonical objects. The `***`-separated structure is authored content — the app merely recognizes and surfaces it.

### Derived objects: ResurfaceCard

A `ResurfaceCard` is a temporary projection derived from a single note at read time:

| Field | Meaning |
|---|---|
| `sourcePath` | Absolute path to the source note |
| `sourceFile` | Basename of the source note (shown in UI as provenance) |
| `front` | Content above the first `***` separator (trimmed) |
| `back` | Content below the first `***` separator (trimmed) |

`ResurfaceCard` has no identity anchor. It is not stored, indexed, or versioned. It is a transient view.

### The `***` separator as epistemic structure

The `***` horizontal rule is not arbitrary visual formatting. It encodes a structural relationship within a note:

```
[problem-situation / question / unresolved tension]

***

[current conjecture / partial resolution / working answer]
```

This is not question-answer formatting. It represents the natural epistemic structure of evolving notes: a problem that has been at least partially engaged with. The resurfacing system revisits these structures — asking: does the current resolution still hold? Has the situation evolved?

This distinction matters for future evolution: the system is converging toward **problem resurfacing infrastructure**, not fact memorization infrastructure.

---

## Extraction Algorithm

### Separator detection

After `splitFrontmatter()` strips the YAML block:

1. Walk the body lines.
2. Toggle `inCodeFence` on any line starting with ` ``` ` — prevents false matches inside code blocks.
3. First line matching `^\*{3,}\s*$` (three or more asterisks) that is outside a code fence = separator.
4. `front` = lines before separator, trimmed. `back` = lines after separator, trimmed.
5. Either empty → skip (no card produced).

### Why `***` not `---`

`---` is the YAML frontmatter delimiter. Even though `splitFrontmatter()` strips the YAML block before scanning, `---` in the body creates visual ambiguity when authoring notes: the author's eye may conflate the semantic separator with the YAML structure. `***` carries no such dual reading. It is visually distinct and unambiguous as a semantic separator.

### Exclusion model

`ResurfaceService.scan()` respects a configurable exclusion list (folder names, not paths). Any file whose relative path contains an excluded folder segment is skipped.

Default excluded folders: `Interesting`, `.obsidian`, `Templates`, `Attachments`.

**Why `Interesting/` is excluded by default:** `Interesting/` contains the app's structured semantic objects (entities, books, Anki cards). These are schema-driven Markdown files with YAML frontmatter and semantic sections — not the raw epistemic material the resurfacing viewer is designed for. The broader vault (journals, reading notes, working documents) is where problem-oriented `***`-separated structures naturally emerge.

Excluded folders are stored in `integrations.md` under `## Resurface` → `excluded_folders:`. User-configurable via Settings → Resurface.

---

## Invariants

- `ResurfaceService` never writes to any file.
- Only the first `***` separator in a note is used (conservative extraction).
- Code fences are tracked — `***` inside a fenced block is not treated as a separator.
- The `***` dedup key is `^\*{3,}\s*$`. Do not silently expand this to match `---` or `___`.
- Excluded folder matching is segment-based (checks each path component), not substring-based (prevents false exclusions like `interesting-notes/` matching `Interesting`).
- Cards are shuffled in memory on each open — no ordering is persisted.

---

## Non-goals

This subsystem is intentionally not:

- A spaced repetition system. No intervals, ease factors, due dates, or FSRS.
- An Anki clone. No deck management, no scheduling state, no review history.
- A card authoring workflow. Notes are not authored as flashcards — the separator structure is discovered in existing prose.
- A card database. `ResurfaceCard` has no ID, no persistent state, no indexing.
- A statistics or productivity dashboard. No streaks, counts, or gamification.

Adding any of these would shift the subsystem from **semantic projection** to **operational review machinery** — a category change that conflicts with the vault-native philosophy.

---

## Tensions and Tradeoffs

**Tension: `Interesting/` excluded by default, but some notes there may have `***` separators.**

Resolution: the exclusion list is user-configurable. The default prioritizes signal quality over completeness. A user who writes epistemic notes inside `Interesting/` can remove the exclusion.

**Tension: only first separator is used.**

A note may have multiple `***` separators encoding multiple problem-resolution pairs. Using only the first is conservative. The tradeoff: using all separators would require a multi-card-per-note model, increasing extraction complexity and potentially fragmenting notes in ways that lose context. The first pair is the primary one. This constraint is easy to relax in future.

**Tension: no review history means the viewer cannot avoid reshowing recently-seen cards.**

The shuffle provides variety but not avoidance. This is acceptable for Phase 1, where the goal is to validate the ontology (problem-oriented resurfacing) rather than optimize review efficiency. Future: vault-native review events written as Markdown could enable history without hidden state.

---

## Non-obvious implementation notes

`splitFrontmatter()` in `md_utils.dart` handles frontmatter by detecting `---` only at the file start. Notes without YAML frontmatter pass through with their full content as the body — including any `***` separators. This is correct behavior.

The code-fence toggle uses `line.trimLeft().startsWith('``\`')` to handle rare indented fence openings. The toggle is simple: any line starting with three backticks (opening or closing) flips the state. Nested fences are not supported by this model, but nested fences are not valid in standard Markdown and are not encountered in practice.

---

## Future evolution direction

Future additions should preserve the **semantic projection** architecture:

- **Vault-native review history**: reviewing a card could append a small event block to the source note (e.g., a `## Resurface history` section). This would keep review state in the vault without a hidden database.
- **FSRS or scheduling**: if added, it should be computed from vault-native review events, not stored in a separate database.
- **Multiple separators per note**: straightforward extension — extract all pairs, not just the first.

What must remain true regardless of future changes: `ResurfaceService` reads the vault and produces a projection. It does not own data. The vault remains canonical.
