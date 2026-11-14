import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../shared/constants/app_text_styles.dart';
import '../../shared/constants/app_theme.dart';
import '../anki/services/anki_sync_service.dart';

/// One card the pager shows: a card that needs Nimeesh's decision, or a
/// problem that stopped a note (or the whole sync) from syncing.
class Decision {
  final int id;
  final String title;
  final String reason;
  final IconData reasonIcon;
  final Color tone;

  /// Null when unknown, as for a problem whose card was not read.
  final String? deck;

  /// What the card's review history says, or null to leave it out.
  final String? history;

  /// When the card was made, or null when there is no card.
  final DateTime? created;
  final String problem;
  final String conjecture;

  /// What happened and what each choice does, for a problem.
  final String? explanation;

  /// Null labels mean the card offers no choice here: it is fixed in
  /// Obsidian, then synced again.
  final String? keepLabel;
  final String? actLabel;
  final bool destructive;
  final AnkiOrphanCard? orphan;
  final AnkiMissingCard? missing;
  final AnkiSyncIssue? issue;

  /// Vault-relative paths (without `.md`) of the notes involved, each
  /// openable in Obsidian.
  final List<String> notes;

  const Decision._({
    required this.id,
    required this.title,
    required this.reason,
    required this.reasonIcon,
    required this.tone,
    required this.deck,
    required this.history,
    required this.created,
    required this.problem,
    required this.conjecture,
    required this.keepLabel,
    required this.actLabel,
    required this.destructive,
    this.explanation,
    this.orphan,
    this.missing,
    this.issue,
    this.notes = const [],
  });

  bool get hasChoice => keepLabel != null || actLabel != null;

  /// Whether there is card text to show: a problem with an unread card, or
  /// one about a note alone, has none.
  bool get hasSides =>
      problem.trim().isNotEmpty || conjecture.trim().isNotEmpty;

  factory Decision.orphan(AnkiOrphanCard card) {
    final extra = card.noteLinks != null;
    return Decision._(
      id: card.ankiNoteId,
      title: card.title,
      reason:
          extra
              ? 'This note has a second card'
              : 'This card has no Obsidian note',
      reasonIcon: extra ? Icons.copy_all_rounded : Icons.link_off_rounded,
      tone: extra ? AppColors.warning : AppColors.danger,
      deck: card.decks.isEmpty ? 'No deck' : card.decks.join(', '),
      history: _reviewed(card.reviews),
      created: card.created,
      problem: card.problem,
      conjecture: card.conjecture,
      explanation:
          extra
              ? '"${card.title}" links another card. This one was made from '
                  'it too and is '
                  'removed only if you choose to.'
              : null,
      keepLabel: 'Keep',
      actLabel: 'Remove',
      destructive: true,
      orphan: card,
      notes: extra ? [card.noteName] : const [],
    );
  }

  /// A problem from the sync, shown as a card. Each kind says what is wrong,
  /// what was and was not synced, and what will fix it.
  factory Decision.issue(AnkiSyncIssue issue) {
    final names = [for (final n in issue.notes) '"${p.basename(n)}"'];
    final self = names.first;
    final source =
        issue.cardSource == null ? null : p.basename(issue.cardSource!);
    final card = issue.cardId;
    final id = issue.message.hashCode;
    final created =
        card == null ? null : DateTime.fromMillisecondsSinceEpoch(card);
    final history =
        issue.cardReviews == null ? null : _reviewed(issue.cardReviews!);
    final two = names.length == 2;
    return switch (issue.kind) {
      AnkiIssueKind.sharedCard => Decision._(
        id: id,
        title: source ?? p.basename(issue.notes.first),
        reason:
            two
                ? 'Two notes claim one card'
                : '${names.length} notes claim one card',
        reasonIcon: Icons.call_split_rounded,
        tone: AppColors.danger,
        deck: null,
        history: history,
        created: created,
        problem: issue.cardProblem,
        conjecture: issue.cardConjecture,
        explanation: [
          '${names.join(' and ')} ${two ? 'both' : 'all'} have anki_note_id '
              '$card. One card cannot belong to two notes, so nothing was '
              'synced.',
          if (source != null && names.contains('"$source"'))
            'The card was made from "$source". Delete the number from the '
                'other ${two ? 'note; it gets its' : 'notes; they get their'} '
                'own card on the next sync.'
          else
            'Keep the number on the note the card belongs to and delete it '
                'from the others; they get their own cards on the next sync.',
        ].join(' '),
        keepLabel: null,
        actLabel: null,
        destructive: false,
        issue: issue,
        notes: issue.notes,
      ),
      AnkiIssueKind.foreignCard => Decision._(
        id: id,
        title: p.basename(issue.notes.first),
        reason: "This note claims another note's card",
        reasonIcon: Icons.swap_horiz_rounded,
        tone: AppColors.warning,
        deck: null,
        history: history,
        created: created,
        problem: issue.cardProblem,
        conjecture: issue.cardConjecture,
        explanation:
            '$self has anki_note_id $card, but that card was made from '
            '"$source", which still exists. Its review history belongs to '
            '"$source", so $self was not synced. If $self should have its '
            'own card, delete its anki_note_id in Obsidian. If the card now '
            'belongs to $self, move it here; it keeps its history.',
        keepLabel: 'Not now',
        actLabel: 'Move card here',
        destructive: true,
        issue: issue,
        notes: issue.notes,
      ),
      AnkiIssueKind.lostIdentity => Decision._(
        id: id,
        title: p.basename(issue.notes.first),
        reason: 'This note lost its card number',
        reasonIcon: Icons.link_off_rounded,
        tone: AppColors.warning,
        deck: null,
        history: history,
        created: created,
        problem: issue.cardProblem,
        conjecture: issue.cardConjecture,
        explanation:
            '$self had card $card when Anki last received it, and now has no '
            'anki_note_id, so nothing was synced. Put the number back to keep '
            'the card and its history. Choose a new card only if you removed '
            'the number on purpose; the old card is then offered for removal.',
        keepLabel: 'New card',
        actLabel: 'Put it back',
        destructive: false,
        issue: issue,
        notes: issue.notes,
      ),
      AnkiIssueKind.noteFailed => Decision._(
        id: id,
        title: p.basename(issue.notes.first),
        reason: "This note didn't sync",
        reasonIcon: Icons.error_outline_rounded,
        tone: AppColors.danger,
        deck: null,
        history: null,
        created: null,
        problem: '',
        conjecture: '',
        explanation: issue.message.replaceFirst(RegExp(r'^[^:]*\.md: '), ''),
        keepLabel: null,
        actLabel: null,
        destructive: false,
        issue: issue,
        notes: issue.notes,
      ),
    };
  }

