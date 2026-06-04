import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';

typedef _RawEntry = ({
  String note,
  String? lastReviewed,
  double graphScore,
  String? lastBoosted,
  List<String> activatedBy,
  bool isProblemNote,
  double? scheduledInterval,
});

typedef _LogData = ({
  int minDegree,
  int maxDegree,
  List<_RawEntry> entries,
});

/// Typed payload for a single atomic graph-state write.
/// All map keys must use [noteKey] notation (lowercase basename).
class GraphStateUpdate {
  /// noteKey → (rawScore, lastBoosted ISO string, isProblemNote)
  final Map<String, ({double rawScore, String lastBoosted, bool isProblemNote})> scores;
  /// noteKey → reviewer noteKeys to append to activated_by (deduped on write)
  final Map<String, List<String>> activations;

  const GraphStateUpdate({required this.scores, required this.activations});
}

class ReviewLogService {
  static String _logPath(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'System', 'review_log.md');

  // ── Raw I/O ─────────────────────────────────────────────────────────────────

  static Future<_LogData> _readAll(String vaultPath) async {
    try {
      final file = File(_logPath(vaultPath));
      if (!await file.exists()) return _emptyLog();
      final raw = await file.readAsString();
      final fm = splitFrontmatter(raw).frontmatter;
      if (fm == null) return _emptyLog();
      final yaml = loadYaml(fm);
      if (yaml is! YamlMap) return _emptyLog();

      int minDegree = 2;
      int maxDegree = 3;
      final settings = yaml['settings'];
      if (settings is YamlMap) {
        final mn = settings['min_degree'];
        final mx = settings['max_degree'];
        if (mn is int) minDegree = mn;
        if (mx is int) maxDegree = mx;
      }

      final list = yaml['reviews'];
      final entries = <_RawEntry>[];
      if (list is YamlList) {
        for (final item in list) {
          if (item is! YamlMap) continue;
          final note = item['note'];
          if (note is! String) continue;
          final date = item['last_reviewed'];
          final score = item['graph_score'];
          final boosted = item['last_boosted'];
          final activated = item['activated_by'];
          final rawIsStar = item['is_star']; // YAML key preserved for backward compat
          final scheduledInterval = item['scheduled_interval'];
          entries.add((
            note: note,
            lastReviewed: (date is String) ? date : null,
            graphScore: (score is num) ? score.toDouble() : 0.0,
            lastBoosted: (boosted is String) ? boosted : null,
            activatedBy: (activated is YamlList)
                ? activated.whereType<String>().toList()
                : <String>[],
            isProblemNote: (rawIsStar is bool) ? rawIsStar : false,
            scheduledInterval:
                (scheduledInterval is num) ? scheduledInterval.toDouble() : null,
          ));
        }
      }
      return (minDegree: minDegree, maxDegree: maxDegree, entries: entries);
    } catch (_) {
      return _emptyLog();
    }
  }

  static _LogData _emptyLog() => (minDegree: 2, maxDegree: 3, entries: []);

  static String _serialize(_LogData data) {
    final buf = StringBuffer('---\n');
    buf.writeln('settings:');
    buf.writeln('  min_degree: ${data.minDegree}');
    buf.writeln('  max_degree: ${data.maxDegree}');
    buf.writeln('reviews:');
    for (final e in data.entries) {
      buf.writeln('  - note: "${e.note}"');
      if (e.lastReviewed != null) {
        buf.writeln('    last_reviewed: "${e.lastReviewed}"');
      } else {
        buf.writeln('    last_reviewed: null');
      }
      buf.writeln('    graph_score: ${e.graphScore.toStringAsFixed(4)}');
      if (e.lastBoosted != null) {
        buf.writeln('    last_boosted: "${e.lastBoosted}"');
      }
      if (e.scheduledInterval != null) {
        buf.writeln(
            '    scheduled_interval: ${e.scheduledInterval!.toStringAsFixed(4)}');
      }
      if (e.activatedBy.isEmpty) {
        buf.writeln('    activated_by: []');
      } else {
        buf.writeln('    activated_by:');
        for (final parent in e.activatedBy) {
          buf.writeln('      - "$parent"');
        }
      }
      buf.writeln('    is_star: ${e.isProblemNote}'); // YAML key preserved
    }
    buf.write('---\n');
    return buf.toString();
  }

  // ── Public read methods ──────────────────────────────────────────────────────

