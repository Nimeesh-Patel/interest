# Projects Subsystem

## Purpose

Unified semantic workspace layer. Projects are flexible Markdown files that can hold task outlines, reading queues, scratchpads, structured plans, or any other working list — without imposing a productivity ontology on the user.

Projects replace the former separate Lists and Todos subsystems. That distinction was artificial; both were Markdown files with list-like content. The unified Projects subsystem presents them in a single projection.

---

## Philosophy

Projects are **not** a task-management industrial complex. They are:

- Flexible semantic canvases — no required structure beyond an optional H1 heading
- Markdown-native — editable directly in Obsidian or any editor
- Ephemeral working spaces — hard-deleted when no longer needed, no trash
- Structurally open-ended — a project file can contain anything a Markdown file can

**Do not add** due dates, reminders, scheduling, Kanban boards, priorities, time tracking, or recurring tasks. The system intentionally does not model these to avoid second-order productivity overhead.

---

## Vault layout

```
Interesting/
  Projects/   — canonical directory for new project files
  Lists/      — legacy; scanned for backward compat; new files NOT created here
  Tasks/      — legacy; scanned for backward compat; new files NOT created here
```

On first `ProjectStorageService.loadAll()`, all `.md` files from `Lists/` and `Tasks/` are migrated into `Projects/` (best-effort, one file at a time). The source directories remain on disk (empty) and are still scanned — any files that fail to migrate remain accessible.

**New project files are always created in `Projects/`.**

---

## File format

Projects have two styles, distinguished by frontmatter:

### Todo-style (no frontmatter)

```markdown
# Project Name

## Optional section heading

- [ ] A task item
  - [ ] A subtask
  Text note attached to the task above

- [x] A completed task

- plain item without a checkbox (treated as prose by the renderer)
```

- H1 is the project name (used as the display title in ProjectsScreen)
- H2/H3 are optional section headers
- `- [ ] text` lines are task items; `- [x] text` are completed tasks
- Indented `- [ ]` lines are subtasks (parsed by `TaskStorageService.parseNodes()`)
- Plain prose lines, including `- item` without brackets, appear as body text

Todo-style files are opened with `TaskFileScreen`.

### List-style (`type: list` frontmatter)

```markdown
---
type: list
---
# List Name

- First item
- Second item
- [[Wikilinks]] are rendered inline
```

- YAML frontmatter with `type: list` is the only frontmatter field used
- H1 is the list name
- `- text` lines are list items (no checkboxes, no nesting)
- File is rebuilt on every save (safe — list files have no user prose sections)

List-style files are opened with `ProjectListDetailScreen`.

---

## ProjectFile model

```dart
class ProjectFile {
  final String filePath;
  final String name;         // from H1 heading in body; falls back to basename
  final int totalTasks;      // count of - [ ] / - [x] lines in body
  final int completedTasks;  // count of - [x] lines
  final bool isListStyle;    // true when frontmatter has type: list
  double get progress        // completedTasks / totalTasks (0.0 if no tasks)
}
```

`isListStyle` is derived at parse time from `type: list` frontmatter via `splitFrontmatter()` + `parseYamlMap()` from `md_utils.dart`. List-style files always have `totalTasks == 0` because their `- item` lines do not match the task regex `^\s*-\s+\[([ xX])\]\s+`.

---

## Identity and deletion

| Property | Value |
|---|---|
| Identity anchor | None — no `alias`, no stable ID |
| Rename | Updates H1 + renames file on disk |
| Delete | Hard delete — no trash |

Projects are ephemeral by design. When a project file is deleted, all its content is gone.

---

## Migration from Lists/ and Tasks/

`_migrateIfNeeded()` runs at the start of every `loadAll()` call. It scans `Lists/` and `Tasks/` for `.md` files and moves them into `Projects/`:

- **Best-effort**: one file at a time; a failure on any file does not abort the rest
- **Idempotent**: if source directories are empty or absent, this is a no-op
- **Collision-safe**: `_uniqueDestPath()` appends `_1`, `_2`, … if the destination filename already exists in `Projects/`
- **Hard move**: copy to `Projects/`, then delete the original

After migration, `loadAll()` still scans all three directories (Projects/ + Lists/ + Tasks/). Any files that failed to migrate remain readable from their source location.

Migrated legacy files (originally from Lists/) have no `type: list` frontmatter, so they are treated as todo-style and open with `TaskFileScreen`. Within `TaskFileScreen`, `- item` lines (without checkboxes) render as prose nodes (grey italic text). New items added via the bottom text field become `- [ ] task` items — the distinction erodes naturally over time.

---

## ProjectStorageService

`lib/features/projects/services/project_storage_service.dart`

All-static, all-catch-null, never throws.

