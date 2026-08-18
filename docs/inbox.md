# Inbox

## Contract

Inbox is one persistent, deliberately low-structure file:

```
Interesting/Inbox.md
```

`InboxStorageService.ensureInbox()` creates it as `# Inbox` only when absent and never rebuilds, migrates, renames, or deletes an existing file. The Inbox tab embeds the existing `TaskFileScreen`, so capture, optional attached prose, nesting, completion, and editing all use `TaskStorageService` rather than another syntax.

An entry has only what was authored:

```markdown
- [ ] Read Wheeler
  Manhattan Project, Oppenheimer, and scientific culture.
```

The checkbox supplies open/closed state. Indented prose is free context. There are no action/open-thread types, priorities, dates, inferred classifications, or stable IDs.

Inbox keeps authored position: completion toggles in place, there is no drag reordering or completed-section regrouping, and headings are never crossed mechanically. Nested completion also toggles only its checkbox, so a child cannot detach from its parent.

Every Inbox write uses the exact UTF-8 bytes loaded by the editor as a precondition. If any external edit changes that snapshot, Interest refuses the write, shows that the Inbox changed outside Interest, and reloads rather than acting on stale line coordinates. A replacement is written and flushed to a same-directory stage, byte-verified, and installed only after a second exact precondition check. The previous file is moved to a byte-verified recovery sibling before installation and removed only after the installed bytes verify. A failed install restores that recovery copy only while no canonical Inbox has reappeared; otherwise Interest preserves both, reports an indeterminate outcome with the recovery path, and reloads without retrying. UTF-8 BOM presence and authored line-ending bytes are retained. Missing, unreadable, or invalid-UTF-8 content is an error state rather than an empty Inbox. Project files retain their existing root-task ordering behavior.

Dart's cross-platform file API does not provide an atomic compare-and-swap replacement. The final byte check, target move, target-absence check, and stage move therefore retain a small cross-process race, especially around Windows/editor rename saves. Staging prevents a direct truncating write and recovery makes ordinary I/O failure repairable, but it does not justify claiming atomicity or crash-proof directory metadata. If another process is observed to have recreated the canonical path, Interest never deliberately overwrites it with the recovery copy.

Stage and backup siblings share one owned transaction ID. On restart, `InboxStorageService` probes those siblings before creating a missing canonical file. Because Dart cannot restore the backup with no replace race, startup fails closed: one readable coherent transaction is reported as recoverable with its exact artifact paths, while multiple, malformed, or unreadable artifacts are reported as blocked. Neither case creates an empty Inbox or deletes recovery material.

First creation has its own flushed and byte-verified sibling marker containing the exact intended `# Inbox` bytes. Only after that marker exists does Interest exclusively create the canonical path and append, flush, and verify those bytes without a truncating write. The marker remains until verification. On restart, a marker with an absent, empty, partial, or otherwise nonmatching canonical blocks opening/creation and surfaces both paths. A marker with an exact canonical is the only completed creation state: startup accepts the canonical and removes only that marker. A mutation backup never replaces an existing canonical Inbox during startup.

## Read-only provider

Run:

```
dart run tool/query_open_inbox.dart --vault <vault-path> [--pretty]
```

`OpenInboxQueryService` reads the exact Inbox file through `TaskStorageService.parseNodes()` and returns unchecked items as JSON. It adds transient retrieval context only: source line, indentation, headings, parent items, completed-ancestor state, attached prose, observation time, and source modification time.

Provider scope is deliberately closed:

- Included: `Interesting/Inbox.md`
- Not scanned: Projects, `To Do List.md`, root notes, logs, and every other vault file or checkbox
- Missing/unreadable Inbox: `status: unavailable`, with a limitation; the provider remains read-only and does not create it
- File changes during observation: two bounded exact-byte/stat observations are attempted; if neither is coherent, `status: indeterminate`, no records, and no source modification timestamp are returned
- Empty existing Inbox: `status: complete`, `records: []`

The JSON result records provider, capability, status, completeness, freshness, included scope, and outside-scope handling. A caller may relate or structure entries transiently, but must not write inferred semantics back to the Inbox.