  static Future<({int minDegree, int maxDegree})> loadSettings() async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return (minDegree: 2, maxDegree: 3);
      final data = await _readAll(vaultPath);
      return (minDegree: data.minDegree, maxDegree: data.maxDegree);
    } catch (_) {
      return (minDegree: 2, maxDegree: 3);
    }
  }

  static Future<Map<String, DateTime>> loadReviewLog() async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return {};
      final data = await _readAll(vaultPath);
      final map = <String, DateTime>{};
      for (final e in data.entries) {
        if (e.lastReviewed == null) continue;
        try {
          map[noteKey(e.note)] = DateTime.parse(e.lastReviewed!);
        } catch (_) {}
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<
      Map<
          String,
          ({
            double graphScore,
            String? lastBoosted,
            DateTime? lastReviewed,
            List<String> activatedBy,
            bool isProblemNote,
            double? scheduledInterval,
          })>> loadFullLog() async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return {};
      final data = await _readAll(vaultPath);
      final map = <String,
          ({
            double graphScore,
            String? lastBoosted,
            DateTime? lastReviewed,
            List<String> activatedBy,
            bool isProblemNote,
            double? scheduledInterval,
          })>{};
      for (final e in data.entries) {
        try {
          map[noteKey(e.note)] = (
            graphScore: e.graphScore,
            lastBoosted: e.lastBoosted,
            lastReviewed:
                e.lastReviewed != null ? DateTime.tryParse(e.lastReviewed!) : null,
            activatedBy: e.activatedBy,
            isProblemNote: e.isProblemNote,
            scheduledInterval: e.scheduledInterval,
          );
        } catch (_) {}
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  // ── Public write methods ─────────────────────────────────────────────────────

  static Future<void> saveSettings({
    required int minDegree,
    required int maxDegree,
  }) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return;
      final data = await _readAll(vaultPath);
      await File(_logPath(vaultPath)).writeAsString(
        _serialize((
          minDegree: minDegree,
          maxDegree: maxDegree,
          entries: data.entries,
        )),
      );
    } catch (_) {}
  }

  static Future<void> markReviewed(
    String noteFilename, {
    bool isProblemNote = false,
    double? scheduledInterval,
  }) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return;
      final data = await _readAll(vaultPath);
      final entries = data.entries;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final name = noteKey(noteFilename);
      final idx = entries.indexWhere((e) => noteKey(e.note) == name);
      final List<_RawEntry> updated;
      if (idx == -1) {
        updated = [
          ...entries,
          (
            note: name,
            lastReviewed: today,
            graphScore: 0.0,
            lastBoosted: null,
            activatedBy: <String>[],
            isProblemNote: isProblemNote,
            scheduledInterval: scheduledInterval,
          ),
        ];
      } else {
        final existing = entries[idx];
        // Promoted from non-problem-note to problem note: clear activated_by.
        final newActivatedBy =
            (!existing.isProblemNote && isProblemNote) ? <String>[] : existing.activatedBy;
        updated = [
          for (var i = 0; i < entries.length; i++)
            i == idx
                ? (
                    note: name,
                    lastReviewed: today,
                    graphScore: existing.graphScore,
                    lastBoosted: existing.lastBoosted,
                    activatedBy: newActivatedBy,
                    isProblemNote: isProblemNote,
                    scheduledInterval:
                        scheduledInterval ?? existing.scheduledInterval,
                  )
                : entries[i],
        ];
      }
      await File(_logPath(vaultPath)).writeAsString(
        _serialize((
          minDegree: data.minDegree,
          maxDegree: data.maxDegree,
          entries: updated,
        )),
      );
    } catch (_) {}
  }

  static Future<void> patchGraphScores(
    Map<String, ({double rawScore, String lastBoosted, bool isProblemNote})> updates,
  ) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return;
      final data = await _readAll(vaultPath);
      var entries = data.entries;
      for (final kv in updates.entries) {
        final name = noteKey(kv.key);
        final update = kv.value;
        final idx = entries.indexWhere((e) => noteKey(e.note) == name);
        if (idx == -1) {
          entries = [
            ...entries,
            (
              note: name,
              lastReviewed: null,
              graphScore: update.rawScore,
              lastBoosted: update.lastBoosted,
              activatedBy: <String>[],
              isProblemNote: update.isProblemNote,
              scheduledInterval: null,
            ),
          ];
        } else {
          entries = [
            for (var i = 0; i < entries.length; i++)
              i == idx
                  ? (
                      note: name,
                      lastReviewed: entries[idx].lastReviewed,
                      graphScore: update.rawScore,
                      lastBoosted: update.lastBoosted,
                      activatedBy: entries[idx].activatedBy,
                      isProblemNote: update.isProblemNote,
                      scheduledInterval: entries[idx].scheduledInterval,
                    )
                  : entries[i],
          ];
        }
      }
      await File(_logPath(vaultPath)).writeAsString(
        _serialize((
          minDegree: data.minDegree,
          maxDegree: data.maxDegree,
          entries: entries,
        )),
      );
    } catch (_) {}
  }

  static Future<void> removeNote(String noteFilename) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return;
      final data = await _readAll(vaultPath);
      final name = noteKey(noteFilename);
      final updated = data.entries.where((e) => noteKey(e.note) != name).toList();
      await File(_logPath(vaultPath)).writeAsString(
        _serialize((
          minDegree: data.minDegree,
          maxDegree: data.maxDegree,
          entries: updated,
        )),
      );
    } catch (_) {}
  }

  /// Applies [update] (score patches + activation additions) in one read-mutate-write cycle.
  /// Accepts [vaultPath] directly to avoid a redundant VaultService lookup when the
  /// caller already has it.
  static Future<void> updateGraphState(
    String vaultPath,
    GraphStateUpdate update,
  ) async {
    try {
      final data = await _readAll(vaultPath);
      var entries = data.entries;

      // ── Apply score patches ────────────────────────────────────────────────
      for (final kv in update.scores.entries) {
        final name = noteKey(kv.key);
        final u = kv.value;
        final idx = entries.indexWhere((e) => noteKey(e.note) == name);
        if (idx == -1) {
          entries = [
            ...entries,
            (
              note: name,
              lastReviewed: null,
              graphScore: u.rawScore,
              lastBoosted: u.lastBoosted,
              activatedBy: <String>[],
              isProblemNote: u.isProblemNote,
              scheduledInterval: null,
            ),
          ];
        } else {
          entries = [
            for (var i = 0; i < entries.length; i++)
              i == idx
                  ? (
                      note: name,
                      lastReviewed: entries[idx].lastReviewed,
                      graphScore: u.rawScore,
                      lastBoosted: u.lastBoosted,
                      activatedBy: entries[idx].activatedBy,
                      isProblemNote: u.isProblemNote,
                      scheduledInterval: entries[idx].scheduledInterval,
                    )
                  : entries[i],
          ];
        }
      }

      // ── Apply activation additions ─────────────────────────────────────────
      for (final kv in update.activations.entries) {
        final name = noteKey(kv.key);
        final reviewers = kv.value;
        final idx = entries.indexWhere((e) => noteKey(e.note) == name);
        if (idx == -1) {
          final isProblemNoteFlag = update.scores[name]?.isProblemNote ?? false;
          entries = [
            ...entries,
            (
              note: name,
              lastReviewed: null,
              graphScore: 0.0,
              lastBoosted: null,
              activatedBy: reviewers.toList(),
              isProblemNote: isProblemNoteFlag,
              scheduledInterval: null,
            ),
          ];
        } else {
          final existing = entries[idx];
          var newActivatedBy = existing.activatedBy;
          for (final reviewer in reviewers) {
            if (!newActivatedBy.contains(reviewer)) {
              newActivatedBy = [...newActivatedBy, reviewer];
            }
          }
          if (identical(newActivatedBy, existing.activatedBy)) continue;
          entries = [
            for (var i = 0; i < entries.length; i++)
              i == idx
                  ? (
                      note: name,
                      lastReviewed: existing.lastReviewed,
                      graphScore: existing.graphScore,
                      lastBoosted: existing.lastBoosted,
                      activatedBy: newActivatedBy,
                      isProblemNote: existing.isProblemNote,
                      scheduledInterval: existing.scheduledInterval,
                    )
                  : entries[i],
          ];
        }
      }

      await File(_logPath(vaultPath)).writeAsString(
        _serialize((
          minDegree: data.minDegree,
          maxDegree: data.maxDegree,
          entries: entries,
        )),
      );
    } catch (_) {}
  }

  /// Appends [reviewedStarNote] to the `activated_by` list of each note in
  /// [targets] (filename → isProblemNote). Creates entries for notes not yet in the log.
  static Future<void> activateNotes(
    String reviewedStarNote,
    Map<String, bool> targets,
  ) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return;
      final data = await _readAll(vaultPath);
      final reviewer = noteKey(reviewedStarNote);
      var entries = data.entries;
      for (final kv in targets.entries) {
        final name = noteKey(kv.key);
        final isProblemNoteFlag = kv.value;
        final idx = entries.indexWhere((e) => noteKey(e.note) == name);
        if (idx == -1) {
          entries = [
            ...entries,
            (
              note: name,
              lastReviewed: null,
              graphScore: 0.0,
              lastBoosted: null,
              activatedBy: [reviewer],
              isProblemNote: isProblemNoteFlag,
              scheduledInterval: null,
            ),
          ];
        } else {
          final existing = entries[idx];
          if (existing.activatedBy.contains(reviewer)) continue;
          entries = [
            for (var i = 0; i < entries.length; i++)
              i == idx
                  ? (
                      note: name,
                      lastReviewed: existing.lastReviewed,
                      graphScore: existing.graphScore,
                      lastBoosted: existing.lastBoosted,
                      activatedBy: [...existing.activatedBy, reviewer],
                      isProblemNote: isProblemNoteFlag,
                      scheduledInterval: existing.scheduledInterval,
                    )
                  : entries[i],
          ];
        }
      }
      await File(_logPath(vaultPath)).writeAsString(
        _serialize((
          minDegree: data.minDegree,
          maxDegree: data.maxDegree,
          entries: entries,
        )),
      );
    } catch (_) {}
  }
}
