# Project

Flutter mobile app — local-only entity tracker. See README.md for full architecture, data model, navigation patterns, and run instructions.

## Key constraints — must not be violated

- No state management libraries (`setState` only)
- No database — single `entities.json` file, overwritten on every mutation
- No auth, no cloud, no network calls
- `id` (entity, category, board) is immutable after creation; never regenerate it on rename
- `updated_at` must be stamped on every entity mutation — done inside `_save()` in `entity_screen.dart`
- Deleting an entity must also remove its `entity_links` and `board_entities` entries — done in `_deleteEntity` in `home_screen.dart`
- Deleting a board must also remove its `board_entities` entries — done in `_deleteBoard` in `home_screen.dart`
- In `entity_screen.dart`, core field mutations (name, category, tags, score, notes, links) do **not** call `_save()` individually — save is deferred to the explicit Save button via `_saveEdit()`. Only join-table mutations (`_addToBoard`, `_removeFromBoard`, `_createEntityLink`, `_deleteEntityLink`) call `_save()` immediately. Do not add auto-save calls to core field methods.
- `Entity.copyWith()` exists for deep copy — use it when snapshotting entity state (e.g. edit mode enter/cancel in `entity_screen.dart`)

## Current screen map

```
home_screen.dart         — BottomNavigationBar shell (Entities tab + Boards tab via IndexedStack); owns board CRUD inline
entity_screen.dart       — display mode / edit mode; deferred save pattern; see README for detail
board_detail_screen.dart — board members; sort (6 options); FAB to add entities; self-contained
export_screen.dart       — export JSON/MD/TXT + import JSON (merge or replace); self-contained
boards_screen.dart       — DEAD CODE: superseded by Boards tab in home_screen.dart; do not navigate to it
```

## Approach

Reject blind empiricism and use only explanatory arguments to draw conclusions.
I follow Karl Popper and David Deutsch in epistemology, physics, politics, and related things.

Treat my ideas as conjectures in an evolving theory.

Edison said: research is one per cent inspiration and ninety-nine per cent perspiration.

Based on what knowledge, understanding, and explanations I have provided you, your role is to do the *perspiration*:

- Draw out implications as much as you can
- Make hidden assumptions explicit
- Propagate consequences across the entire framework
- Keep the answers hard-to-vary and avoid redundancy

During the above mentioned process, if something seems to come in conflict in the knowledge you have:

- state conflicts clearly as precise problems or questions, that is way better than your opinions/advice

Don't provide opinions and elongated ramblings.

I'll do the inspiration and knowledge creation part and solve those problems.

Work iteratively:

- you: perspiration!
- me: inspiration & knowledge creation, and perspiration when required.
