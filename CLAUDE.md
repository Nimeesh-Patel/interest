Focus on creating progressively better abstractions: implementation should become more elegant and hard-to-vary over time. Encode error-correcting mechanisms into the code.

# Project

Interest is a single-purpose Anki sync console for an Obsidian vault: it keeps Anki cards matching the vault's `***` Problem Notes. Android talks to AnkiDroid; Windows talks to Anki desktop through AnkiConnect. Note viewing and editing live in Obsidian; tasks live in ClickUp; templates are a vault-wide Obsidian feature. Architectural story: [README.md](README.md). This file states constraints and their enforcement points.

## Documentation philosophy

This file is a **constraint registry**, not a narrative. Keep it precise over complete, hard-to-vary, and current. `README.md` is the story (what + why), `CLAUDE.md` the enforcement layer (do/don't + where), `docs/*.md` the subsystem detail. Don't duplicate across layers. Update `README.md` and `CLAUDE.md` when a write path, invariant, identity anchor or service standard changes.

## Traversal guide

| Task | Read first |
|------|-----------|
| Changing the sync (either transport) | [docs/anki.md](docs/anki.md), then `AnkiSyncService` and the `AnkiTransport` implementations in `lib/features/anki/` |
| Changing what counts as a card source | `AnkiProblemNoteScanner`, then `CurrentVaultContent` |
| Changing the deep link | [docs/anki.md](docs/anki.md) § deep-link contract, then `MainActivity.kt` and `HomeScreen` |
| Changing any screen, colour or type | [docs/ui.md](docs/ui.md), then `app_theme.dart` and `app_text_styles.dart` |
| Running the tests | `flutter test` from the repo root (bare `dart test` is not the entrypoint) |
| Checking native AnkiDroid behaviour | [docs/anki.md](docs/anki.md) § device verification (`AnkiBridgeDeviceChecks`; `-e mode snapshot` is read-only) |

## Architectural invariants

**1. Markdown is the database.** No rival editable store for authored Markdown. Anki owns scheduling and review state; a user-requested AnkiDroid JSON export is dated evidence, not a store. WHY: two owners of authored knowledge diverge without a canonical answer.

**2. The sync's only vault write is `anki_note_id`.** Through `patchFrontmatterField` / `MarkdownFile`, preserving the body byte for byte. Interest creates no other vault files except the device-local `.interest/anki-sync.lock`. WHY: an earlier version rebuilt note bodies from its own model and destroyed prose, including a Problem Note's `***` halves.

**3. Structural roles and Anki eligibility are separate.** A Problem Note is the first qualifying `***` split (empty sides allowed); `collection:` presence opts a note out of Anki and withdraws a linked card. `category:` names the deck (absent or empty → Default; a singleton text list is one deck; anything ambiguous is refused). WHY: changing collection identity must withdraw the projection, not move it to Default.

**4. Anki mirrors the vault, and the vault decides.** Cards are created, changed and deleted only from Obsidian. A linked id absent from the collection is `missing` and is never re-added without confirmation; an owned card that no current note links is an `orphan` and is never removed without confirmation; a duplicate (its note links a different card that is present) is retired automatically through the source-guarded `retireNote`. Only `reconcileCollection: true` (complete whole-vault discovery) classifies unreferenced cards. WHY: Obsidian Sync and AnkiWeb settle independently, so "absent here" can mean "not delivered yet".

**5. Full-body wikilink scan.** `rewriteWikilinksToHtml` scans the whole body. WHY: narrowing the scan makes link relationships location-dependent.

## Sync mechanics

Each run starts from one complete `AnkiTransport.snapshot()` and writes only differences; an incomplete snapshot changes nothing. `preview: true` computes the same outcome without writing. Confirmations go through `AnkiSyncService.resolve`, which re-checks each item against a fresh scan and snapshot. A filesystem lease (`AnkiSyncLock`) excludes overlapping runs on one physical vault. Discovery captures exact source text; a source that changed before a write is refused rather than overwritten.

## Service standard

Expected failure crosses a service boundary as an explicit result, including whether an observation was complete. `AnkiProblemNoteScanner`, `AnkiSyncService` and the transports expose errors rather than returning an ordinary empty or partial success. Transports may throw `AnkiSyncAbort` / `AnkiNoteFailure`, consumed only inside `AnkiSyncService`.

## Identity anchors

| Type | Anchor | Mutability |
|---|---|---|
| Problem Note ↔ card | `anki_note_id` frontmatter | Written on first sync; stable across edits and renames |
| Card ownership | the `obsidian://open?vault=…&file=…` source link in the card front (older `+`-encoded links are recognised) | Rewritten by every update |

## Shared utilities — do not duplicate

- **Markdown parsing** — `lib/shared/markdown/md_utils.dart` (pure): frontmatter splitting, `splitFrontBack`, wikilinks, `obsidianUri` / `obsidianUriForName`, `noteKey`.
- **Eligibility** — `CurrentVaultContent` is the one path rule for card sources and link targets. `VaultScanner.scanResult()` is the sole recursive directory walk and exposes incomplete traversal.
- **Safe writes** — `MarkdownFile` / `patchFrontmatterField` in `lib/shared/markdown/`.
- **Design tokens** — `AppColors`, `Space`, `Radii` in `app_theme.dart`; `AppTextStyles` in `app_text_styles.dart`. No hex literals, magic spacing or inline fonts in screens. Every text colour must clear 4.5:1 on its surface (ratios are noted beside the tokens).
- **Feedback** — `showSnack()` for transient messages.

## Subsystem constraints

**Screens** — `HomeScreen` (sync panel, review panel, decisions, last sync) and `SettingsScreen` are the whole app; `VaultSetupScreen` runs once. The home screen follows the journey Obsidian → sync → Anki review; exactly one button is filled, chosen by the next step (see docs/ui.md). Obsidian is reached through links on specific notes. Decisions are one card per page in `DecisionPager`, never stacked modal dialogs. Review counts come only from `AnkiTransport.reviewLoad()`, which is read-only.

**Device memory** — SharedPreferences holds `vault_path`, the last sync summary and kept card ids (`SyncMemory`). There is no vault configuration file.

**Anki state observation** — read-only. It must not invoke the scheduler, answer cards, select decks or call sync. Save uses the chosen document URI and verifies written bytes. Full contract: docs/anki.md.

**Deep link (Android)** — `interest://sync-anki` is a VIEW intent on `MainActivity` (`launchMode=singleTop`): cold start stores `pendingSyncAnki`; a running app receives `onNewIntent` → `syncAnki`. `HomeScreen` syncs immediately on it and previews on a normal open. A headless trampoline was tried and never synced on-device; don't reintroduce it.

**State management** — `setState` only.

## Targeted Anki CLI

`tool/sync_anki_notes.dart` must reuse `AnkiProblemNoteScanner`, `AnkiSyncService` and `AnkiConnectTransport`, require explicit `--file` arguments, reject paths outside the vault, never classify unlinked cards, and re-create missing cards only with `--recreate-missing`.
