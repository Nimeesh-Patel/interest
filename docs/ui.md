# UI and design system

Interest has one main screen and one settings screen. The design exists to
make the sync's state obvious and the occasional decision easy. Tokens live in
`lib/shared/constants/app_theme.dart`, type in `app_text_styles.dart`.

## Why it looks the way it does

The previous palette was near-black with a single purple accent. Its secondary
text measured 2.8:1 against the background and its tertiary text 1.4:1, so
labels and counts were close to invisible. The current system follows two
references:

- **Anthropic's `frontend-design` skill**: plan a small token system before
  building; avoid generic defaults (near-black with one accent, all-caps
  eyebrows, middle-dot metadata strings); put boldness in one memorable
  element; screenshot and criticise while building.
- **Refactoring UI** (Wathan and Schoger): build hierarchy with colour and
  weight before size; de-emphasise by bringing text closer to its background,
  never below a readable contrast; not every button needs a fill.

## Rules

1. **Every text colour clears WCAG AA (4.5:1) on every surface it can sit on.**
   Ratios are noted beside each token. Re-measure before changing a colour.
   Interactive outlines use `outline`, at least 3:1. `line` is for hairline
   dividers only.
2. **Surfaces step in lightness:** `canvas` (page), `card` (in-flow panels),
   `raised` (sheets and dialogs). Colours derive from the app icon (`#5BA8C4`)
   on a blue-tinted charcoal.
3. **Two voices.** IBM Plex Sans for the app's own words, IBM Plex Serif for
   the author's: a card's problem and conjecture. Nothing is smaller than 13 px
   or set in all caps.
4. **The screen follows the journey, and emphasis follows the next step.** The
   journey is Obsidian (write) → sync → Anki (review), so the home screen
   stacks a sync panel above a review panel. Exactly one button is filled: Sync
   while changes are waiting or a sync failed; "Review in AnkiDroid" once
   everything is in sync and cards are due. Obsidian, the step you came from,
   is reached through links on specific notes (changed notes, a missing card's
   note) plus a header icon, not a competing button.
5. **Counts match the app they describe.** The review panel's numbers are
   AnkiDroid's own deck counts with daily limits ("192 cards due: 100 to
   review, 85 new, 7 learning"), summed over top-level decks, so what Interest
   says is what AnkiDroid will show.
6. **State is a sentence.** The status panel always says one thing ("Everything
   is in sync", "3 changes to sync", "Sync didn't finish") and what it means.
7. **Decisions are cards, one per page.** The pager shows a peek of the next
   card, arrows and a count, and dots. Each card shows the reason, the title,
   deck, review history and creation date, then the problem and conjecture as
   fixed-length previews separated by the `***` divider, the design's one
   signature element. "Read the full card" opens the whole card in a sheet.
   Destructive actions use the danger colour on a tinted fill, never a
   saturated red block.
8. **Copy** is sentence case, active and specific ("Remove", "Re-create",
   "Allow access"), with no "please", "successfully" or exclamation marks.

## Checking a change

Build a release APK, install it on the phone, and screenshot every state that
changed, including checking, in sync, changes waiting, failed and decisions.
Criticise each screenshot against the rules above before calling it done.
