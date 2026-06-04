import 'dart:math' as math;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/resurface_note.dart';
import 'resurface_service.dart';
import 'review_log_service.dart';

const double kBaseBoost = 1.0;
const double kDecayLambda = 0.1;
const double kNoiseThresholdShort = 10.0;
const double kNoiseThresholdMedium = 60.0;
const double kNoiseLongFraction = 0.05;

class GraphScoringService {
  static double decayedScore(double rawScore, DateTime? lastBoosted) {
    if (lastBoosted == null) return 0.0;
    final days = DateTime.now().difference(lastBoosted).inDays.toDouble();
    return rawScore * math.exp(-kDecayLambda * days);
  }

  static double _maxParentScore(
    List<String> activatedBy,
    Map<
            String,
            ({
              double graphScore,
              String? lastBoosted,
              DateTime? lastReviewed,
              List<String> activatedBy,
              bool isProblemNote,
              double? scheduledInterval,
            })>
        log,
  ) {
    if (activatedBy.isEmpty) return 0.0;
    var best = 0.0;
    for (final parentName in activatedBy) {
      final e = log[parentName];
      if (e == null) continue;
      final score = decayedScore(
        e.graphScore,
        e.lastBoosted != null ? DateTime.tryParse(e.lastBoosted!) : null,
      );
      if (score > best) best = score;
    }
    return best;
  }

  static Future<void> updateGraphScores(String reviewedNoteFilename) async {
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (vaultPath == null) return;

      final settings = await ReviewLogService.loadSettings();
      final minDeg = settings.minDegree;
      final maxDeg = settings.maxDegree;

      final notes = await ResurfaceService.getAllNotes(vaultPath);

      final graph = <String, Set<String>>{};
      final isProblemNoteMap = <String, bool>{};
      for (final note in notes) {
        final key = noteKey(note.sourceFile);
        graph[key] = extractWikilinks(note.body).map((t) => t.toLowerCase()).toSet();
        isProblemNoteMap[key] = note.isProblemNote;
      }

      final reviewed = noteKey(reviewedNoteFilename);

      // BFS up to maxDeg; collect nodes keyed by exact hop distance.
      final hopNodes = <int, Set<String>>{};
      final visited = <String>{reviewed};
      var frontier = <String>{reviewed};
      for (var d = 1; d <= maxDeg; d++) {
        final next = <String>{};
        for (final node in frontier) {
          for (final nbr in (graph[node] ?? <String>{})) {
            if (!visited.contains(nbr)) {
              visited.add(nbr);
              next.add(nbr);
            }
          }
        }
        if (next.isEmpty) break;
        hopNodes[d] = next;
        frontier = next;
      }

      if (hopNodes.isEmpty) return;

      final log = await ReviewLogService.loadFullLog();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final scoreUpdates =
          <String, ({double rawScore, String lastBoosted, bool isProblemNote})>{};
      final activationTargets = <String, bool>{};

      for (final entry in hopNodes.entries) {
        final d = entry.key;
        for (final key in entry.value) {
          final isProblemNoteFlag = isProblemNoteMap[key] ?? false;
          final existing = log[key]?.graphScore ?? 0.0;
          scoreUpdates[key] = (
            rawScore: existing + kBaseBoost / d,
            lastBoosted: today,
            isProblemNote: isProblemNoteFlag,
          );
          if (d >= minDeg) {
            activationTargets[key] = isProblemNoteFlag;
          }
        }
      }

      if (scoreUpdates.isNotEmpty) {
        final activations = <String, List<String>>{
          for (final key in activationTargets.keys) key: [reviewed],
        };
        await ReviewLogService.updateGraphState(
          vaultPath,
          GraphStateUpdate(scores: scoreUpdates, activations: activations),
        );
      }
    } catch (_) {}
  }

  static Future<({List<ResurfaceNote> sorted, Map<String, double> priorities})>
      sortByPriority(
    List<ResurfaceNote> notes,
  ) async {
    try {
      final log = await ReviewLogService.loadFullLog();
      final today = DateTime.now();
      const neverReviewedDays = 365.0;
      final rng = math.Random();

      final preNoisePriorities = <String, double>{};
      final sortPriorities = <String, double>{};

      for (final note in notes) {
        final key = noteKey(note.sourceFile);
        final e = log[key];

        final rawDays = e?.lastReviewed != null
            ? today.difference(e!.lastReviewed!).inDays.toDouble()
            : neverReviewedDays;

        // Late-penalty cap: if note is reviewed much later than its scheduled
        // interval, cap effective days to avoid permanent queue dominance.
        final scheduledInterval = e?.scheduledInterval;
        final effectiveDays = (scheduledInterval != null &&
                e?.lastReviewed != null &&
                rawDays > scheduledInterval * 1.5)
            ? scheduledInterval * 1.5
            : rawDays;

        final scoreTerm = note.isProblemNote
            ? decayedScore(
                e?.graphScore ?? 0.0,
                e?.lastBoosted != null
                    ? DateTime.tryParse(e!.lastBoosted!)
                    : null,
              )
            : _maxParentScore(e?.activatedBy ?? <String>[], log);

        final preNoise = effectiveDays + scoreTerm;
        preNoisePriorities[key] = preNoise;

        // Noise: prevent pile-ups when many notes have similar staleness.
        // Threshold uses rawDays (actual elapsed time, not capped).
        double noise;
        if (rawDays <= kNoiseThresholdShort) {
          noise = rng.nextDouble() > 0.5 ? 1.0 : 0.0;
        } else if (rawDays <= kNoiseThresholdMedium) {
          noise = -3.0 + rng.nextDouble() * 6.0;
        } else {
          noise = rawDays * (rng.nextDouble() * 0.10 - kNoiseLongFraction);
        }
        sortPriorities[key] = preNoise + noise;
      }

      final sorted = List.of(notes)
        ..sort((a, b) {
          final pa = sortPriorities[noteKey(a.sourceFile)] ?? 0.0;
          final pb = sortPriorities[noteKey(b.sourceFile)] ?? 0.0;
          return pb.compareTo(pa);
        });

      return (sorted: sorted, priorities: preNoisePriorities);
    } catch (_) {
      return (sorted: notes, priorities: <String, double>{});
    }
  }
}
