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

**Summary / flat (unchanged):**
- `loadTaskFiles()` — scans `Interesting/Tasks/*.md`; counts tasks via regex → `List<TaskFile>` (summary only)
- `loadLines(filePath)` → `List<String>`
- `toggleTask(filePath, lineIndex)` — flip `[ ]` ↔ `[x]` on one line
- `addTask(filePath, text)` — append root-level task to end of file
- `deleteTask(filePath, lineIndex)` — remove single line
- `updateTaskText(filePath, lineIndex, newText)` — preserve indent + state, replace text
- `createTaskFile(name)` → `TaskFile?`; writes `# name\n\n`; null on collision
- `deleteTaskFile(filePath)` — hard delete

**Hierarchical (new):**
- `parseNodes(lines)` → `List<TaskNode>` — pure parser
- `addNote(filePath, parent, noteText)` — insert `noteText` at `parent.startLine + 1` with `parent.indentSpaces + 2` indent; multiline text split on `\n`; each empty line stored as `''`
- `addSubtask(filePath, parent, text)` — insert `' ' * (parent.indentSpaces + 2) + '- [ ] text'` at `parent.endLine + 1`
- `addSiblingTask(filePath, block, text)` — insert `' ' * block.indentSpaces + '- [ ] text'` at `block.endLine + 1` (same indent level as `block`)
- `deleteBlock(filePath, block)` — `removeRange(block.startLine, block.endLine + 1)`; removes full subtree
- `updateBlockText(filePath, block, newText)` — thin wrapper: `updateTaskText(filePath, block.startLine, newText)`
- `updateLine(filePath, lineIndex, newText)` — raw line replacement; used for inline note editing (caller must re-prepend original indentation)
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
- `_addingSiblingOf` — `int?` startLine of source block for pending sibling add; sibling field renders outside the block's indent wrapper

**Constructor params:** `filePath`, `title`, `onRenamed` (optional callback `(String newPath, String newTitle) → void`).

**Rendering:**
- `_buildNodeWidget` dispatches to header/prose/block renderers
- `_buildBlockWidget(block, depth)`: `Padding(left: depth * 24px)` with collapse chevron, Checkbox, task text (or inline TextField), ⊕ add-subtask icon, ··· more-actions icon (→ sheet: Add note / Add sibling task / Delete)
- Task text color: `Theme.of(context).colorScheme.onSurface` (explicit; `RichText` does not inherit `DefaultTextStyle`)
- Notes: italic grey 13px, `left = 56px + depth * 24px`
- Completed tasks: grey + strikethrough
- Collapse chevron visible when `block.children.isNotEmpty || block.noteLineIndices.isNotEmpty`

**Render order inside a block (top → bottom):**
1. Task row (chevron / checkbox / text / ⊕ subtask-icon / ··· more-icon)
2. Inline note-add field (if `_addingNoteOf == block.startLine`)
3. Existing notes (`noteLineIndices`)
4. Inline subtask-add field (if `_addingChildOf == block.startLine`)
5. Children (recursive)

Sibling add field (`_addingSiblingOf == block.startLine`) renders **outside** the block's indent wrapper, as a sibling of the block in a wrapping `Column`.

**Inline editing:** Tap task text → TextField in-place (no dialog). Tap note line → TextField in-place. Note edit re-prepends original leading whitespace before writing (`_lines[lineIndex]` prefix). Both save on `onSubmitted` and `onTapOutside`.

**Add note:** Tap 📝 icon → sets `_addingNoteOf`; renders `_buildInlineNoteAddField` — multiline TextField (`maxLines: null`, `TextInputAction.newline`) at note indent. Confirm (✓) calls `addNote(filePath, parent, text)`; inserted at `parent.startLine + 1`.

**Add subtask:** Tap ⊕ icon → sets `_addingChildOf`; renders inline TextField below existing notes.

**Bottom bar:** `SafeArea(top: false)` handles Android gesture nav bar. `Scaffold.resizeToAvoidBottomInset` (default true) handles keyboard. No manual `viewInsets.bottom` padding.

**Rename:** AppBar `PopupMenuButton` → `showInputDialog()` → `renameTaskFile()` → updates `_currentTitle` / `_currentPath` in state; calls `onRenamed`.

## HomeScreen integration (`lib/screens/home_screen.dart` — stays at this path)

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
- Do NOT add due dates, reminders, recurring tasks, priorities, notifications, drag-to-reorder, or calendar
- `TaskBlock.endLine` is computed from the live subtree — do not cache across reloads