```dart
static Future<List<ProjectFile>> loadAll(String vaultPath) async
  // Runs _migrateIfNeeded(), then scans Projects/ + Lists/ + Tasks/
  // Returns List<ProjectFile> sorted A→Z (case-insensitive) by name

static Future<ProjectFile?> createProject(
  String vaultPath,
  String name, {
  bool listStyle = false,
}) async
  // Creates file in Projects/ only
  // Todo: writes '# $name\n\n'
  // List: writes '---\ntype: list\n---\n# $name\n\n'
  // Filename: illegal chars (\ / : * ? " < > |) replaced with '_'
  // Returns null on filename collision or I/O error

static Future<void> deleteProject(String vaultPath, ProjectFile project) async
  // Hard-deletes the file; no trash; no-op if file already absent

static Future<String?> renameProject(
  String vaultPath, ProjectFile project, String newName) async
  // Updates H1 heading in-place (reads all lines, patches first H1, writes back)
  // Renames file on disk; returns new path, or null on collision or I/O error
```

**Note on `renameProject`**: reads the file via `readAsLines()` (not `splitFrontmatter()`), so frontmatter lines are preserved verbatim. The H1 search iterates all lines for the first `# ` prefix (excluding `## `), which correctly skips YAML `---` delimiters and `type: list` lines.

---

## ProjectsScreen

`lib/features/projects/screens/projects_screen.dart`

Displays all project files from `ProjectStorageService.loadAll()` in an A→Z `ListView`. State class is public (`ProjectsScreenState`) so `HomeScreen` can trigger project creation via `GlobalKey`.

**Row display**: name on the left (dimmed when 100 % complete), a "LIST" or "TODO" type badge on the right. If `totalTasks > 0`, a thin `LinearProgressIndicator` and a `"done / total"` count below; list-style rows show neither (their `- item` lines never match the task regex).

**Creation flow**: FAB calls `showCreateDialog(ctx)`, which shows `showBottomSheetMenu` with:
- "Todo outline" (`Icons.check_box_outline_blank`) → `_createProject(ctx, listStyle: false)`
- "Simple list" (`Icons.format_list_bulleted`) → `_createProject(ctx, listStyle: true)`

After type selection, `showInputDialog` prompts for a name. On success, the project is created and the detail screen is pushed immediately.

**Detail routing** — determined by `ProjectFile.isListStyle`:
- `false` → `TaskFileScreen(filePath, title, onRenamed: (_, _) => _reload())`
- `true` → `ProjectListDetailScreen(filePath, title, onRenamed: _reload)`

**Long press**: `showBottomSheetMenu` with Rename and Delete options. Rename calls `ProjectStorageService.renameProject`. Delete requires `showConfirmDialog` confirmation; hard-deletes with no undo.

---

## ProjectListDetailScreen

`lib/features/projects/screens/project_list_detail_screen.dart`

Flat list editor for list-style project files. Does not depend on `ListStorageService` — reads and writes the file directly.

**Load**: `splitFrontmatter()` strips YAML, then parses lines: the first `# ` line sets the title; `- ` lines become items. Lines that are neither H1 nor `- ` prefixed (H2+, blank, prose) are silently skipped on load and lost on the next save.

**Save**: rebuilds the full file as `---\ntype: list\n---\n# $title\n\n- item1\n- item2\n`. Rebuild-on-save is safe because list files have no user prose sections.

**Rename**: patches H1 and renames the file directly (does not call `ProjectStorageService.renameProject` — `vaultPath` is not available in the screen). Calls `widget.onRenamed` on completion so `ProjectsScreen` reloads.

**UI**: `ReorderableListView.builder` — tap to edit inline, delete icon, drag handle. FAB adds item via `showInputDialog`. AppBar trailing (`Icons.more_vert`) opens a bottom sheet with a Rename option.

---

## What is not implemented

- No due dates, priorities, reminders, or notifications
- No Kanban columns or status transitions
- No project metadata beyond `type:` frontmatter
- No project membership in the entity graph
- No statistics dashboards
- No cloud sync
- No trash for project files (hard delete only)
- No automatic project-type migration for existing files — files without `type: list` frontmatter default to todo-style

---

## Boundaries

- `ProjectStorageService` writes only to `Interesting/Projects/` for new files. Migration writes from `Lists/` and `Tasks/` into `Projects/`, then deletes the originals.
- Never add scheduling, due dates, reminders, or recurring tasks.
- Project files have no identity anchor — do not add one unless a genuine use case requires it.
- The task parser (`TaskStorageService.parseNodes`) is shared with the Tasks subsystem; do not duplicate it.
- List-style file saves always rebuild from `_items`; any content outside `# Title` and `- item` lines is discarded on the next save in `ProjectListDetailScreen`.
