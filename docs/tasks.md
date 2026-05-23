# Tasks subsystem

Hierarchical Markdown-native task layer. Files in `Interesting/Tasks/` — one per topic, no YAML frontmatter. Fully Obsidian-compatible; can be edited directly.

Task files are ephemeral working lists, not knowledge nodes. They carry no `alias` and cannot participate in the entity graph. Because there is no stable identity to preserve, deletion is hard (no `.trash/`) — in contrast to Anki cards, which have an `anki_id` that must survive across syncs and therefore require soft-delete.

## File format

```markdown
# Build

## Goals

- [ ] Improve [[Anki Integration]]

  Current sync is correct, but Markdown coexistence still fragile.

  - [ ] Preserve arbitrary sections
  - [ ] Improve conflict handling

- [ ] Explore [[Readwise]]

## Done

- [x] Fix widget UX
```

Task syntax: `- [ ] text` (uncompleted), `- [x] text` (completed). Regex: `^\s*-\s+\[([ xX])\]\s+(.+)$`.  
Subtasks: `- [ ]` at 2-space indent multiples below the parent task.  
Notes: indented prose lines (non-task) between a task and its subtasks.  
Wikilinks: preserved verbatim; not wired into `EntityLink` graph.

## In-memory model (`lib/features/tasks/models/task_block.dart`)

The file is parsed into a `TaskNode` tree in memory. The tree is a parsed projection only — Markdown files remain canonical.

```
abstract class TaskNode

  TaskHeaderNode   lineIndex, headingLevel (2 or 3), text
  TaskProseNode    lineIndex, raw
  TaskBlock        text, completed, indentSpaces, startLine,
                   noteLineIndices[], children[]
                   endLine (computed: max over startLine, noteLineIndices, children.last.endLine)
```

`indentSpaces` = raw count of leading spaces before `-`.  
`indentLevel = indentSpaces ~/ 2`.  
`endLine` = last line belonging to the block's full subtree — derived, not stored; invalidated on every `_reload()`.

## Parser (`TaskStorageService.parseNodes`)

**Signature:** `static List<TaskNode> parseNodes(List<String> lines)` — pure, no I/O. Call after `loadLines()`.

**Top-level scan:**
1. Skip H1 (file title — rendered in AppBar)
2. `##` / `###` → `TaskHeaderNode`
3. `_taskRegex` match → `TaskBlock`; call `_collectBlockContent`
4. Anything else → `TaskProseNode`

**`_collectBlockContent(lines, start, parent) → int`** (private):
- Blank line: look ahead to next non-blank; if its indent ≤ `parent.indentSpaces` → stop; else add blank to `parent.noteLineIndices`
- Non-blank line with indent > `parent.indentSpaces` + task regex → recurse to build child `TaskBlock`; add to `parent.children`
- Non-blank line with indent > `parent.indentSpaces` + no task match → add to `parent.noteLineIndices`
- Header line or indent ≤ `parent.indentSpaces` → stop
- Returns next unconsumed line index

## Storage methods (`lib/features/tasks/services/task_storage_service.dart`)

All-static, all-catch, never throw.

**Summary / flat:**
- `loadTaskFiles()` — scans `Interesting/Tasks/*.md`; counts tasks via regex → `List<TaskFile>` (summary only)
- `loadLines(filePath)` → `List<String>`
- `toggleTask(filePath, lineIndex)` — flip `[ ]` ↔ `[x]` on one line
- `addTask(filePath, text)` — inserts new root-level task before the first completed root-level task (`^- \[[xX]\]`); appends to end if no completed tasks exist. Completed tasks are always anchored at the bottom of the file by `toggleBlockAndReorder`, so this keeps new tasks in the active region.
- `deleteTask(filePath, lineIndex)` — remove single line (used for both task lines and individual note lines)
- `updateTaskText(filePath, lineIndex, newText)` — preserve indent + state, replace text
- `createTaskFile(name)` → `TaskFile?`; writes `# name\n\n`; null on collision
- `deleteTaskFile(filePath)` — hard delete

**Hierarchical:**
- `parseNodes(lines)` → `List<TaskNode>` — pure parser
- `addNote(filePath, parent, noteText)` — insert `noteText` at `parent.startLine + 1` with `parent.indentSpaces + 2` indent; multiline text split on `\n`; each empty line stored as `''`
- `addSubtask(filePath, parent, text)` — insert `' ' * (parent.indentSpaces + 2) + '- [ ] text'` at `parent.endLine + 1`
- `deleteBlock(filePath, block)` — `removeRange(block.startLine, block.endLine + 1)`; removes full subtree including all notes and children
- `updateBlockText(filePath, block, newText)` — thin wrapper: `updateTaskText(filePath, block.startLine, newText)`
- `updateLine(filePath, lineIndex, newText)` — raw line replacement; used for inline note editing (caller re-prepends original indentation)
- `toggleBlockAndReorder(filePath, block)` — toggle + auto-reorder: completing → move block to end of file; uncompleting → move before first completed root-level block
- `reorderRootBlocks(filePath, nodes, oldIndex, newIndex)` — drag reorder for root-level blocks; mutates file order
- `renameTaskFile(filePath, newName)` → `String?` — updates `# heading` in file, renames file on disk; null on collision or error

