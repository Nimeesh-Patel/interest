# UI System

Canonical reference for visual design and navigation. Color constants live in `lib/shared/constants/app_theme.dart`. Named text styles live in `lib/shared/constants/app_text_styles.dart`.

---

## Theme

Material 3, dark only (`Brightness.dark`). No light theme. `scaffoldBackgroundColor` is `AppColors.background`.

**Font:** IBM Plex Sans (body, UI) and IBM Plex Serif (card front/back, note peek) via `google_fonts`. All `ThemeData.textTheme` entries use `GoogleFonts.ibmPlexSans()`.

---

## Color palette

```dart
class AppColors {
  static const background      = Color(0xFF0A0A0A);  // Scaffold background
  static const surface         = Color(0xFF111111);  // Card / sheet background
  static const surfaceElevated = Color(0xFF161616);  // Bottom sheet, dialog, popup menu, nav bar
  static const border          = Color(0xFF1E1E1E);  // Dividers, list separators
  static const borderMid       = Color(0xFF282828);  // Card borders (slightly lighter than border)
  static const textPrimary     = Color(0xFFF0F0F0);  // Body text, titles
  static const textSecondary   = Color(0xFF595959);  // Subtitles, metadata, icons
  static const textTertiary    = Color(0xFF2C2C2C);  // Hints, disabled, counters, muted glyphs
  static const accent          = Color(0xFF8B7CF6);  // Primary action, links, selected state
  static const accentDim       = Color(0xFF1C1835);  // FAB background, active chip background
  static const destructive     = Color(0xFFE05252);  // Error, delete actions
  static const score           = Color(0xFFFFB800);  // Rating / quality signal (amber)
}
```

ColorScheme mappings for Material widgets: `onSurface` → `textPrimary`, `onSurfaceVariant` → `textSecondary`, `primary` → `accent`, `outline` → `border`, `surface` → `surface`, `surfaceContainerHighest` → `surfaceElevated`.

---

## Typography

### `AppTextStyles` — named static getters (`lib/shared/constants/app_text_styles.dart`)

All use `GoogleFonts.ibmPlexSans()` unless noted.

| Getter | Font | Size | Weight | Color | Notes |
|---|---|---|---|---|---|
| `appTitle` | Sans | 17 | 600 | textPrimary | AppBar title |
| `sectionHeader` | Sans | 10 | 600 | textTertiary | Uppercase, letterSpacing 1.3 |
| `entityName` | Sans | 15 | 500 | textPrimary | List row primary label |
| `bodyLarge` | Sans | 16 | 400 | textPrimary | General body |
| `bodyMedium` | Sans | 14 | 400 | textPrimary | |
| `bodySmall` | Sans | 13 | 400 | textSecondary | Subtitles, metadata |
| `meta` | Sans | 12 | 400 | textSecondary | Timestamps, counts |
| `metaMuted` | Sans | 11 | 400 | textTertiary | Muted labels |
| `cardQuestion` | **Serif** | 21 | 400 | textPrimary | Card front, height 1.65 |
| `cardAnswer` | **Serif** | 17 | 400 | textPrimary | Card back, height 1.78 |
| `notePeek` | **Serif** | 17 | 400 | textPrimary | Home dashboard card peek |
| `navLabel` | Sans | 9 | 600 | — | Bottom nav; uppercase, letterSpacing 0.5 |

### `ThemeData.textTheme` (fallback for widgets using `Theme.of(context).textTheme`)

| Style | Size | Weight | Font |
|---|---|---|---|
| `bodyLarge` | 16 | 400 | IBM Plex Sans |
| `bodyMedium` | 14 | 400 | IBM Plex Sans |
| `bodySmall` | 12 | 400 | IBM Plex Sans |
| `labelSmall` | 11 | 400 | IBM Plex Sans |
| `titleLarge` | 22 | 600 | IBM Plex Sans, letterSpacing −0.3 |
| `titleMedium` | 16 | 400 | IBM Plex Sans |
| `titleSmall` | 13 | 500 | IBM Plex Sans, letterSpacing +1.2 |
| `headlineSmall` | 18 | 600 | IBM Plex Sans |

AppBar title: 17px w600 IBM Plex Sans.

---

## Navigation

