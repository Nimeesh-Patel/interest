import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/vault_service.dart';
import '../../shared/constants/app_text_styles.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/markdown/md_utils.dart';
import '../../shared/widgets/snack.dart';
import '../anki/services/anki_sync_controller.dart';
import '../anki/services/anki_sync_service.dart';
import '../anki/services/anki_transport.dart';
import 'decision_pager.dart';
import 'settings_screen.dart';
import 'sync_memory.dart';
import 'sync_target.dart';

enum _Phase { checking, ready, syncing, unavailable, failed }

/// Interest's one screen, ordered like the journey it serves: notes are
/// written in Obsidian, the sync panel brings Anki in step, the review panel
/// hands over to Anki for studying. Opening the app previews; the Obsidian
/// ribbon (`interest://sync-anki`) syncs straight away. When the link names
/// the note being edited (`?note=`), only that note is synced and a clean
/// result hands straight back to the Anki app: the edit cycle of a review
/// session should cost seconds, not a whole-vault sync and two taps.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _deeplink = MethodChannel('dev.interest.app/deeplink');

  final _target = SyncTarget.forPlatform();
  _Phase _phase = _Phase.checking;
  TargetReadiness _readiness = TargetReadiness.ready;
  String? _vaultPath;

  /// The newest observation: a preview, or the result of the last sync.
  AnkiSyncResult? _state;
  ReviewLoad? _load;
  LastSync? _last;
  Set<int> _kept = {};
  final Set<int> _resolved = {};
  final Set<int> _busy = {};
  bool _showChanged = false;

  /// The note a one-note sync is about, vault-relative; null for a
  /// whole-vault preview or sync.
  String? _note;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deeplink.setMethodCallHandler((call) async {
      if (call.method != 'syncAnki' || !mounted) return;
      final note = call.arguments;
      note is String ? _syncNote(note) : _sync();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      Object? initial;
      try {
        initial = await _deeplink.invokeMethod<Object>('getInitialSyncAnki');
      } on MissingPluginException {
        initial = null; // desktop builds have no deep-link channel
      }
      final link = initial is Map ? initial : const {};
      final note = link['note'];
      if (link['sync'] != true) {
        _preview();
      } else if (note is String) {
        _syncNote(note);
      } else {
        _sync();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from AnkiDroid usually means cards were studied, so the
  /// due counts are refreshed (a cheap read; the vault is not rescanned).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _readiness == TargetReadiness.ready &&
        _phase == _Phase.ready) {
      _refreshLoad();
    }
  }

  Future<void> _loadLocal() async {
    final results = await Future.wait([
      VaultService.getVaultPath(),
      SyncMemory.lastSync(),
      SyncMemory.keptCards(),
    ]);
    _vaultPath = results[0] as String?;
    _last = results[1] as LastSync?;
    _kept = results[2] as Set<int>;
  }

  Future<bool> _ready() async {
    final readiness = await _target.prepare();
    if (!mounted) return false;
    setState(() {
      _readiness = readiness;
      if (readiness != TargetReadiness.ready) _phase = _Phase.unavailable;
    });
    return readiness == TargetReadiness.ready;
  }

  Future<void> _refreshLoad() async {
    final load = await _target.transport.reviewLoad();
    if (mounted) setState(() => _load = load);
  }

  Future<void> _preview() async {
    await _loadLocal();
    setState(() {
      _phase = _Phase.checking;
      _note = null;
    });
    if (!await _ready()) return;
    final result = await AnkiSyncController.sync(
      _target.transport,
      preview: true,
    );
    _show(result);
  }

  Future<void> _sync() async {
    if (_phase == _Phase.syncing) return;
    await _loadLocal();
    setState(() {
      _phase = _Phase.syncing;
      _note = null;
    });
    if (!await _ready()) return;
    final result = await AnkiSyncController.sync(_target.transport);
    if (result != null && result.completed) {
      await SyncMemory.recordSync(result);
      _last = await SyncMemory.lastSync();
    }
    _show(result);
  }

  /// The edit cycle: one note changed in Obsidian. A clean result returns to
  /// the Anki app at once; anything that needs Nimeesh (an error, a missing
  /// card to decide on) keeps Interest open to show it.
  Future<void> _syncNote(String note) async {
    if (_phase == _Phase.syncing) return;
    await _loadLocal();
    setState(() {
      _phase = _Phase.syncing;
      _note = note;
    });
    if (!await _ready()) return;
    final result = await AnkiSyncController.syncNote(_target.transport, note);
    if (result != null && result.completed) {
      await SyncMemory.recordSync(result);
      _last = await SyncMemory.lastSync();
    }
    _show(result);
    if (result != null && result.isSuccessful && !result.needsDecision) {
      await _openAnki();
    }
  }

  void _show(AnkiSyncResult? result) {
    if (!mounted) return;
    setState(() {
      _state = result;
      _resolved.clear();
      _phase =
          result == null || !result.completed ? _Phase.failed : _Phase.ready;
    });
    _refreshLoad();
  }

  bool get _changesWaiting {
    final state = _state;
    return state != null && state.preview && state.pending > 0;
  }

  List<Decision> get _decisions {
    final state = _state;
    if (state == null || _phase != _Phase.ready) return const [];
    return [
      for (final card in state.orphans)
        if (!_kept.contains(card.ankiNoteId) &&
            !_resolved.contains(card.ankiNoteId))
          Decision.orphan(card),
      for (final item in state.missing)
        if (!_resolved.contains(item.ankiNoteId))
          Decision.missing(item, _target.name, _vaultPath),
    ];
  }

  Future<void> _keep(Decision d) async {
    if (d.orphan != null) await SyncMemory.keep(d.id);
    setState(() {
      if (d.orphan != null) _kept.add(d.id);
      _resolved.add(d.id);
    });
  }

  Future<void> _act(Decision d) async {
    setState(() => _busy.add(d.id));
    final result = await AnkiSyncController.resolve(
      _target.transport,
      retire: [if (d.orphan != null) d.orphan!],
      recreate: [if (d.missing != null) d.missing!],
    );
    if (!mounted) return;
    setState(() => _busy.remove(d.id));
    if (result != null && result.isSuccessful) {
      setState(() => _resolved.add(d.id));
      showSnack(context, d.orphan != null ? 'Card removed' : 'Card re-created');
      _refreshLoad();
    } else {
      showSnack(
        context,
        result?.errors.firstOrNull ?? "That didn't work. Try again.",
        isError: true,
      );
    }
  }

  Future<void> _openAnki() async {
    if (!await _target.transport.openApp() && mounted) {
      showSnack(context, "${_target.name} couldn't be opened", isError: true);
    }
  }

  /// Opens the vault, or one note in it when [notePath] (vault-relative,
  /// without `.md`) is given.
  Future<void> _openObsidian([String? notePath]) async {
    final vault = _vaultPath ?? await VaultService.getVaultPath();
    if (vault == null) return;
    final uri = Uri.parse(
      notePath == null
          ? 'obsidian://open?vault=${Uri.encodeComponent(p.basename(vault))}'
          : obsidianUriForName(vault, notePath),
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      showSnack(context, "Obsidian couldn't be opened", isError: true);
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(target: _target)),
    );
    if (changed == true && mounted) _preview();
    _kept = await SyncMemory.keptCards();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final decisions = _decisions;
    final showReview =
        _readiness == TargetReadiness.ready &&
        (_phase == _Phase.ready || _phase == _Phase.failed);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interest'),
        actions: [
          IconButton(
            tooltip: 'Open Obsidian',
            onPressed: _openObsidian,
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: Space.xs),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _preview,
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xxl),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.lg,
                ),
                child: Text(
                  _vaultPath == null
                      ? 'Notes to ${_target.name}'
                      : '${p.basename(_vaultPath!)} to ${_target.name}',
                  style: AppTextStyles.small,
                ),
              ),
              _Gutter(child: _syncPanel()),
              if (showReview) ...[
                const SizedBox(height: Space.md),
                _Gutter(
                  child: _ReviewPanel(
                    target: _target.name,
                    load: _load,
                    primary: !_changesWaiting && _phase == _Phase.ready,
                    onOpen: _openAnki,
                  ),
                ),
              ],
              if (decisions.isNotEmpty) ...[
                const SizedBox(height: Space.xxl),
                DecisionPager(
                  decisions: decisions,
                  busy: _busy,
                  onKeep: _keep,
                  onAct: _act,
                  onOpenNote: _openObsidian,
                ),
              ],
              if (_last != null) ...[
                const SizedBox(height: Space.xxl),
                _Gutter(
                  child: _LastSyncPanel(last: _last!, onOpen: _openObsidian),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncPanel() {
    final state = _state;
    final (icon, tone, statement, detail) = switch (_phase) {
      _Phase.checking => (
        Icons.hourglass_top_rounded,
        AppColors.inkMuted,
        'Checking your notes',
        'Comparing the vault with ${_target.name}. Nothing changes yet.',
      ),
      _Phase.syncing => (
        Icons.sync_rounded,
        AppColors.accent,
        'Syncing',
        _note == null
            ? 'Writing only the cards that changed.'
            : 'Updating the card for ${p.basenameWithoutExtension(_note!)}.',
      ),
      _Phase.unavailable => (
        Icons.block_rounded,
        AppColors.warning,
        _readiness == TargetReadiness.notInstalled
            ? '${_target.name} isn\'t available'
            : 'Interest needs access to ${_target.name}',
        _readiness == TargetReadiness.notInstalled
            ? 'Install or open ${_target.name}, then try again.'
            : 'Allow access so cards can be read and written.',
      ),
      _Phase.failed => (
        Icons.error_outline_rounded,
        AppColors.danger,
        "Sync didn't finish",
        state?.errors.take(3).join('\n') ?? 'No vault is chosen yet.',
      ),
      _Phase.ready when _changesWaiting => (
        Icons.pending_outlined,
        AppColors.accent,
        state!.pending == 1
            ? '1 change to sync'
            : '${state.pending} changes to sync',
        _changeSummary(state),
      ),
      _Phase.ready when _note != null => (
        Icons.check_circle_outline_rounded,
        AppColors.success,
        state != null && state.added > 0
            ? 'Card created'
            : 'Card up to date',
        '${p.basenameWithoutExtension(_note!)} matches its note in '
            '${_target.name}. The rest of the vault was not checked; pull down '
            'to check everything.',
      ),
      _Phase.ready => (
        Icons.check_circle_outline_rounded,
        AppColors.success,
        'Everything is in sync',
        state == null
            ? ''
            : '${state.unchanged + state.added + state.updated} cards match your notes.',
      ),
    };
    final busy = _phase == _Phase.checking || _phase == _Phase.syncing;
    final changed = state?.changed ?? const <String>[];
    return _Panel(
      children: [
        Row(
          children: [
            busy
                ? SizedBox.square(
                  dimension: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: tone,
                  ),
                )
                : Icon(icon, size: 28, color: tone),
            const SizedBox(width: Space.md),
            Expanded(child: Text(statement, style: AppTextStyles.statement)),
          ],
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          Text(detail, style: AppTextStyles.bodyMuted),
        ],
        if (_changesWaiting && changed.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(() => _showChanged = !_showChanged),
            icon: Icon(
              _showChanged
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
            ),
            label: Text(_showChanged ? 'Hide notes' : 'Show notes'),
          ),
          if (_showChanged)
            for (final path in changed.take(30))
              _NoteLink(path: path, onOpen: _openObsidian),
        ],
        const SizedBox(height: Space.xl - 4),
        _syncAction(busy),
      ],
    );
  }

  Widget _syncAction(bool busy) {
    if (_phase == _Phase.unavailable) {
      return FilledButton(
        onPressed: _preview,
        child: Text(
          _readiness == TargetReadiness.permissionDenied
              ? 'Allow access'
              : 'Try again',
        ),
      );
    }
    final state = _state;
    final label = switch (_phase) {
      _Phase.checking => 'Checking',
      _Phase.syncing => 'Syncing',
      _Phase.failed => 'Try again',
      _ when _changesWaiting =>
        'Sync ${state!.pending} ${state.pending == 1 ? 'change' : 'changes'}',
      _ => 'Sync now',
    };
    // Emphasis follows state: syncing is the primary action only when there
    // is something to sync; once in sync, the review panel takes it.
    return _changesWaiting || _phase == _Phase.failed
        ? FilledButton(onPressed: busy ? null : _sync, child: Text(label))
        : OutlinedButton(onPressed: busy ? null : _sync, child: Text(label));
  }

  String _changeSummary(AnkiSyncResult s) => [
    if (s.added > 0) '${s.added} new ${s.added == 1 ? 'card' : 'cards'}',
    if (s.updated > 0)
      '${s.updated} updated ${s.updated == 1 ? 'card' : 'cards'}',
    if (s.duplicatesRetired > 0)
      '${s.duplicatesRetired} ${s.duplicatesRetired == 1 ? 'duplicate' : 'duplicates'} to remove',
    if (s.retired > 0) '${s.retired} withdrawn from a collection',
  ].join(', ');
}

