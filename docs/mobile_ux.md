# Mobile UX conventions

Android-specific safe area, keyboard, and interaction patterns. These apply globally — maintain them when adding or modifying any Scaffold body, modal, bottom bar, or form field.

---

## Safe area

### Scaffold body

Every Scaffold body must be wrapped in `SafeArea(top: false)`. The AppBar handles the top inset; `SafeArea(top: false)` protects the bottom edge from the Android gesture navigation bar (height varies by device and nav mode — do not substitute a fixed-pixel bottom padding).

```dart
body: SafeArea(
  top: false,
  child: YourBodyWidget(...),
),
```

Screens where this has been applied: `_StoragePermissionGate`, `VaultSetupScreen`, `SettingsScreen`, entity display body, entity edit body.

### ListView bodies

A `ListView` or `ListView.builder` inside a `SafeArea(top: false)` body inherits the safe area at the bottom. Its own `padding` should use `EdgeInsets.all(16)` or equivalent without adding an extra bottom offset.

Exception: when a FAB overlaps the list — see FAB list clearance below.

### Bottom bars and persistent input bars

Persistent bottom bars use `SafeArea(top: false)` directly around the bar widget, not around the whole Scaffold body:

```dart
SafeArea(
  top: false,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
    child: Row(...),  // input bar
  ),
)
```

`Scaffold.resizeToAvoidBottomInset` (default `true`) handles keyboard avoidance for the bar. No manual `viewInsets.bottom` needed on the bar itself.

Reference: `task_file_screen.dart` — canonical implementation.

### Bottom sheet menus

`showBottomSheetMenu()` in `lib/shared/widgets/bottom_sheet_menu.dart` already wraps its content in `SafeArea`. No extra action needed.

### Scrollable search sheets (`isScrollControlled: true`)

These use keyboard padding + screen-fraction height:

```dart
showModalBottomSheet(
  isScrollControlled: true,
  builder: (ctx) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.55,  // fraction, not pixels
        child: Column(...),
      ),
    );
  },
);
```

Use screen-fraction height (not fixed pixels) so the sheet scales across device sizes:

| Sheet content | Height fraction |
|---------------|----------------|
| RSS feed add/edit form | `* 0.55` |
| Hardcover search + result list | `* 0.85` |

(The Quick Add Sheet is `isScrollControlled` but sizes to its content; it needs only the keyboard-inset padding.)

---

## FAB list clearance

When a screen has a `FloatingActionButton`, the scrollable body must add bottom padding to prevent the last item from sitting behind the FAB:

```dart
ListView.builder(
  padding: const EdgeInsets.only(bottom: kFabListBottomPad),
  ...
)
```

`kFabListBottomPad = 88.0` from `lib/shared/constants/app_spacing.dart` (FAB 56 + margin 16 + safe area buffer 16).

Screens requiring this: `CollectionsScreen` (entity list), `ProjectsScreen`, `ProjectListDetailScreen`, `TemplatesScreen`, `RssScreen`, `HardcoverScreen`.

---

## Keyboard handling

### resizeToAvoidBottomInset

Scaffold default (`true`) handles keyboard avoidance for the body. Do not override to `false` unless the screen manages insets manually.

### TextInputAction

Every `TextField` must declare `textInputAction`. Standard assignments:

| Context | Value |
|---------|-------|
| Non-last field in a form | `TextInputAction.next` |
| Last field in a form | `TextInputAction.done` |
| Multiline textarea | `TextInputAction.newline` |
| Inline add field (tasks) | `TextInputAction.send` |
| Inline note-add field (tasks) | `TextInputAction.newline` |

Flutter's default focus traversal handles `next` hops without explicit `FocusNode` chains.

### Inline edit fields

Inline `TextField`s (task text, list items) commit on:
- `onSubmitted` — explicit keyboard submit
- `onTapOutside` — tap elsewhere

**Exception — task note edit fields**: `onTapOutside` is intentionally absent. The note edit row includes an inline delete button; if `onTapOutside` were present, tapping delete would trigger a save before the delete fires, causing a redundant write. Note edits commit only on `onSubmitted`.

After commit the keyboard dismisses naturally via `FocusScope.of(context).unfocus()` or the framework's default behavior.

---

## Shared spacing constants

`lib/shared/constants/app_spacing.dart`:

| Constant | Value | Use |
|----------|-------|-----|
| `kFabListBottomPad` | `88.0` | Bottom padding on lists behind a FAB |
| `kScreenHPad` | `16.0` | Standard horizontal body padding |
