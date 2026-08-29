# Interest

Interest is a small Android (and Windows) companion to an Obsidian vault. It does four narrow things over your plain-Markdown files:

1. **Collections** — browse and tag notes grouped by a `collection:` frontmatter key.
2. **Inbox** — capture loose Markdown, including unfinished items and tangents, in one persistent `Interesting/Inbox.md` document.
3. **Projects** — a lightweight todo/project workspace.
4. **One-way Anki sync** — push your `***` "problem notes" to AnkiDroid as flashcards, triggered by a deep link from the companion **Problem Notes** Obsidian plugin.

It exists because plain Markdown files are the durable artifact and apps are not: the vault is the database, Interest is a disposable projection over it, and if the app disappears tomorrow your notes are exactly what you wrote. Vault-root note integrations only patch frontmatter; Interest owns the Markdown bodies under `Interesting/` that back Inbox and Projects.

## The Problem Note

A Problem Note is structurally any Markdown note containing a `***` separator: the situation/problem above, your current best conjecture below. Interest creates a card only when both sides are non-empty; a blank template or unfinished capture remains a Problem Note without becoming a review card yet.

```markdown
What makes Interest a good Obsidian-to-Anki bridge?

***

It pushes one Anki card per note by reading a single `***`
separator — no plugin syntax, no ID comments, no code added
to your note. The file stays an ordinary, readable Markdown
note that works on its own, with or without Anki.
```

That is the entire format. No special fields, no ID comments, no injected code. The note stays a fully readable Markdown file. Optionally a `category:` frontmatter key picks the AnkiDroid deck and `tags:` become Anki tags; neither is required.

The framing is deliberate: the front is a problem, the back is your current best conjecture, and **both sides keep evolving**. You edit it in Obsidian whenever your thinking moves, and the next sync updates the card in place.

## The companion plugin

Editing, backlinks, and tap-to-reveal review of `***` notes live in **Obsidian**. The **Problem Notes** plugin owns that review surface. Interest's Collections screen separately renders an entity note body read-only and sends its wikilinks to Obsidian; it is not a Problem Note reviewer.

The plugin and the app meet at one contract: the plugin's "sync to AnkiDroid" button fires the `interest://sync-anki` deep link. `MainActivity` (`launchMode=singleTop`) receives it — cold start through `pendingSyncAnki`, running app through `onNewIntent` — and **Interest comes to the foreground and runs the sync there**, reporting the result in a snackbar.

## The sync

**One-way: vault → Anki.** The Markdown files are always the source of truth. Anki never writes into the vault; review history, intervals, and FSRS state stay on Anki's side and Interest never sees them. The single thing written back to a note is an `anki_note_id` frontmatter key (a surgical frontmatter patch), so re-syncs update the existing card instead of duplicating it. This is structural, not a setting — **no code path in the sync touches a note body**, so it cannot alter what you wrote. Discovery refuses rollback/history, trash, templates, attachments, Basic Memory, Interest system files, unreadable scans, and duplicate active IDs before changing cards.

Two transports share one sync core and one `anki_note_id`:

- **AnkiDroid** (phone) — through AnkiDroid's ContentProvider API. No desktop Anki, no laptop in the loop, no markers in your prose. Triggered by the `interest://sync-anki` deep link.
- **AnkiConnect** (desktop) — when the vault is open in Obsidian desktop and Anki desktop is running the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on, the same one-way sync runs over HTTP with identical card semantics. Triggered manually from the Sources screen.

Each synced card's front carries an `obsidian://` link back to its source note, and `[[wikilinks]]` inside a card render as tappable `obsidian://` links — so mid-review you are one tap from the note in Obsidian.

What you give up: one note is one card (no multi-card extraction); cards use Anki's Basic model only (no cloze, no media); sync is a manual trigger, not a background job.

## The three-system model

| System | Owns |
|---|---|
| **Obsidian** (+ Problem Notes plugin) | Canonical editing, `***` review rendering, backlinks, and full wikilink traversal. The vault's Markdown files are the only canonical data. |
| **Interest** | Collections (including a read-only entity-body view), Inbox, Projects, and the one-way Anki sync engine. |
| **AnkiDroid / Anki desktop** | Retention. FSRS scheduling and drilling, fed by the one-way push. |

## Running it

You need Flutter and an Android device, or Windows with the Visual Studio C++ build tools for the desktop build. There are no published releases; build from source:

```
flutter pub get
flutter run -d android    # or: flutter run -d windows
```

First launch asks for "All Files Access" (the vault is read straight from disk) and a vault folder — point it at an Obsidian vault or any folder of Markdown files. Interest keeps its own structured data inside an `Interesting/` subtree; everything outside it is yours and is only ever frontmatter-patched, never rebuilt. It is a personal project writing into your vault: try it on a copy first.

For the Anki bridge: add `***` to a note, then either tap the Problem Notes plugin's sync button in Obsidian (AnkiDroid), or run Anki desktop with AnkiConnect and tap **Anki desktop** in the Sources screen.

## Architecture in brief

Flutter, `setState` only. Expected failures cross service boundaries as explicit results; pure Markdown/YAML utilities live in `lib/shared/markdown/md_utils.dart`. Two invariants matter: a note's roles are orthogonal frontmatter/body facts (`collection:` makes it a collection member, a non-empty `***` split makes it card-ready — a note can be both), and vault-root integrations patch frontmatter without replacing user prose. Interest body editing stays bounded to its own Inbox and Project files under `Interesting/`.

Subsystem detail: [docs/](docs/) — [Inbox and its provider](docs/inbox.md), [Anki sync & the deep-link contract](docs/anki.md), [entities & collections](docs/entities.md), [projects](docs/projects.md), [tasks parser](docs/tasks.md), [UI](docs/ui.md), [mobile UX](docs/mobile_ux.md). `CLAUDE.md` is the constraint registry used when working on the code with AI assistance.

## License

[MIT](LICENSE)