class _Gutter extends StatelessWidget {
  final Widget child;
  const _Gutter({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
    child: child,
  );
}

class _Panel extends StatelessWidget {
  final List<Widget> children;
  const _Panel({required this.children});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(Radii.card),
    ),
    child: Padding(
      padding: const EdgeInsets.all(Space.xl - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

/// The hand-over to the Anki app: what is waiting today, and one tap to
/// start. Counts are the ones Anki itself shows, daily limits included.
class _ReviewPanel extends StatelessWidget {
  final String target;
  final ReviewLoad? load;
  final bool primary;
  final VoidCallback onOpen;

  const _ReviewPanel({
    required this.target,
    required this.load,
    required this.primary,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final load = this.load;
    final due = load?.total ?? 0;
    final statement = switch (load) {
      null => 'Study in $target',
      _ when due == 0 => 'Nothing due today',
      _ => due == 1 ? '1 card due' : '$due cards due',
    };
    final detail = switch (load) {
      null => 'Due counts are unavailable right now.',
      _ when due == 0 => 'You are up to date in $target.',
      _ => [
        if (load.review > 0) '${load.review} to review',
        if (load.newCards > 0) '${load.newCards} new',
        if (load.learning > 0) '${load.learning} learning',
      ].join(', '),
    };
    final label = due > 0 ? 'Review in $target' : 'Open $target';
    final emphasise = primary && due > 0;
    return _Panel(
      children: [
        Row(
          children: [
            Icon(
              Icons.style_outlined,
              size: 28,
              color: due > 0 ? AppColors.accent : AppColors.inkMuted,
            ),
            const SizedBox(width: Space.md),
            Expanded(child: Text(statement, style: AppTextStyles.statement)),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(detail, style: AppTextStyles.bodyMuted),
        const SizedBox(height: Space.xl - 4),
        emphasise
            ? FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(label),
            )
            : OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(label),
            ),
      ],
    );
  }
}

/// A note name that opens the note in Obsidian.
class _NoteLink extends StatelessWidget {
  final String path;
  final void Function(String path) onOpen;
  const _NoteLink({required this.path, required this.onOpen});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: () => onOpen(path),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              p.basename(path),
              style: AppTextStyles.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Space.sm),
          const Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: AppColors.inkFaint,
          ),
        ],
      ),
    ),
  );
}

class _LastSyncPanel extends StatelessWidget {
  final LastSync last;
  final void Function(String path) onOpen;
  const _LastSyncPanel({required this.last, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (last.added > 0) '${last.added} added',
      if (last.updated > 0) '${last.updated} updated',
      if (last.removed > 0) '${last.removed} removed',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Last sync', style: AppTextStyles.heading),
        const SizedBox(height: Space.xs),
        Text(_when(last.at), style: AppTextStyles.bodyMuted),
        const SizedBox(height: Space.xs),
        Text(
          parts.isEmpty ? 'Nothing needed changing.' : '${parts.join(', ')}.',
          style: AppTextStyles.body,
        ),
        if (last.changed.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          for (final path in last.changed.take(8))
            _NoteLink(path: path, onOpen: onOpen),
          if (last.changed.length > 8)
            Text(
              'and ${last.changed.length - 8} more',
              style: AppTextStyles.small,
            ),
        ],
      ],
    );
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    final time =
        '${at.hour % 12 == 0 ? 12 : at.hour % 12}:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'am' : 'pm'}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today at $time';
    if (diff == 1) return 'Yesterday at $time';
    return '${at.day}/${at.month}/${at.year} at $time';
  }
}