All mutations: `readAsLines() → mutate → writeAsString(join('\n'))`. Never regenerate whole file.

## UI (`lib/features/tasks/screens/task_file_screen.dart`)

**State:**
- `_lines` — raw file lines; source of truth
- `_nodes` — `List<TaskNode>` tree; rebuilt from `_lines` on every `_reload()`
- `_collapsed` — `Set<int>` of `block.startLine` keys; session-only; never persisted
- `_editingLine` — `int?` startLine of task being inline-edited
- `_editingNoteLine` — `int?` line index of note being edited
- `_addingChildOf` — `int?` startLine of parent for pending subtask add
- `_addingNoteOf` — `int?` startLine of parent for pending note add; cleared by `_reload()`

**Constructor params:** `filePath`, `title`, `onRenamed` (optional callback `(String newPath, String newTitle) → void`).

**Task row layout (left → right):**

```
[Chevron 24px] [Checkbox 32px] [Task Text Expanded] [⋯ More 32px] [⠿ Drag 32px]
```

- Collapse chevron: visible when `block.children.isNotEmpty || block.noteLineIndices.isNotEmpty`; shows `+N` descendant count badge when collapsed
- Checkbox: toggles completion via `toggleBlockAndReorder`
- Task text: `WikilinkText` in display mode (strikethrough + grey when completed); `TextField` in inline edit mode (tap to activate)
- ⋯ More: opens `_showTaskActions` bottom sheet (see below)
- Drag handle: `ReorderableDragStartListener` — root blocks only (`depth == 0`); 32×32 touch target; hidden during inline editing

**`_showTaskActions` menu (progressive disclosure):**

| Item | Action |
|------|--------|
| Add subtask | sets `_addingChildOf`; renders `_buildInlineAddField` below existing notes |
| Add note | sets `_addingNoteOf`; renders `_buildInlineNoteAddField` |
| Edit | sets `_editingLine`; activates inline text edit |
| Delete | `showConfirmDialog` → `deleteBlock` |

**Render order inside a block (top → bottom):**
1. Task row (chevron / checkbox / text / ⋯ more / drag)
2. Inline note-add field (if `_addingNoteOf == block.startLine`)
3. Existing notes (`noteLineIndices`)
4. Inline subtask-add field (if `_addingChildOf == block.startLine`)
5. Children (recursive)

**Inline editing:**
- Task text: tap → TextField in-place. Saves on `onSubmitted` and `onTapOutside`.
- Note: tap → TextField in-place. Saves on `onSubmitted` only — no `onTapOutside` (tapping the inline delete button must not trigger a save before the delete). Note re-prepends original leading whitespace before writing (`_lines[lineIndex]` prefix).
- Note delete: visible only in note edit mode — `delete_outline` IconButton (18px, `red.shade300`) calls `deleteTask(filePath, lineIndex)`. Hard delete; no undo.

**Completed task separation:**
- `_firstCompleteRootNodeIdx()` finds the first completed root block in `_nodes`
- A "Completed" divider (centered `Divider` + grey label) is inserted at that display index
- `toggleBlockAndReorder` maintains the invariant: completing moves a block to end-of-file; uncompleting moves it before the first completed root block

**Bottom bar:** Persistent `TextField` at screen bottom. `SafeArea(top: false)` handles Android gesture nav bar. `Scaffold.resizeToAvoidBottomInset` (default true) handles keyboard. No manual `viewInsets.bottom` padding. Submitting calls `addTask()`, which inserts the new task before the completed section.

**Drag reorder:** `ReorderableListView.builder` with `buildDefaultDragHandles: false`. Root-level blocks only are draggable. `onReorder` adjusts for the "Completed" divider offset, then calls `reorderRootBlocks()`.

**Rename:** AppBar `PopupMenuButton` → `showInputDialog()` → `renameTaskFile()` → updates `_currentTitle` / `_currentPath` in state; calls `onRenamed`.

## HomeScreen integration (`lib/screens/home_screen.dart`)

`HomeScreen` owns `_taskFiles` state and all task-file CRUD:
- `_reloadTaskFiles()` — refreshes from disk
- `_showCreateTaskFile()` — dialog → `createTaskFile()`
- `_showTaskFileOptions(tf)` — bottom sheet: Rename | Delete
- `_showRenameTaskFile(tf)` / `_renameTaskFile(tf, name)` — rename flow → `renameTaskFile()` → `_reloadTaskFiles()`
- `_showDeleteTaskFileConfirm(tf)` — delete confirmation

`TaskFileScreen` is pushed with `onRenamed: (newPath, newTitle) => _reloadTaskFiles()`.

## Boundaries (do not violate)

- `_collapsed` is session-only — never write to Markdown or SharedPreferences
- `parseNodes` is pure — call only after `loadLines()`; never call from `loadTaskFiles()` (summary scan, no tree needed)
- `deleteBlock` is hard-delete with no trash — task files are not identity-bearing
- Do NOT wire task wikilinks into `EntityLink` graph — task files have no `alias`
- Do NOT add due dates, reminders, recurring tasks, priorities, notifications, or calendar integration
- `TaskBlock.endLine` is computed from the live subtree — do not cache across reloads
