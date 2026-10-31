# Tasks subsystem (parser + outline editor)

## Role

The Tasks subsystem is the **shared checkbox-outline layer used by Inbox and Projects**. It owns the Markdown task syntax (`- [ ]` / `- [x]`, indentation, attached notes), the pure parser that turns file lines into a block tree, snapshot-guarded line/block transforms, and `TaskFileScreen`.

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

Todo outlines require no frontmatter. Existing metadata and fenced examples are preserved as prose rather than interpreted as tasks. Task syntax: `- [ ] text` (open), `- [x] text` (done). Regex: `^\s*-\s+\[([ xX])\]\s+(.+)$`.
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

**Signature:** `static List<TaskNode> parseNodes(List<String> lines)` — pure, no I/O. Call with `MarkdownFile.loadSnapshot().lines`. Shared by `TaskFileScreen` and the read-only Inbox provider; provider code must not implement a rival checkbox parser.

**Top-level scan:**
1. Metadata and fenced lines → `TaskProseNode`, using shared `unfencedBodyLines` eligibility
2. Skip H1 (file title — rendered in AppBar)
3. `##` / `###` → `TaskHeaderNode`
4. Task-regex match → `TaskBlock`; recurse via `_collectBlockContent`
5. Anything else → `TaskProseNode`

**`_collectBlockContent(lines, start, parent) → int`** (private):
- Blank line: look ahead to next non-blank; if its indent ≤ `parent.indentSpaces` → stop; else add blank to `parent.noteLineIndices`
- Non-blank line with indent > `parent.indentSpaces` + task regex → recurse to build child `TaskBlock`
- Non-blank line with indent > `parent.indentSpaces` + no task match → add to `parent.noteLineIndices`
- Header line or indent ≤ `parent.indentSpaces` → stop
- Returns next unconsumed line index

## Mutations (`TaskStorageService`)

Every method below receives the exact loaded `TaskFileSnapshot` and returns a
`GuardedTaskMutationResult`. Both Inbox and Project outlines use these methods;
the task service supplies line/block transforms to the shared file boundary.

| Method | Transform |
| --- | --- |
| `guardedAddTask` | Append an open root task; do not regroup existing content. |
| `guardedToggleBlock` | Toggle a checkbox. With `reorderRoot: true`, move a Project root block; nested and Inbox blocks stay in place. |
| `guardedUpdateBlockText` | Replace a task's text, preserving indentation and checkbox state. |
| `guardedDeleteBlock` | Remove the selected subtree, including its attached notes and children. |
| `guardedAddNote` | Insert indented note lines immediately after the parent task line. |
| `guardedAddSubtask` | Insert a child after the parent's current subtree. |
| `guardedUpdateLine` / `guardedDeleteLine` | Change or remove one selected line. The editor retains note indentation when replacing text. |
| `guardedReorderRootBlocks` | Move a Project root block among the current nodes; Inbox exposes no reorder surface. |

Loading and title/filename rename belong to `MarkdownFile`, not this service.
The former `loadLines` and unguarded file-writing methods have been removed.

## UI (`lib/features/tasks/screens/task_file_screen.dart`)

Pushed by `ProjectsScreen` for todo-style project files and embedded directly in the Inbox tab. Inbox disables rename and all reordering, supplies its own empty-state/capture wording, loads strict UTF-8, and routes every mutation through the exact-snapshot guarded methods.

**State:** `_lines` (raw file lines — source of truth), `_nodes` (tree, rebuilt on every `_reload()`), `_collapsed` (`Set<int>` of `block.startLine`; session-only, never persisted), plus inline-edit/add state (`_editingLine`, `_editingNoteLine`, `_addingChildOf`, `_addingNoteOf`) cleared on reload.

**Task row layout (left → right):**

```
[Chevron 24px] [Checkbox 32px] [Task Text Expanded] [⋯ More 32px] [⠿ Drag 32px]
```

- Collapse chevron: visible when the block has children or notes; shows a `+N` descendant badge when collapsed
- Checkbox: Project roots use `guardedToggleBlock(reorderRoot: true)`; Inbox uses guarded in-place toggle
- Task text: `WikilinkText` in display mode (strikethrough + grey when completed); `TextField` in inline edit mode (tap to activate)
- ⋯ More: bottom sheet — Add subtask / Add note / Edit / Delete (confirmed)
- Drag handle: root blocks only; hidden during inline editing

**Render order inside a block:** task row → inline note-add field → existing notes → inline subtask-add field → children (recursive).

**Inline editing:** task text saves on `onSubmitted` and `onTapOutside`. Note editing saves on `onSubmitted` only — no `onTapOutside`, because the note edit row has an inline delete button and a tap-outside save would fire before the delete. Note edits re-prepend the original leading whitespace before writing.

**Completed separation (Projects only):** a centered "Completed" divider precedes the first completed root block. Root completion uses `guardedToggleBlock(reorderRoot: true)`; nested completion stays in place. New root tasks append without regrouping existing content. Inbox has no divider or regrouping.

**Bottom bar:** persistent `TextField`; `SafeArea(top: false)` handles the gesture nav bar, `resizeToAvoidBottomInset` handles the keyboard. Submitting calls `guardedAddTask`.

**Drag reorder (Projects only):** `ReorderableListView.builder` with `buildDefaultDragHandles: false`; root-level blocks only; `onReorder` adjusts for the "Completed" divider offset, then calls `guardedReorderRootBlocks`. Inbox passes no drag listener and defensively refuses the callback.

## Boundaries (do not violate)

- `_collapsed` is session-only — never write to Markdown or SharedPreferences
- `parseNodes` is pure — pass the exact loaded snapshot lines
- Inbox mutations require the exact loaded snapshot; stale coordinates must reload without retrying
- Inbox completion stays in place and exposes no drag handle or completed divider
- Invalid UTF-8/read failure is an error, never an empty outline
- `deleteBlock` is hard-delete with no trash — task outlines are not identity-bearing
- Do NOT wire task wikilinks into any graph — task files have no identity anchor
- Do NOT add due dates, reminders, recurring tasks, priorities, notifications, or calendar integration
- `TaskBlock.endLine` is computed from the live subtree — do not cache across reloads

## Shared file boundary

`lib/shared/markdown/markdown_file.dart` owns strict `loadSnapshot` observations,
unchanged-source preconditions, staged/flushed/verified replacement, recovery
observation and guarded `renameTaskFile`. It preserves unrelated source text,
BOM and line endings. Stale or ambiguous results are visible and never retried
automatically; this recoverable transaction is not an atomic cross-process CAS.

Task outlines and flat-list Project edits use this same boundary. Their modules
own syntax and semantic transforms rather than rival filesystem writers.
After each attempt the editors reload; after a successful rename they adopt the
returned path before further editing. Inbox startup and first-creation recovery
have additional responsibilities owned by `InboxStorageService`; see
[Inbox](inbox.md). Project file creation/deletion retain the legacy contracts
documented in [Projects](projects.md#projectstorageservice).