**Bottom nav bar** — 4 tabs, labeled, no elevation, `border-top: 1px AppColors.border`. Background: `surfaceElevated` (#161616).

| Index | Label | Icon (inactive / active) | Screen |
|---|---|---|---|
| 0 | HOME | `home_outlined` / `home` | `HomeDashboardScreen` |
| 1 | NOTES | `auto_stories_outlined` / `auto_stories` | `ResurfaceScreen` |
| 2 | COLLECTIONS | `hub_outlined` / `hub` | Collections tab (inline in `HomeScreen`) |
| 3 | PROJECTS | `checklist_outlined` / `checklist` | `ProjectsScreen` |

Active tab: label + icon in `accent`. Inactive: `textTertiary`. Label style: `navLabel` (9px w600, uppercase, letterSpacing 0.5).

Double-tapping the NOTES tab calls `ResurfaceScreenState.resetStack()` (collapses to deck list).

**Sources screen** — not a tab. Pushed from the `sensors` AppBar icon. Full inbox-style layout: Hardcover, Articles, Readwise, Bookmarks, and Obsidian as rows with icon / name+description / last-sync meta / chevron.

---

## Component patterns

**No elevation** — elevation: 0 everywhere (AppBar, Cards, FAB, BottomSheet).

**AppBar** — background `background`, no shadow, icon color `textSecondary`, title IBM Plex Sans 17px w600 `textPrimary`.

**Cards** — background `surface`, border `borderMid`, radius 10, zero margin, zero elevation.

**Bottom sheets / dialogs** — background `surfaceElevated`, radius 14 (top corners for sheets, all corners for dialogs).

**FAB** — background `accentDim`, foreground `accent`, radius 14, size 52×52, border `1px accent.withValues(alpha:0.33)`.

**Dividers** — color `border` (#1E1E1E), thickness 1, space 0.

**Input fields** — background `surface`, border `border`, focused border `accent`, hint `textTertiary`, radius 10.

**Chips (category filter)** — padding `5×14`, radius 20, gap 6. Active: bg `accentDim`, border `accent`, text `accent`. Inactive: bg transparent, border `border`, text `textSecondary`.

**Related chips (entity detail)** — text `[[Name]]`, 13px `accent`, padding `4×10`, border `accentDim`, radius 6.

**Inline edit fields** — bg `surface`, border `1px accent`, radius 7, padding `6×10`.

**Section headers** — `SectionHeader` widget: 10px IBM Plex Sans w600 uppercase, letterSpacing 1.3, `textTertiary`. Top padding 14px, bottom 8px.

---

## Home Dashboard (`HomeDashboardScreen`)

Entry point screen (tab 0). Loads on `initState` via `ResurfaceService.getAllNotes()` and `MarkdownStorageService`.

### Card Peek Hero

Surface-colored container with `borderMid` border, radius 10:
- First card's question text in IBM Plex Serif 17px (from `GraphScoringService.sortByPriority()`)
- Deck name + "N cards to review" meta
- "Review" `→` button (accent bg, white text) — switches to Notes tab (tab 1)

### Worth Revisiting section

Entities sorted by `(score × 0.4) + (daysSinceUpdated × 0.6)` descending, capped at 3 rows. Each row shows name + reason text (e.g. "Not visited in 7 days") + category right-aligned. Reason logic: days > 7 → "Not visited in N days"; score > 7 → "High rated"; days ≤ 2 → "Updated recently"; else → "Worth another look".

### Recent Notes section

2 most recently modified vault notes (by file `stat().modified`). Shows filename + deck name + `✦` glyph if note has card.

### Persistent FAB

`AppFab` (`lib/shared/widgets/app_fab.dart`) — 52×52px, `accentDim` bg, accent icon, radius 14. Every screen-level primary action uses this one widget (Collections quick-add, Projects new-project, RSS add-feed, Templates new-template, list-detail add-item); there are no raw `FloatingActionButton`s.

---

## Quick Add Sheet (`lib/shared/widgets/quick_add_sheet.dart`)

Opened via `showQuickAddSheet(context, ...)`. `showModalBottomSheet(isScrollControlled: true)`.

Layout:
1. Handle bar (36×4 `borderMid`)
2. Header row: "Add entity" (16px w600) + "Add" CTA (accent bg, white text)
3. Auto-focused name `TextField` (accent border when focused)
4. Category chips (horizontal scroll, same active/inactive style as entity list)
5. Last-used category persisted in `SharedPreferences` key `last_used_category`

On submit: calls `MarkdownStorageService` create path → dismisses sheet → navigates to new entity.

---

## Entity list rows

Used in Home (Worth Revisiting) and Collections tab. Layout per row:
- Name: IBM Plex Sans 15px w500 `textPrimary`
- Metadata `Wrap`: `★N` (score color 12px), category name (13px `textSecondary`), `#tag` (13px accent)
- Timestamp right-aligned: 11px `textTertiary`
- Bottom border `border`; padding 13px vertical / 16px horizontal

---

## Entity detail view

**Title block** (padding `22 top / 16 horizontal`):
- Name: IBM Plex Sans 26px w600, letterSpacing −0.3, height 1.2; tappable → inline `TextField`
- Meta row: category · `#tag` (accent) · `★N` (score) — all 13px

**Section pattern:** `SectionHeader` (caps) + content, left-padded `kScreenHPad`.

**Notes bullets:** `· ` (14px `textTertiary`) + text (15px, height 1.55); each bullet tappable → inline `TextField`. `+ Add note` row always visible below bullets.

**Sources:** `link` icon (14px accent) + URL text (14px accent), gap 8, margin-bottom 6.

**Related:** `[[Name]]` chips (13px accent, border `accentDim`, radius 6); `+ Link` chip always visible.

**Grokipedia card:** `surface` bg, `borderMid` border, radius 8, padding `12×14`; body 14px `textSecondary` height 1.65; "Read full article" link + `open_in_new` icon in accent; "Show/Hide summary" toggle.

**Inline edit AppBar:** when `_hasUnsavedChanges == true` → `check` icon (accent) → calls `_saveEdit()`. When false → `edit` icon + (implicit) `more_vert` menu.

---

## Notes / Decks screen layout

**Deck list (DeckListRoute):**
1. **All Notes hero** — surface card with `borderMid` border, radius 10: `✦` (16px accent) + "All Notes" (w600 16px) + "N problem notes to review" (13px `textSecondary`) + `arrow_forward_ios` right
2. **DECKS section** (named decks only, if any): `✦` glyph (11px `textTertiary`) + deck name (500 15px) + count + `arrow_forward_ios`
3. **RECENT NOTES section**: top-2 most recently modified vault notes, filename (15px) + first deck below (13px) + `✦` right (12px accent) if `isProblemNote`

---

## Card review layout (`_NoteViewerBody`)

**Card body** (padding `40 top / 26 horizontal / 28 bottom`):
- Front: IBM Plex Serif 21px, height 1.65, `textPrimary`; margin-bottom 38
- Divider: `borderMid`, margin-bottom 30 (shown after reveal)
- Back: IBM Plex Serif 17px, height 1.78, `textPrimary`; `**bold**` spans rendered in accent w600

**Navigation row** (border-top `border`, padding `12 vertical / kScreenHPad horizontal`):
- **Prev:** outlined button (border `border`, radius 8, padding `9×18`), `arrow_back_ios_new` + "Prev" in `textSecondary`
- **Progress:** "N / total" center (13px `textTertiary`)
- **Next:** filled button (`accent` bg, radius 8, padding `9×20`), "Next" w600 white + `arrow_forward_ios` white; dimmed to `accentDim` when at last card

---

## Sources screen layout

Inbox-style list. AppBar: "Sources" title + "Sync all" outlined button (border `border`, `sync` icon + text, 12px `textSecondary`).

Row layout: icon (22px `textSecondary`) | name (500 15px) + description+meta below (13px/11px `textSecondary`/`textTertiary`) | `arrow_forward_ios` right (14px `textTertiary`).

---

## Projects screen layout

Row layout (padding `14×16`):
- Name: IBM Plex Sans 500 15px; `textSecondary` if 100% complete
- Type badge right: "LIST" or "TODO", 11px w600 uppercase, 0.8px letterSpacing, `textTertiary`
- Progress bar: height 2, `LinearProgressIndicator`, `accent` fill (in-progress) / `textTertiary` (complete), `border` track, radius 1
- Count label: "done / total" 11px `textTertiary`

---

## Spacing constants (`lib/shared/constants/app_spacing.dart`)

| Constant | Value | Usage |
|---|---|---|
| `kFabListBottomPad` | 88.0 | Bottom padding for lists behind a FAB |
| `kScreenHPad` | 16.0 | Horizontal screen padding |