  factory Decision.missing(
    AnkiMissingCard item,
    String target,
    String? vaultPath,
  ) => Decision._(
    id: item.ankiNoteId,
    title: item.title,
    reason: "This note's card is missing from $target",
    reasonIcon: Icons.help_outline_rounded,
    tone: AppColors.warning,
    deck: item.deck,
    history: 'Not on this device',
    created: DateTime.fromMillisecondsSinceEpoch(item.ankiNoteId),
    problem: item.problem,
    conjecture: item.conjecture,
    keepLabel: 'Not now',
    actLabel: 'Re-create',
    destructive: false,
    missing: item,
    notes: [
      if (vaultPath != null)
        p
            .withoutExtension(p.relative(item.sourcePath, from: vaultPath))
            .replaceAll('\\', '/'),
    ],
  );
}

String _reviewed(int reviews) => switch (reviews) {
  0 => 'Never reviewed',
  1 => 'Reviewed once',
  final n => 'Reviewed $n times',
};

/// Swipeable decisions, one card per page. The next card peeks in from the
/// edge so it is obvious there is more than one; deciding a card moves on.
class DecisionPager extends StatefulWidget {
  final List<Decision> decisions;

  /// Ids whose decision is currently being applied.
  final Set<int> busy;
  final void Function(Decision) onKeep;
  final void Function(Decision) onAct;
  final void Function(String notePath) onOpenNote;

  /// The heading for [count] cards.
  final String Function(int count) heading;

  const DecisionPager({
    super.key,
    required this.decisions,
    required this.busy,
    required this.onKeep,
    required this.onAct,
    required this.onOpenNote,
    this.heading = decisionHeading,
  });

  static String decisionHeading(int count) =>
      count == 1
          ? 'One card needs your decision'
          : '$count cards need your decision';

  static String problemHeading(int count) =>
      count == 1 ? 'One problem to fix' : '$count problems to fix';

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
                  widget.heading(count),
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
                  child: _DecisionCard(
                    decision: decisions[index],
                    onOpenNote: widget.onOpenNote,
                  ),
                ),
          ),
        ),
        if (count > 1) ...[
          const SizedBox(height: Space.md),
          _Dots(count: count, active: _page),
        ],
        if (current.hasChoice) ...[
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => widget.onKeep(current),
                    child: Text(current.keepLabel ?? 'Not now'),
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
                            : Text(current.actLabel ?? ''),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final Decision decision;
  final void Function(String notePath) onOpenNote;
  const _DecisionCard({required this.decision, required this.onOpenNote});

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
            if (d.explanation != null) ...[
              Text(
                d.explanation!,
                style: AppTextStyles.bodyMuted,
                maxLines: d.hasSides ? 6 : 12,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Space.lg),
            ],
            Expanded(
              child:
                  d.hasSides
                      ? _Sides(
                        decision: d,
                        problemLines: d.explanation == null ? 4 : 2,
                        conjectureLines: d.explanation == null ? 3 : 1,
                      )
                      : const SizedBox.shrink(),
            ),
            Wrap(
              spacing: Space.lg,
              children: [
                if (d.hasSides || d.explanation != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => _showFullCard(context, d),
                    icon: const Icon(Icons.open_in_full_rounded, size: 18),
                    label: Text(d.hasSides ? 'Read the full card' : 'Read all'),
                  ),
                for (final note in d.notes)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => onOpenNote(note),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      d.notes.length == 1
                          ? 'Open note'
                          : 'Open ${p.basename(note)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
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
                  if (d.explanation != null) ...[
                    Text(d.explanation!, style: AppTextStyles.bodyMuted),
                    const SizedBox(height: Space.lg),
                  ],
                  if (d.hasSides) _Sides(decision: d),
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
            if (d.deck != null)
              _Fact(icon: Icons.style_outlined, label: d.deck!),
            if (d.history != null)
              _Fact(icon: Icons.history_rounded, label: d.history!),
            if (d.created != null)
              _Fact(icon: Icons.event_outlined, label: _date(d.created!)),
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
