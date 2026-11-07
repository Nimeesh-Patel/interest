import 'package:flutter/material.dart';

import '../../shared/constants/app_text_styles.dart';
import '../../shared/constants/app_theme.dart';
import '../anki/services/anki_sync_service.dart';

/// One card that needs Nimeesh's decision, in the form the pager shows it.
class Decision {
  final int id;
  final String title;
  final String reason;
  final IconData reasonIcon;
  final Color tone;
  final String deck;

  /// Null when the card is not in this collection, so it has no history here.
  final int? reviews;
  final DateTime created;
  final String problem;
  final String conjecture;
  final String keepLabel;
  final String actLabel;
  final bool destructive;
  final AnkiOrphanCard? orphan;
  final AnkiMissingCard? missing;

  const Decision._({
    required this.id,
    required this.title,
    required this.reason,
    required this.reasonIcon,
    required this.tone,
    required this.deck,
    required this.reviews,
    required this.created,
    required this.problem,
    required this.conjecture,
    required this.keepLabel,
    required this.actLabel,
    required this.destructive,
    this.orphan,
    this.missing,
  });

  factory Decision.orphan(AnkiOrphanCard card) => Decision._(
    id: card.ankiNoteId,
    title: card.title,
    reason: 'This card has no Obsidian note',
    reasonIcon: Icons.link_off_rounded,
    tone: AppColors.danger,
    deck: card.decks.isEmpty ? 'No deck' : card.decks.join(', '),
    reviews: card.reviews,
    created: card.created,
    problem: card.problem,
    conjecture: card.conjecture,
    keepLabel: 'Keep',
    actLabel: 'Remove',
    destructive: true,
    orphan: card,
  );

  factory Decision.missing(AnkiMissingCard item, String target) => Decision._(
    id: item.ankiNoteId,
    title: item.title,
    reason: "This note's card is missing from $target",
    reasonIcon: Icons.help_outline_rounded,
    tone: AppColors.warning,
    deck: item.deck,
    reviews: null,
    created: DateTime.fromMillisecondsSinceEpoch(item.ankiNoteId),
    problem: item.problem,
    conjecture: item.conjecture,
    keepLabel: 'Not now',
    actLabel: 'Re-create',
    destructive: false,
    missing: item,
  );
}

/// Swipeable decisions, one card per page. The next card peeks in from the
/// edge so it is obvious there is more than one; deciding a card moves on.
class DecisionPager extends StatefulWidget {
  final List<Decision> decisions;

  /// Ids whose decision is currently being applied.
  final Set<int> busy;
  final void Function(Decision) onKeep;
  final void Function(Decision) onAct;

  const DecisionPager({
    super.key,
    required this.decisions,
    required this.busy,
    required this.onKeep,
    required this.onAct,
  });

  @override
  State<DecisionPager> createState() => _DecisionPagerState();
}

class _DecisionPagerState extends State<DecisionPager> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void didUpdateWidget(DecisionPager old) {
    super.didUpdateWidget(old);
    final last = widget.decisions.length - 1;
    if (_page > last && last >= 0) {
      _page = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) _controller.jumpToPage(_page);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final decisions = widget.decisions;
    final count = decisions.length;
    final current = decisions[_page.clamp(0, count - 1)];
    final busy = widget.busy.contains(current.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count == 1
                      ? 'One card needs your decision'
                      : '$count cards need your decision',
                  style: AppTextStyles.heading,
                ),
              ),
              if (count > 1) ...[
                IconButton(
                  tooltip: 'Previous card',
                  onPressed: _page > 0 ? () => _go(_page - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('${_page + 1} of $count', style: AppTextStyles.small),
                IconButton(
                  tooltip: 'Next card',
                  onPressed: _page < count - 1 ? () => _go(_page + 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        SizedBox(
          height: 470,
          child: PageView.builder(
            controller: _controller,
            itemCount: count,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder:
                (_, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _DecisionCard(decision: decisions[index]),
                ),
          ),
        ),
        if (count > 1) ...[
          const SizedBox(height: Space.md),
          _Dots(count: count, active: _page),
        ],
        const SizedBox(height: Space.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => widget.onKeep(current),
                  child: Text(current.keepLabel),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: FilledButton(
                  style:
                      current.destructive
                          ? FilledButton.styleFrom(
                            backgroundColor: AppColors.dangerTint,
                            foregroundColor: AppColors.danger,
                            minimumSize: const Size.fromHeight(48),
                          )
                          : FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                  onPressed: busy ? null : () => widget.onAct(current),
                  child:
                      busy
                          ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(current.actLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final Decision decision;
  const _DecisionCard({required this.decision});

  @override
  Widget build(BuildContext context) {
    final d = decision;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl - 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(decision: d),
            const SizedBox(height: Space.lg),
            Expanded(
              child: _Sides(decision: d, problemLines: 4, conjectureLines: 3),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _showFullCard(context, d),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('Read the full card'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showFullCard(BuildContext context, Decision d) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.raised,
    builder:
        (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder:
              (_, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.xxl,
                ),
                children: [
                  _CardHeader(decision: d),
                  const SizedBox(height: Space.lg),
                  _Sides(decision: d),
                ],
              ),
        ),
  );
}

class _CardHeader extends StatelessWidget {
  final Decision decision;
  const _CardHeader({required this.decision});

  @override
  Widget build(BuildContext context) {
    final d = decision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(d.reasonIcon, size: 18, color: d.tone),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                d.reason,
                style: AppTextStyles.smallStrong.copyWith(color: d.tone),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Text(d.title, style: AppTextStyles.heading),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            _Fact(icon: Icons.style_outlined, label: d.deck),
            _Fact(
              icon: Icons.history_rounded,
              label: switch (d.reviews) {
                null => 'Not on this device',
                0 => 'Never reviewed',
                1 => 'Reviewed once',
                final n => 'Reviewed $n times',
              },
            ),
            _Fact(icon: Icons.event_outlined, label: _date(d.created)),
          ],
        ),
      ],
    );
  }
}

/// The author's two sides, in the author's serif voice, divided by the same
/// *** that divides them in the note. Line limits make a preview; without
/// them it is the whole card.
class _Sides extends StatelessWidget {
  final Decision decision;
  final int? problemLines;
  final int? conjectureLines;

  const _Sides({
    required this.decision,
    this.problemLines,
    this.conjectureLines,
  });

  @override
  Widget build(BuildContext context) {
    final problem = decision.problem.trim();
    final conjecture = decision.conjecture.trim();
    final preview = problemLines != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          problem.isEmpty ? 'No problem written yet' : problem,
          style: AppTextStyles.problem,
          maxLines: problemLines,
          overflow: preview ? TextOverflow.ellipsis : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          child: Center(
            child: Text(
              '*   *   *',
              style: AppTextStyles.smallStrong.copyWith(
                color: AppColors.accent,
              ),
            ),
          ),
        ),
        Text(
          conjecture.isEmpty ? 'No conjecture yet' : conjecture,
          style: AppTextStyles.conjecture,
          maxLines: conjectureLines,
          overflow: preview ? TextOverflow.ellipsis : null,
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Fact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      // `line` stays visible on both the card and the raised sheet.
      color: AppColors.line,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.inkMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.small.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;
  const _Dots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == active ? AppColors.accent : AppColors.outline,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'today';
  }
  final day = '${d.day} ${_months[d.month - 1]}';
  return d.year == now.year ? day : '$day ${d.year}';
}
