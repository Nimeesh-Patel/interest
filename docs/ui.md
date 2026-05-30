# UI System

Canonical reference for visual design and navigation. All values are defined in `lib/shared/constants/app_theme.dart`.

---

## Theme

Material 3, dark only (`Brightness.dark`). No light theme exists. `scaffoldBackgroundColor` is `AppColors.background`.

---

## Color palette

```dart
class AppColors {
  static const background     = Color(0xFF0A0A0A);  // Scaffold background
  static const surface        = Color(0xFF141414);  // Card / sheet background
  static const surfaceElevated= Color(0xFF1C1C1C);  // Bottom sheet, dialog, popup menu
  static const border         = Color(0xFF2A2A2A);  // Dividers, outline borders
  static const textPrimary    = Color(0xFFF0F0F0);  // Body text, titles
  static const textSecondary  = Color(0xFF6B6B6B);  // Subtitles, metadata, icons
  static const textTertiary   = Color(0xFF3D3D3D);  // Hints, disabled, counters
  static const accent         = Color(0xFF8B7CF6);  // Primary action, links, selected tab
  static const accentDim      = Color(0xFF3D3566);  // FAB background, chip selected state
  static const destructive    = Color(0xFFE05252);  // Error, delete actions
  static const score          = Color(0xFFFFB800);  // Rating / quality signal (amber)
}
```

ColorScheme mappings used by Material widgets: `onSurface` → `textPrimary`, `onSurfaceVariant` → `textSecondary`, `primary` → `accent`, `outline` → `border`.

---

## Typography

Named styles from `ThemeData.textTheme`:

| Style | Size | Weight | Color | Letter-spacing |
|---|---|---|---|---|
| `bodyLarge` | 16px | normal | textPrimary | — |
| `bodyMedium` | 14px | normal | textPrimary | — |
| `bodySmall` | 12px | normal | textSecondary | — |
| `labelSmall` | 11px | normal | textTertiary | — |
| `titleLarge` | 22px | w600 | textPrimary | −0.3 |
| `titleMedium` | 16px | normal | textPrimary | — |
| `titleSmall` | 13px | w500 | textSecondary | +1.2 |
| `headlineSmall` | 18px | w600 | textPrimary | — |
| AppBar title | 18px | w600 | textPrimary | — |

---

## Navigation

**Bottom nav bar** — 3 tabs, no labels, no elevation:

| Index | Icon | Screen |
|---|---|---|
| 0 | `Icons.article_outlined` | Notes (`ResurfaceScreen`) |
| 1 | `Icons.list_alt` | Entities |
| 2 | `Icons.folder_outlined` | Projects (`ProjectsScreen`) |

Selected tab icon: `accent` (#8B7CF6). Unselected: `textTertiary` (#3D3D3D). Bar background: `surfaceElevated` (#1C1C1C).

**Sources screen** — not a tab. Pushed via an AppBar icon button. A list screen with rows for Hardcover, RSS, Readwise, and Bookmarks.

---

## Component patterns

**No elevation** — elevation: 0 everywhere (AppBar, Cards, FAB, BottomSheet).

**AppBar** — background `background`, no shadow, icon color `textSecondary`, title `textPrimary` 18px w600.

**Cards** — background `surface`, border `border`, radius 10, zero margin, zero elevation.

**Bottom sheets / dialogs** — background `surfaceElevated`, radius 14 (top corners for sheets, all corners for dialogs).

**FAB** — background `accentDim`, foreground `accent`, radius 14.

**ListTile** — icon color `textSecondary`, title `textPrimary`, subtitle 13px `textSecondary`, min vertical padding 12.

**Dividers** — color `border` (#2A2A2A), thickness 1, space 0.

**Input fields** — background `surface`, border `border`, focused border `accent`, hint `textTertiary`, radius 10.

**Chips** — background `surface`, border `border`, label `textSecondary`; selected: `accentDim` background, `accent` label.

---

## Note card viewer

All content is rendered via `flutter_markdown` `MarkdownBody` using a shared `MarkdownStyleSheet`:

| Element | Size | Weight | Color |
|---|---|---|---|
| H1 (source filename) | 22px | w600 | textPrimary |
| H2 | 19px | w600 | textPrimary |
| H3 | 16px | w600 | textPrimary |
| Body / list bullet | 16px | normal | textPrimary |
| Links (`[[wikilink]]`, URL) | — | — | accent, no underline |

Line heights: H1 1.3, H2 1.35, H3 1.4, body 1.6. H1 letter-spacing −0.3.

The viewer handles two note types in the same queue:

**`***` note layout (top to bottom):**
1. Source filename — H1 `MarkdownBody`
2. Front — `MarkdownBody`, `textPrimary`
3. "tap to reveal" hint (when back hidden) — 14px italic `textTertiary`, centered
4. `Divider` (`border` color, thickness 1) — shown when back revealed
5. Back — `MarkdownBody`, `textPrimary`
6. Pagination row — prev `IconButton` · "N / total" (13px `textTertiary`) · next `IconButton`

Tap anywhere on the card area toggles back visibility.

**Non-`***` (activated plain) note layout:**
1. Source filename — H1 `MarkdownBody`
2. Full body — `MarkdownBody`, `textPrimary` (no front/back split)
3. Pagination row — same as above

No "tap to reveal" affordance. Tap on body area is a no-op. Swipe navigation still active.

Swipe left (velocity < −200) → next; swipe right (velocity > +200) → previous. Navigation resets back-revealed state.

---

## Spacing constants (`lib/shared/constants/app_spacing.dart`)

| Constant | Value | Usage |
|---|---|---|
| `kFabListBottomPad` | 88.0 | Bottom padding for lists behind a FAB |
| `kScreenHPad` | 16.0 | Horizontal screen padding |
