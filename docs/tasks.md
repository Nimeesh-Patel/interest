# Tasks subsystem (parser + outline editor)

## Role

The Tasks subsystem is the **shared checkbox-outline layer used by Inbox and Projects**. It owns the Markdown task syntax (`- [ ]` / `- [x]`, indentation, attached notes), the pure parser that turns file lines into a block tree, the line-level mutation methods, and `TaskFileScreen`.

It is not a standalone storage subsystem and owns no path. `InboxStorageService` owns the persistent `Interesting/Inbox.md`; `ProjectStorageService` owns `Interesting/Projects/`. Items carry no stable identity and participate in no graph.

## Non-goals

Do not add: due dates, reminders, recurring tasks, priorities, notifications, calendar integration, time tracking, or productivity statistics. These would turn a lightweight working list into a second-order planning system.

---

## File format

```markdown
# Build

## Goals

- [ ] Improve [[Anki Integration]]

  Current sync is correct, but Markdown coexistence still fragile.

  - [ ] Preserve arbitrary sections
  - [ ] Improve conflict handling

- [ ] Explore [[David Deutsch]]

## Done

- [x] Fix widget UX
```

No YAML frontmatter. Task syntax: `- [ ] text` (open), `- [x] text` (done). Regex: `^\s*-\s+\[([ xX])\]\s+(.+)$`.
Subtasks: `- [ ]` at deeper indent below the parent task.
Notes: indented non-task lines between a task and its subtasks.
Wikilinks: rendered highlighted (`WikilinkText`) but not tappable here, and not part of any graph.

## In-memory model (`lib/features/tasks/models/task_block.dart`)

The file is parsed into a `TaskNode` tree in memory. The tree is a parsed projection only — the Markdown file remains canonical.

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

**Signature:** `static List<TaskNode> parseNodes(List<String> lines)` — pure, no I/O. Call after `loadLines()`. Shared by `TaskFileScreen` and the read-only Inbox provider; provider code must not implement a rival checkbox parser.

**Top-level scan:**
1. Skip H1 (file title — rendered in AppBar)
2. `##` / `###` → `TaskHeaderNode`
3. Task-regex match → `TaskBlock`; recurse via `_collectBlockContent`
4. Anything else → `TaskProseNode`

**`_collectBlockContent(lines, start, parent) → int`** (private):
- Blank line: look ahead to next non-blank; if its indent ≤ `parent.indentSpaces` → stop; else add blank to `parent.noteLineIndices`
- Non-blank line with indent > `parent.indentSpaces` + task regex → recurse to build child `TaskBlock`
- Non-blank line with indent > `parent.indentSpaces` + no task match → add to `parent.noteLineIndices`
- Header line or indent ≤ `parent.indentSpaces` → stop
- Returns next unconsumed line index

## Storage methods (`lib/features/tasks/services/task_storage_service.dart`)

All-static, all-catch, never throw. Project mutations retain the established `readAsLines() → mutate → writeAsString(join('\n'))` path. Inbox mutations use one exact-byte guarded, staged, flushed, verified, and recoverable replacement path; stage and backup share a transaction ID, preserve BOM and authored newline bytes, and never retry an ambiguous write. Before first creation, a verified sibling marker records the intended canonical bytes; startup accepts a marked canonical only on an exact byte match. Startup also probes mutation siblings and refuses empty creation when recovery material exists.

**Line-level:**
- `loadLines(filePath)` → `List<String>`
- `toggleTask(filePath, lineIndex)` — flip `[ ]` ↔ `[x]` on one line
- `addTask(filePath, text)` — Project behavior: inserts before the first completed root task. Inbox capture uses `guardedAddTask`, which appends without regrouping authored content.
- `deleteTask(filePath, lineIndex)` — remove a single line (task line or note line)
- `updateTaskText(filePath, lineIndex, newText)` — preserve indent + check state, replace text
- `updateLine(filePath, lineIndex, newText)` — raw line replacement; used for inline note editing (caller re-prepends original indentation)

