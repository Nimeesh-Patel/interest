# Interest

Interest is an Android app that syncs Obsidian notes to AnkiDroid as flashcards — phone to phone, no desktop Anki, no plugin syntax inside your notes — and adds a traversal layer for revisiting the open problems in your vault. It exists because plain Markdown files are the durable artifact and apps are not: the vault is the database, Interest is a disposable projection over it, and if the app disappears tomorrow your notes are exactly what you wrote.

## The Problem Note

One Obsidian note = one Anki card. To make any note a card, add a `***` line: problem above, current best answer below.

```markdown
What makes Interest a better Obsidian-to-Anki bridge than the existing plugins?

***

It creates one Anki card per note by reading a single `***`
separator — no plugin syntax, no ID comments, no code added
to your note. The file stays an ordinary, readable Markdown
note that works on its own, with or without Anki.
```

That is the entire format. No special fields, no ID comments, no code blocks injected into the note. It stays an ordinary Markdown file — fully readable and editable in Obsidian, useful on its own even if Anki never enters the picture. Optionally, a `category:` frontmatter key picks the AnkiDroid deck and `tags:` become Anki tags; neither is required.

The framing is deliberate: the front is a problem situation, the back is your current best conjecture, and **both sides are expected to keep evolving**. This is not a Q/A flashcard you write once; it is a thinking artifact that happens to be drillable. You edit it in Obsidian whenever your thinking moves, and the next sync updates the card in place.

## Why not the existing plugins

The community Obsidian↔Anki bridges generally need special syntax inside notes (ID comments, custom blocks, regex-matched patterns), a desktop Anki instance running AnkiConnect, or both. Interest reads the vault directly from disk on the phone and pushes cards through AnkiDroid's ContentProvider API. No laptop in the loop, no markers in your prose.

**The sync is one-way: vault → AnkiDroid.** The Markdown files are always the source of truth. AnkiDroid never writes into the vault; review history, intervals, and FSRS state stay on Anki's side and Interest never sees them. The single thing written back to a note is an `anki_note_id` frontmatter key, so re-syncs update the existing card instead of duplicating it. This is structural, not a configuration option — no code path in the sync touches a note body, so it cannot alter what you wrote.

Honestly, what you give up: one note is one card, so you cannot generate several cards from one file the way the extraction plugins can. Cards use AnkiDroid's Basic model only — no cloze, no media. Sync is a manual tap, not a background job. And Interest is a personal project, Android-only, built from source, with no onboarding — the conventions live in `docs/`, not in the UI.

## The three-system model

| System | Owns |
|---|---|
| **Obsidian** | Editing. The vault's Markdown files are the only canonical data. |
| **Interest** | Traversal. Resurfacing problem notes, graph-weighted ordering, backlinks, search. |
| **AnkiDroid** | Retention. FSRS scheduling and drilling, fed by the one-way push. |

Deep links stitch the three together. Every synced card's front carries an `obsidian://` link to its source note, so mid-review you are one tap from editing. `[[wikilinks]]` inside a card render as tappable links: if the target is itself a synced card, the link opens it inside AnkiDroid's own browser (AnkiDroid ≥ 2.16); otherwise it fires `interest://note/...`, which opens the note in Interest's reader. Drilling a card, jumping sideways into a linked idea, and landing in the editor are each one tap apart.

## What else it does

Interest's own review queue tracks traversal, not memory: opening a problem note boosts the scores of its wikilink neighbours, boosts decay over time, and plain notes within a configurable hop range of a reviewed problem get activated into the queue alongside it — revisiting one problem drags its conceptual neighbourhood back into view. All of that state lives in one Markdown file (`Interesting/System/review_log.md`), readable in Obsidian like everything else. Backlinks are computed live from full-body wikilink scans — there is no stored graph to corrupt. A `collection:` frontmatter key groups notes into browsable collections, and a `deck:` key filters the card viewer; both are plain YAML you could have written by hand.

## Import pipelines

Side features, mentioned for completeness rather than novelty. Book data from Readwise (highlights), Hardcover (reading state), and ReadEra (e-reader highlights) converges on one Markdown file per book; each source owns a fixed set of frontmatter keys and appends under its own dedup anchors, so no source can overwrite another's data. RSS feeds (Substack, Letterboxd, generic) import as article notes. Sharing an X post to the app saves it as a vault note — this leans on third-party mirrors and degrades often. A home-screen widget does quick capture straight into the vault.

## Running it

You need Flutter and an Android device. There are no published releases; build from source:

```
flutter pub get
flutter run -d android
```

First launch asks for "All Files Access" (the vault is read straight from disk) and a vault folder — point it at an Obsidian vault or any folder of Markdown files. Interest keeps its own structured data inside an `Interesting/` subtree; everything outside it is yours and is only ever frontmatter-patched, never rebuilt. It is still a personal project writing into your vault: try it on a copy first.

For the Anki bridge: install AnkiDroid, add `***` to a note, tap AnkiDroid in the Sources screen.

## Architecture in brief

Flutter, `setState` only. Storage is a set of all-static services that never throw, each owning exactly one vault directory; pure Markdown/YAML utilities live in `lib/shared/markdown/md_utils.dart`. The two invariants that matter: a note's roles are orthogonal frontmatter/body facts (`collection:` makes it a collection member, `***` makes it a card — a note can be both), and the app patches frontmatter but never note bodies, so no operation can destroy prose. Subsystem detail: [docs/](docs/) — [AnkiDroid sync](docs/ankidroid.md), [resurfacing & scoring](docs/resurface.md), [entities & collections](docs/entities.md), [books](docs/books.md), [projects](docs/projects.md), [bookmarks](docs/bookmarks.md), [UI](docs/ui.md). `CLAUDE.md` is the constraint registry used when working on the code with AI assistance.

## License

[MIT](LICENSE)
