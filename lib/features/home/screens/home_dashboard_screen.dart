import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../../features/entities/models/category.dart';
import '../../../features/entities/models/entity.dart';
import '../../../features/resurface/models/resurface_note.dart';
import '../../../features/resurface/services/graph_scoring_service.dart';
import '../../../features/resurface/services/resurface_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/section_header.dart';

class HomeDashboardScreen extends StatefulWidget {
  final List<Entity> entities;
  final List<Category> categories;
  final VoidCallback onBeginReview;
  final void Function(Entity) onEntityTap;
  final VoidCallback onAddTap;

  const HomeDashboardScreen({
    super.key,
    required this.entities,
    required this.categories,
    required this.onBeginReview,
    required this.onEntityTap,
    required this.onAddTap,
  });

  @override
  State<HomeDashboardScreen> createState() => HomeDashboardScreenState();
}

class HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _problemNoteCount = 0;
  String? _firstCardFront;
  String? _firstCardDeck;
  List<ResurfaceNote> _recentNotes = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> reload() => _loadDashboardData();

  Future<void> _loadDashboardData() async {
    try {
      final vault = await VaultService.getVaultPath();
      if (vault == null || !mounted) return;
      final config = await IntegrationsConfigService.load(vault);
      final notes = await ResurfaceService.getAllNotes(
        vault,
        excludedFolders: config.resurfaceExcludedFolders,
      );

      // Sort by file modification time (newest first) for Recent Notes
      final withStats = <({ResurfaceNote note, DateTime modified})>[];
      for (final note in notes) {
        try {
          final stat = await File(note.sourcePath).stat();
          withStats.add((note: note, modified: stat.modified));
        } catch (_) {
          withStats.add((
            note: note,
            modified: DateTime.fromMillisecondsSinceEpoch(0)
          ));
        }
      }
      withStats.sort((a, b) => b.modified.compareTo(a.modified));

      final problemNotes = notes.where((n) => n.isProblemNote).toList();
      final sortedResult =
          await GraphScoringService.sortByPriority(problemNotes);
      final sortedCards = sortedResult.sorted;

      if (!mounted) return;
      setState(() {
        _problemNoteCount = problemNotes.length;
        _firstCardFront =
            sortedCards.isNotEmpty ? sortedCards.first.front : null;
        _firstCardDeck = sortedCards.isNotEmpty &&
                sortedCards.first.decks.isNotEmpty
            ? sortedCards.first.decks.first
            : 'Default deck';
        _recentNotes = withStats.take(2).map((e) => e.note).toList();
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final worthRevisiting = _worthRevisiting();

    return SafeArea(
      top: false,
      child: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: kFabListBottomPad),
            children: [
              _buildCardPeekHero(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: kScreenHPad),
                child: SectionHeader(title: 'Worth Revisiting'),
              ),
              ..._buildWorthRevisitingRows(worthRevisiting),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: kScreenHPad),
                child: SectionHeader(title: 'Recent Notes'),
              ),
              ..._buildNoteRows(),
            ],
          ),
          // Persistent FAB
          Positioned(
            right: kScreenHPad,
            bottom: kScreenHPad,
            child: GestureDetector(
              onTap: widget.onAddTap,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.33)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add,
                    color: AppColors.accent, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPeekHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kScreenHPad, 16, kScreenHPad, 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.borderMid),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_firstCardFront != null) ...[
              Text(
                _firstCardFront!,
                style: GoogleFonts.ibmPlexSerif(
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Text('✦ ',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.accent)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _firstCardDeck ?? 'Default deck',
                        style: AppTextStyles.bodySmall,
                      ),
                      Text(
                        '$_problemNoteCount problem notes to review',
                        style: AppTextStyles.metaMuted,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: widget.onBeginReview,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Review',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward,
                            size: 14, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<({Entity entity, String reason})> _worthRevisiting() {
    if (widget.entities.isEmpty) return [];
    final now = DateTime.now();

    double entityWeight(Entity e) {
      final days = now
          .difference(DateTime.fromMillisecondsSinceEpoch(e.updatedAt))
          .inDays
          .toDouble();
      final entityScore = e.score ?? 0.0;
      return (entityScore * 0.4) + (days * 0.6);
    }

    String revisitReason(Entity e) {
      final days = now
          .difference(DateTime.fromMillisecondsSinceEpoch(e.updatedAt))
          .inDays;
      final entityScore = e.score ?? 0.0;
      if (days > 7) return 'Not visited in $days days';
      if (entityScore > 7) return 'High rated';
      if (days <= 2) return 'Updated recently';
      return 'Worth another look';
    }

    final sorted = List<Entity>.from(widget.entities)
      ..sort((a, b) => entityWeight(b).compareTo(entityWeight(a)));

    return sorted
        .take(3)
        .map((e) => (entity: e, reason: revisitReason(e)))
        .toList();
  }

  List<Widget> _buildWorthRevisitingRows(
      List<({Entity entity, String reason})> items) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kScreenHPad, vertical: 12),
          child: Text('No entities yet.', style: AppTextStyles.bodySmall),
        ),
      ];
    }
    return items.map((item) {
      final catName = widget.categories
          .firstWhere((c) => c.id == item.entity.categoryId,
              orElse: () => Category(id: '', name: ''))
          .name;
      return GestureDetector(
        onTap: () => widget.onEntityTap(item.entity),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: kScreenHPad, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.entity.name, style: AppTextStyles.entityName),
                    const SizedBox(height: 2),
                    Text(item.reason,
                        style: AppTextStyles.metaMuted),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (catName.isNotEmpty)
                Text(catName, style: AppTextStyles.bodySmall),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildNoteRows() {
    if (_recentNotes.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: kScreenHPad, vertical: 12),
          child: Text(
            _loaded ? 'No notes found.' : 'Loading…',
            style: AppTextStyles.bodySmall,
          ),
        ),
      ];
    }
    return _recentNotes.map((note) {
      final filename = p.basenameWithoutExtension(note.sourceFile);
      final deck = note.decks.isNotEmpty ? note.decks.first : '';
      return Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: kScreenHPad, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filename, style: AppTextStyles.entityName),
                  if (deck.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(deck, style: AppTextStyles.bodySmall),
                  ],
                ],
              ),
            ),
            if (note.isProblemNote)
              Text(
                '✦',
                style: AppTextStyles.meta
                    .copyWith(color: AppColors.accent, fontSize: 12),
              ),
          ],
        ),
      );
    }).toList();
  }

}
