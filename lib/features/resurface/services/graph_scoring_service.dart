import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/markdown/md_utils.dart';
import '../models/resurface_note.dart';
import 'resurface_service.dart';
import 'review_log_service.dart';

const double kBaseBoost = 1.0;
const double kDecayLambda = 0.1;

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
              bool isStar,
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
      final normalToOrig = <String, String>{};
      final isStarMap = <String, bool>{};
      for (final note in notes) {
        final orig = p.basenameWithoutExtension(note.sourceFile);
        final key = orig.toLowerCase();
        normalToOrig[key] = orig;
        graph[key] = extractWikilinks(note.body).map((t) => t.toLowerCase()).toSet();
        isStarMap[key] = note.hasCard;
      }

      final reviewed = reviewedNoteFilename.toLowerCase();

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
          <String, ({double rawScore, String lastBoosted, bool isStar})>{};
      final activationTargets = <String, bool>{};

      for (final entry in hopNodes.entries) {
        final d = entry.key;
        for (final key in entry.value) {
          final orig = normalToOrig[key] ?? key;
          final isStar = isStarMap[key] ?? false;
          final existing = log[orig]?.graphScore ?? 0.0;
          scoreUpdates[orig] = (
            rawScore: existing + kBaseBoost / d,
            lastBoosted: today,
            isStar: isStar,
          );
          if (d >= minDeg) {
            activationTargets[orig] = isStar;
          }
        }
      }

      if (scoreUpdates.isNotEmpty) {
        await ReviewLogService.patchGraphScores(scoreUpdates);
      }
      if (activationTargets.isNotEmpty) {
        await ReviewLogService.activateNotes(reviewedNoteFilename, activationTargets);
      }
    } catch (_) {}
  }

  static Future<List<ResurfaceNote>> sortByPriority(
    List<ResurfaceNote> notes,
  ) async {
    try {
      final log = await ReviewLogService.loadFullLog();
      final today = DateTime.now();
      const neverReviewedDays = 365.0;
      final sorted = List.of(notes)
        ..sort((a, b) {
          final keyA = p.basenameWithoutExtension(a.sourceFile);
          final keyB = p.basenameWithoutExtension(b.sourceFile);
          final ea = log[keyA];
          final eb = log[keyB];
          final daysA = ea?.lastReviewed != null
              ? today.difference(ea!.lastReviewed!).inDays.toDouble()
              : neverReviewedDays;
          final daysB = eb?.lastReviewed != null
              ? today.difference(eb!.lastReviewed!).inDays.toDouble()
              : neverReviewedDays;
          final prioA = daysA +
              (a.hasCard
                  ? decayedScore(
                      ea?.graphScore ?? 0.0,
                      ea?.lastBoosted != null
                          ? DateTime.tryParse(ea!.lastBoosted!)
                          : null,
                    )
                  : _maxParentScore(ea?.activatedBy ?? <String>[], log));
          final prioB = daysB +
              (b.hasCard
                  ? decayedScore(
                      eb?.graphScore ?? 0.0,
                      eb?.lastBoosted != null
                          ? DateTime.tryParse(eb!.lastBoosted!)
                          : null,
                    )
                  : _maxParentScore(eb?.activatedBy ?? <String>[], log));
          return prioB.compareTo(prioA);
        });
      return sorted;
    } catch (_) {
      return notes;
    }
  }
}
