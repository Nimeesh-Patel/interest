import 'package:path/path.dart' as p;

import '../models/resurface_note.dart';
import '../services/graph_scoring_service.dart';
import '../services/traversal_log_service.dart';

/// Fires recordTraversal + updateGraphScores for each note shown.
/// Instantiated when a deck opens; disposal is implicit (no resources held).
class TraversalSession {
  void record(
    String filename, {
    bool isProblemNote = false,
    double? scheduledInterval,
  }) {
    TraversalLogService.recordTraversal(
      filename,
      isProblemNote: isProblemNote,
      scheduledInterval: scheduledInterval,
    );
    GraphScoringService.updateGraphScores(filename);
  }
}

/// Plain-class controller owning the card viewer queue, position, no-repeat
/// tracking, and per-note reload/removal. All mutating methods are designed
/// to be called from within the parent's setState(), which triggers rebuilds.
class CardViewerController {
  final TraversalSession session = TraversalSession();

  List<ResurfaceNote> _notes = [];
  int _index = 0;
  bool _backRevealed = false;
  String? _lastShownFilename;
  Map<String, double> _priorities = {};

  // ── Getters ────────────────────────────────────────────────────────────────

  List<ResurfaceNote> get notes => _notes;
  int get index => _index;
  bool get backRevealed => _backRevealed;
  bool get isEmpty => _notes.isEmpty;
  ResurfaceNote? get current => _notes.isEmpty ? null : _notes[_index];

  // ── Deck loading ───────────────────────────────────────────────────────────

  /// Sets up the viewer with [sorted] notes and records the first note shown.
  /// Call from within parent setState.
  void load(List<ResurfaceNote> sorted, Map<String, double> priorities) {
    _notes = List<ResurfaceNote>.from(sorted);
    _priorities = Map<String, double>.from(priorities);
    _index = 0;
    _backRevealed = false;
    if (_notes.isNotEmpty) {
      final firstName = p.basenameWithoutExtension(_notes.first.sourceFile);
      _lastShownFilename = firstName;
      session.record(
        firstName,
        isProblemNote: _notes.first.isProblemNote,
        scheduledInterval: _priorities[firstName],
      );
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  /// Advances to the next card with no-repeat logic; records the traversal.
  /// Call from within parent setState.
  void goNext() {
    if (_index >= _notes.length - 1) return;
    final nextIdx = _index + 1;
    final nextName = p.basenameWithoutExtension(_notes[nextIdx].sourceFile);
    // No-repeat: defer the next note by one position when it was just shown.
    if (nextName == _lastShownFilename && nextIdx + 1 < _notes.length) {
      final skipped = _notes.removeAt(nextIdx);
      _notes.insert(nextIdx + 1, skipped);
    }
    _index = nextIdx;
    _backRevealed = false;
    final note = _notes[_index];
    final filename = p.basenameWithoutExtension(note.sourceFile);
    _lastShownFilename = filename;
    session.record(filename,
        isProblemNote: note.isProblemNote,
        scheduledInterval: _priorities[filename]);
  }

  /// Steps back one card and records the traversal. Call from within parent setState.
  void goPrev() {
    if (_index <= 0) return;
    _index--;
    _backRevealed = false;
    final note = _notes[_index];
    final filename = p.basenameWithoutExtension(note.sourceFile);
    _lastShownFilename = filename;
    session.record(filename,
        isProblemNote: note.isProblemNote,
        scheduledInterval: _priorities[filename]);
  }

  /// Toggles back-side visibility. Call from within parent setState.
  void toggleBack() => _backRevealed = !_backRevealed;

  /// Resets back-side visibility without recording. Call from within parent setState.
  void resetBackRevealed() => _backRevealed = false;

  // ── Note lifecycle ─────────────────────────────────────────────────────────

  /// Replaces the note at [idx]. Call from within parent setState.
  void reloadNote(int idx, ResurfaceNote updated) => _notes[idx] = updated;

  /// Removes the note at [idx] and clamps the index. Call from within parent setState.
  void removeAt(int idx) {
    _notes.removeAt(idx);
    _index = _index.clamp(0, (_notes.length - 1).clamp(0, 1 << 30));
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  /// Clears all viewer state. Call from within parent setState.
  void reset() {
    _notes = [];
    _index = 0;
    _backRevealed = false;
    _lastShownFilename = null;
    _priorities = {};
  }
}
