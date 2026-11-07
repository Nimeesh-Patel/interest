# Interest

Interest keeps Anki in step with an Obsidian vault. Every note with a `***`
line becomes one card, and Interest keeps the cards matching the notes: it
adds what is new, updates what changed, removes duplicates, and asks before
deleting a card whose note is gone or re-creating one that is missing.

It runs on Android (AnkiDroid) and Windows (Anki desktop through AnkiConnect).
Plain Markdown is the durable artifact and the app is not: the vault is the
database, Interest is a disposable projection over it, and if the app
disappears tomorrow your notes are exactly what you wrote.

## The Problem Note

A Problem Note is any Markdown note containing a `***` separator: the problem
above, your current best conjecture below. Interest makes a card from every
such note without a `collection:` key, even when a side is still empty, since
the card front always carries the note's title link.

```markdown
What makes Interest a good Obsidian-to-Anki bridge?

***

It pushes one Anki card per note by reading a single `***`
separator: no plugin syntax, no ID comments, no code added
to your note.
```

Optionally `category:` picks the deck (Default when absent) and `tags:` become
Anki tags. Both sides keep evolving: edit the note in Obsidian and the next
sync updates the card in place. Adding `collection:` withdraws the card.

## The app

One screen says whether the vault and Anki match. Opening it previews what a
sync would change, writing nothing; the Sync button (or the Problem Notes
plugin's ribbon button, which fires `interest://sync-anki`) applies it. When
the plugin's button is tapped with a note open, only that note is synced
and Interest hands straight back to AnkiDroid, so fixing a card mid-review
costs about a second and one tap. Cards
that need a decision appear in a swipeable pager, one card per page, with the
card's deck, review history, problem and conjecture, so you can judge what
removing or re-creating it means. Settings shows the vault, the Anki target
and its permission, kept cards, the card rules, and an export of AnkiDroid's
card state for Perspirator.

## The sync

**Content projection is one-way: vault → Anki.** Markdown owns what you wrote;
Anki owns scheduling and review history. Each sync reads the whole collection
once and writes only the differences. The only thing written back to a note is
an `anki_note_id` frontmatter key, through a surgical patch; no code path
touches a note body. Templates, attachments, trash, history, the `memory/`
folder and Interest's device-local `.interest/` lock folder are never card
sources.

Cards are created, changed and deleted only from Obsidian, so Anki should
mirror the notes. A linked card that is missing is never re-created
automatically, because it may still be travelling through AnkiWeb from another
device. A card whose note is gone is never removed automatically, because the
note may not have reached this device yet. Both are offered for your
decision. Duplicates are removed automatically.

Each card's front links back to its note, and `[[wikilinks]]` in a card open
in Obsidian. One note is one card, on Anki's Basic model.

## Running it

You need Flutter and an Android device, or Windows with the Visual Studio C++
build tools. Build from source:

```
flutter pub get
flutter run -d android    # or: flutter run -d windows
```

On Android, first launch asks for All Files Access and a vault folder.
Interest creates nothing in the vault except `anki_note_id` keys and its
hidden `.interest/` lock.

`dart run tool/sync_anki_notes.dart --vault <path> --file <note.md>` syncs
chosen notes to Anki desktop from the command line.

## Architecture

Flutter, `setState` only. `lib/features/anki/` is the sync core: scanner,
renderer, transports and the snapshot-diff sync. `lib/features/sync/` is the
app: home, decision pager and settings. Detail: [the sync and deep-link
contract](docs/anki.md) and [the design system](docs/ui.md). `CLAUDE.md` is
the constraint registry for working on the code with AI assistance.

## License

[MIT](LICENSE)