**Block-level:**
- `addNote(filePath, parent, noteText)` — insert at `parent.startLine + 1` with `parent.indentSpaces + 2` indent; multiline text split on `\n`
- `addSubtask(filePath, parent, text)` — insert `'- [ ] text'` at `parent.endLine + 1`, indented one level deeper
- `deleteBlock(filePath, block)` — `removeRange(startLine, endLine + 1)`; removes the full subtree including notes and children
- `updateBlockText(filePath, block, newText)` — thin wrapper over `updateTaskText`
- `toggleBlockAndReorder(filePath, block)` — root Project blocks toggle + reorder; nested blocks always toggle in place so they cannot detach from their parent
- `reorderRootBlocks(filePath, nodes, oldIndex, newIndex)` — drag reorder for root-level blocks
- `renameTaskFile(filePath, newName)` → `String?` — updates the `# heading`, renames the file on disk; null on collision or error

## UI (`lib/features/tasks/screens/task_file_screen.dart`)

Pushed by `ProjectsScreen` for todo-style project files and embedded directly in the Inbox tab. Inbox disables rename and all reordering, supplies its own empty-state/capture wording, loads strict UTF-8, and routes every mutation through the exact-snapshot guarded methods.

**State:** `_lines` (raw file lines — source of truth), `_nodes` (tree, rebuilt on every `_reload()`), `_collapsed` (`Set<int>` of `block.startLine`; session-only, never persisted), plus inline-edit/add state (`_editingLine`, `_editingNoteLine`, `_addingChildOf`, `_addingNoteOf`) cleared on reload.

**Task row layout (left → right):**

```
[Chevron 24px] [Checkbox 32px] [Task Text Expanded] [⋯ More 32px] [⠿ Drag 32px]
```

- Collapse chevron: visible when the block has children or notes; shows a `+N` descendant badge when collapsed
- Checkbox: Project roots use `toggleBlockAndReorder`; Inbox uses guarded in-place toggle
- Task text: `WikilinkText` in display mode (strikethrough + grey when completed); `TextField` in inline edit mode (tap to activate)
- ⋯ More: bottom sheet — Add subtask / Add note / Edit / Delete (confirmed)
- Drag handle: root blocks only; hidden during inline editing

**Render order inside a block:** task row → inline note-add field → existing notes → inline subtask-add field → children (recursive).

**Inline editing:** task text saves on `onSubmitted` and `onTapOutside`. Note editing saves on `onSubmitted` only — no `onTapOutside`, because the note edit row has an inline delete button and a tap-outside save would fire before the delete. Note edits re-prepend the original leading whitespace before writing.

**Completed separation (Projects only):** a centered "Completed" divider is inserted before the first completed root block; `toggleBlockAndReorder` maintains the invariant that completed roots sit at the bottom. Inbox has no divider or regrouping.

**Bottom bar:** persistent `TextField`; `SafeArea(top: false)` handles the gesture nav bar, `resizeToAvoidBottomInset` handles the keyboard. Submitting calls `addTask()`.

**Drag reorder (Projects only):** `ReorderableListView.builder` with `buildDefaultDragHandles: false`; root-level blocks only; `onReorder` adjusts for the "Completed" divider offset, then calls `reorderRootBlocks()`. Inbox passes no drag listener and defensively refuses the callback.

## Boundaries (do not violate)

- `_collapsed` is session-only — never write to Markdown or SharedPreferences
- `parseNodes` is pure — call only after `loadLines()`
- Inbox mutations require the exact loaded snapshot; stale coordinates must reload without retrying
- Inbox completion stays in place and exposes no drag handle or completed divider
- Invalid UTF-8/read failure is an error, never an empty outline
- `deleteBlock` is hard-delete with no trash — task outlines are not identity-bearing
- Do NOT wire task wikilinks into any graph — task files have no identity anchor
- Do NOT add due dates, reminders, recurring tasks, priorities, notifications, or calendar integration
- `TaskBlock.endLine` is computed from the live subtree — do not cache across reloads
