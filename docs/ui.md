# UI System

Canonical reference for visual design and navigation. Color constants live in `lib/shared/constants/app_theme.dart`. Named text styles live in `lib/shared/constants/app_text_styles.dart`.

---

## Theme

Material 3, dark only (`Brightness.dark`). No light theme. `scaffoldBackgroundColor` is `AppColors.background`.

**Font:** IBM Plex Sans (body, UI) and IBM Plex Serif (card front/back) via `google_fonts`. All `ThemeData.textTheme` entries use `GoogleFonts.ibmPlexSans()`.

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
| `cardAnswer` | **Serif** | 17 | 400 | textPrimary | Card back, height 1.78; card front uses `copyWith(fontSize: 21, height: 1.65)` |
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

**Bottom nav bar** — 2 tabs, labeled, no elevation, `border-top: 1px AppColors.border`. Background: `surfaceElevated` (#161616).

| Index | Label | Icon (inactive / active) | Screen |
|---|---|---|---|
| 0 | COLLECTIONS | `hub_outlined` / `hub` | `CollectionsScreen` (landing) |
| 1 | PROJECTS | `checklist_outlined` / `checklist` | `ProjectsScreen` |

Active tab: label + icon in `accent`. Inactive: `textTertiary`. Label style: `navLabel` (9px w600, uppercase, letterSpacing 0.5).

**AppBar** (owned by `HomeScreen`): the title is the tab name; the `sensors` icon pushes the Sources screen; the overflow menu holds Settings, Templates, and Open Obsidian.

**Sources screen** — not a tab. Pushed from the `sensors` AppBar icon. Three rows: Hardcover, Obsidian, Anki desktop — icon / name+description / meta / chevron. (AnkiDroid sync is deep-link triggered, not a row.)

---

## Component patterns

**No elevation** — elevation: 0 everywhere (AppBar, Cards, FAB, BottomSheet).

**AppBar** — background `background`, no shadow, icon color `textSecondary`, title IBM Plex Sans 17px w600 `textPrimary`.

**Cards** — background `surface`, border `borderMid`, radius 10, zero margin, zero elevation.

**Bottom sheets / dialogs** — background `surfaceElevated`, radius 14 (top corners for sheets, all corners for dialogs).

**FAB** — `AppFab` (`lib/shared/widgets/app_fab.dart`): 52×52, background `accentDim`, foreground `accent`, radius 14, border `1px accent.withValues(alpha: 0.33)`. Every screen-level primary action uses this one widget (Collections quick-add, Projects new-project, Templates new-template, list-detail add-item); there are no raw `FloatingActionButton`s.

**Dividers** — color `border` (#1E1E1E), thickness 1, space 0.

**Input fields** — background `surface`, border `border`, focused border `accent`, hint `textTertiary`, radius 10.

**Chips (`SelectChip`)** — padding `5×14`, radius 20, gap 6. Active: bg `accentDim`, border `accent`, text `accent`. Inactive: bg transparent, border `border`, text `textSecondary`. Used for collection filters and quick-fill rows.

**List rows (`ListRow`)** — hairline bottom border `border`; default padding 14px vertical / `kScreenHPad` horizontal. Every bordered list row builds on this widget.

**Section headers** — `SectionHeader` widget: 10px IBM Plex Sans w600 uppercase, letterSpacing 1.3, `textTertiary`. Top padding 14px, bottom 8px.

---

## Quick Add Sheet (`lib/shared/widgets/quick_add_sheet.dart`)

Opened via `showQuickAddSheet(context, ...)`. `showModalBottomSheet(isScrollControlled: true)`.

Layout:
1. Handle bar (36×4 `borderMid`)
2. Header row: "Add to collection" (16px w600) + "Add" `AccentButton`
3. Auto-focused name `TextField`
4. Free-text Collection `TextField` — any value creates/uses a collection
5. Existing collections as quick-fill `SelectChip`s (horizontal scroll)
6. Last-used collection persisted in `SharedPreferences` key `last_used_collection`

On submit: creates the file via `MarkdownStorageService.saveEntity` → dismisses sheet → `onCreated` callback (HomeScreen reloads and opens the new entity).

---

## Collections tab rows

Layout per entity row:
- Name: IBM Plex Sans 15px w500 `textPrimary`
- Metadata `Wrap`: `★N` (score color 12px), collection name (13px `textSecondary`), up to two `#tag`s (13px accent)
- Timestamp right-aligned: 11px `textTertiary` (`formatRelative`)
- `ListRow` bottom border; padding 13px vertical / 16px horizontal

---

## Entity detail view (`EntityScreen`)

**Title block** (padding `22 top / 16 horizontal`): name 26px w600 letterSpacing −0.3 height 1.2; meta row below — collection · `#tag` (accent) · `★N` (score) — all 13px.

**Body**: a read-only render of the note via the shared `noteMarkdownBody` (tappable wikilinks open Obsidian), then the Grokipedia card. There is no in-app backlinks panel or body editor — those live in Obsidian.

**Grokipedia card**: `surface` bg, `borderMid` border, radius 8, padding `12×14`; body 14px `textSecondary` height 1.65; "Read full article" link + `open_in_new` icon in accent; "Show/Hide summary" toggle.

**Edit details mode**: collection dropdown, tag chips with `RawAutocomplete` add field, score slider. AppBar shows Cancel / Save text buttons.

> Card rendering and the `***` review viewer live in **Obsidian** (the Problem Notes plugin), not in Interest — there is no in-app deck list or card viewer. IBM Plex Serif is still defined in `app_text_styles.dart` for card-like surfaces but the app no longer renders cards.

---

## Sources screen layout

Inbox-style list. AppBar: "Sources" title + "Sync all" outlined button (border `border`, `sync` icon + text, 12px `textSecondary`).

Row layout: icon (22px `textSecondary`) | name (500 15px) + description+meta below (13px/11px `textSecondary`/`textTertiary`) | `arrow_forward_ios` right (14px `textTertiary`). Rows with a sync in flight dim and show an `InlineSpinner`.

---

## Projects screen layout

Row layout (padding `14×16`):
- Name: IBM Plex Sans 500 15px; `textSecondary` if 100% complete
- Type badge right: "LIST" or "TODO", 11px w600 uppercase, 0.8px letterSpacing, `textTertiary`
- Progress bar (todo-style with tasks): height 2, `LinearProgressIndicator`, `accent` fill (in-progress) / `textTertiary` (complete), `border` track, radius 1
- Count label: "done / total" 11px `textTertiary`

---

## Spacing constants (`lib/shared/constants/app_spacing.dart`)

| Constant | Value | Usage |
|---|---|---|
| `kFabListBottomPad` | 88.0 | Bottom padding for lists behind a FAB |
| `kScreenHPad` | 16.0 | Horizontal screen padding |
