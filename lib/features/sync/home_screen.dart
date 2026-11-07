import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/vault_service.dart';
import '../../shared/constants/app_text_styles.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/widgets/snack.dart';
import '../anki/services/anki_sync_controller.dart';
import '../anki/services/anki_sync_service.dart';
import 'decision_pager.dart';
import 'settings_screen.dart';
import 'sync_memory.dart';
import 'sync_target.dart';

enum _Phase { checking, ready, syncing, unavailable, failed }

/// Interest's one screen: is Anki in step with the vault, what would a sync
/// change, and which cards need a decision. Opening the app previews; the
/// Obsidian ribbon (`interest://sync-anki`) syncs straight away.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _deeplink = MethodChannel('dev.interest.app/deeplink');

  final _target = SyncTarget.forPlatform();
  _Phase _phase = _Phase.checking;
  TargetReadiness _readiness = TargetReadiness.ready;
  String? _vaultPath;

  /// The newest observation: a preview, or the result of the last sync.
  AnkiSyncResult? _state;
  LastSync? _last;
  Set<int> _kept = {};
  final Set<int> _resolved = {};
  final Set<int> _busy = {};
  bool _showChanged = false;

  @override
  void initState() {
    super.initState();
    _deeplink.setMethodCallHandler((call) async {
      if (call.method == 'syncAnki' && mounted) _sync();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool fromRibbon = false;
      try {
        fromRibbon =
            await _deeplink.invokeMethod<bool>('getInitialSyncAnki') ?? false;
      } on MissingPluginException {
        fromRibbon = false; // desktop builds have no deep-link channel
      }
      fromRibbon ? _sync() : _preview();
    });
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

  Future<void> _preview() async {
    await _loadLocal();
    setState(() => _phase = _Phase.checking);
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
    setState(() => _phase = _Phase.syncing);
    if (!await _ready()) return;
    final result = await AnkiSyncController.sync(_target.transport);
    if (result != null && result.completed) {
      await SyncMemory.recordSync(result);
      _last = await SyncMemory.lastSync();
    }
    _show(result);
  }

  void _show(AnkiSyncResult? result) {
    if (!mounted) return;
    setState(() {
      _state = result;
      _resolved.clear();
      _phase =
          result == null || !result.completed ? _Phase.failed : _Phase.ready;
    });
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
          Decision.missing(item, _target.name),
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
    } else {
      showSnack(
        context,
        result?.errors.firstOrNull ?? "That didn't work. Try again.",
        isError: true,
      );
    }
  }

  Future<void> _openObsidian() async {
    final vault = _vaultPath ?? await VaultService.getVaultPath();
    if (vault == null) return;
    final uri = Uri.parse(
      'obsidian://open?vault=${Uri.encodeComponent(p.basename(vault))}',
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: _statusPanel(),
              ),
              if (decisions.isNotEmpty) ...[
                const SizedBox(height: Space.xxl),
                DecisionPager(
                  decisions: decisions,
                  busy: _busy,
                  onKeep: _keep,
                  onAct: _act,
                ),
              ],
              if (_last != null) ...[
                const SizedBox(height: Space.xxl),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: _LastSyncPanel(last: _last!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPanel() {
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
        'Writing only the cards that changed.',
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
      _Phase.ready when state != null && state.preview && state.pending > 0 => (
        Icons.pending_outlined,
        AppColors.accent,
        state.pending == 1
            ? '1 change to sync'
            : '${state.pending} changes to sync',
        _changeSummary(state),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.xl - 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                Expanded(
                  child: Text(statement, style: AppTextStyles.statement),
                ),
              ],
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(detail, style: AppTextStyles.bodyMuted),
            ],
            if (_phase == _Phase.ready &&
                state != null &&
                state.preview &&
                changed.isNotEmpty) ...[
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
                for (final title in changed.take(30))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Text(title, style: AppTextStyles.body),
                  ),
            ],
            const SizedBox(height: Space.xl - 4),
            _primaryAction(busy),
          ],
        ),
      ),
    );
  }

  Widget _primaryAction(bool busy) {
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
      _ when state != null && state.preview && state.pending > 0 =>
        'Sync ${state.pending} ${state.pending == 1 ? 'change' : 'changes'}',
      _ => 'Sync now',
    };
    final waiting =
        _phase == _Phase.failed ||
        (state != null && state.preview && state.pending > 0);
    // Emphasis follows state: a filled button only when there is work to do.
    return waiting
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

class _LastSyncPanel extends StatelessWidget {
  final LastSync last;
  const _LastSyncPanel({required this.last});

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
          const SizedBox(height: Space.sm),
          for (final title in last.changed.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3, right: Space.sm),
                    child: Icon(
                      Icons.subdirectory_arrow_right_rounded,
                      size: 16,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  Expanded(child: Text(title, style: AppTextStyles.bodyMuted)),
                ],
              ),
            ),
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
