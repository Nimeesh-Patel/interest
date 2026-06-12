# Interest

Interest is an Android app that sits on top of an Obsidian vault and keeps your open problems in circulation. It resurfaces unresolved questions, lets you walk the wikilink neighbourhood around them, and pushes the ones worth drilling into AnkiDroid — without ever owning your notes.

## The problem

Obsidian is good at capturing ideas; Anki is good at retaining facts. Neither keeps a *problem* alive. A note about an unresolved question doesn't come back to you in Obsidian unless you go looking for it. Anki brings cards back on schedule, but as isolated question/answer pairs, cut off from the web of notes that gave them meaning — and most Obsidian→Anki bridges treat cards as one-time exports that drift from their source.

Interest is built around a different unit: the **Problem Note**. It is any Markdown file containing a `***` separator. Above the separator is a problem situation or open question; below is the current best conjecture. Both sides are expected to keep evolving — it is a thinking artifact that happens to be syncable as a flashcard, not a flashcard.

## How it works

Three systems, each owning one thing:

| System | Owns |
|---|---|
| **Obsidian** | Editing. The vault's Markdown files are the only canonical data. |
| **Interest** | Traversal. Resurfacing problem notes, graph-weighted ordering, backlinks, search. |
| **AnkiDroid** | Retention. FSRS scheduling and drilling, fed by a one-way push from the vault. |

The vault is the database. Interest persists nothing outside it except the vault path; everything else — notes, review log, integration config — is plain Markdown you can read and edit in Obsidian. Interest patches only the frontmatter keys it owns and never rewrites a note body.

Resurfacing works on traversal, not memory scheduling: opening a problem note boosts the scores of its wikilink neighbours, boosts decay over time, and plain notes that sit within a configurable hop range of a reviewed problem get "activated" into the queue alongside it. The intent is that revisiting one problem drags its conceptual neighbourhood back into view. All of this state lives in one Markdown file (`Interesting/System/review_log.md`).

The AnkiDroid sync is one-way (vault → AnkiDroid) via AnkiDroid's ContentProvider API. The only thing ever written back to a note is its `anki_note_id`. Synced cards keep their context: each card's front carries an `obsidian://` link to the source note, and `[[wikilinks]]` inside a card become deep links — to the linked card inside AnkiDroid's browser when the target is itself synced, otherwise back into Interest (`interest://note/...`), which resolves and opens the note. Review history, intervals, and scheduling stay in AnkiDroid; Interest never sees them, by design.

## What it looks like

*(Screenshots not yet added — placeholders below.)*

> Deck list with problem-note counts · card viewer (problem above, conjecture revealed on tap) · a note's backlinks panel · a synced card in AnkiDroid with its Obsidian link.

## Trying it

You need Flutter and an Android device or emulator. There are no published releases; build from source:

```
flutter pub get
flutter run -d android
```

First launch asks for "All Files Access" (the vault is read directly from disk) and then for a vault folder — point it at an Obsidian vault, or any folder of Markdown files. Interest creates an `Interesting/` subtree inside the vault for its own structured data (books, articles, projects, system files); everything outside that tree is treated as yours and only ever patched, never rebuilt. Still: this is a personal project that writes into your vault, so try it on a copy or a test vault first.

To use the Anki bridge, install AnkiDroid, give any note a `***` separator (and optionally a `category:` frontmatter key to pick the deck), then tap AnkiDroid in the Sources screen.

## Honest limitations

This was built for one person's vault and it shows in places. It is Android-only. There is no onboarding; conventions like `***`, `deck:`, and `category:` are documented in `docs/` rather than discovered in the UI. The X/Twitter bookmark capture (share-sheet → vault note) depends on third-party mirrors and degrades often. The internal package name is still `people_tracker` from an earlier life. Several side subsystems — book enrichment from Readwise/Hardcover/ReadEra, RSS ingestion, lightweight projects — work but are incidental to the core idea, and the test suite covers only the Markdown-parsing core.

## Architecture in brief

Flutter, `setState` only, no state-management framework. Storage is a set of all-static services that never throw, each owning exactly one vault directory; pure Markdown/YAML utilities live in `lib/shared/markdown/md_utils.dart`. Two invariants matter most: an entity (collection member) is any note with a `collection:` frontmatter key, a problem note is any note with `***` in its body, and the two are orthogonal — a note can be both; and the app patches frontmatter but never note bodies, so no app operation can destroy prose. There is no stored graph: backlinks and graph scores are computed live from full-body wikilink scans.

Subsystem detail is in [docs/](docs/) — [resurfacing & scoring](docs/resurface.md), [AnkiDroid sync](docs/ankidroid.md), [entities & collections](docs/entities.md), [books](docs/books.md), [projects](docs/projects.md), [bookmarks](docs/bookmarks.md), [UI system](docs/ui.md). `CLAUDE.md` is the constraint registry used when working on the code with AI assistance.

## License

[MIT](LICENSE)
