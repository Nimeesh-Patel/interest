import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/entities/controllers/entity_list_controller.dart';
import '../features/entities/models/entity.dart';
import '../features/entities/screens/collections_screen.dart';
import '../features/entities/screens/entity_screen.dart';
import '../features/projects/screens/projects_screen.dart';
import '../features/tasks/screens/inbox_screen.dart';
import '../features/anki/services/anki_sync_runner.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/templates/screens/templates_screen.dart';
import 'sources_screen.dart';
import '../shared/constants/app_theme.dart';
import '../shared/utils/obsidian_launcher.dart';
import '../shared/widgets/app_fab.dart';
import '../shared/widgets/progress.dart';
import '../shared/widgets/quick_add_sheet.dart';
import '../shared/widgets/snack.dart';

/// Three-tab shell: Collections (0, landing), Inbox (1), and Projects (2).
/// Collections + Inbox + Projects tool plus a one-way Anki sync triggered by
/// the `interest://sync-anki` deep link from the Problem Notes Obsidian plugin.
/// Problem Note review/editing lives in Obsidian; Collections has a read-only
/// entity-body view. The deep link opens this app in the foreground and runs
/// the sync here.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _deeplinkChannel = MethodChannel('dev.interest.app/deeplink');

  final _projectsKey = GlobalKey<ProjectsScreenState>();

  late final _controller = EntityListController(
    onDataChanged: () {
      if (mounted) setState(() {});
    },
  );

  bool _isLoading = true;
  // Tabs: 0=Collections, 1=Inbox, 2=Projects
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _deeplinkChannel.setMethodCallHandler(_onDeeplinkMethod);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final syncAnki =
          await _deeplinkChannel.invokeMethod<bool>('getInitialSyncAnki') ??
          false;
      if (syncAnki && mounted) _syncAnkiFromDeeplink();
    });
  }

  Future<void> _loadData() async {
    await _controller.loadData();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _onDeeplinkMethod(MethodCall call) async {
    if (call.method == 'syncAnki' && mounted) _syncAnkiFromDeeplink();
  }

  /// `interest://sync-anki` — the Obsidian plugin triggers the whole-vault
  /// AnkiDroid push. No navigation, no new write path.
  void _syncAnkiFromDeeplink() {
    showSnack(context, 'Syncing problem notes to AnkiDroid…');
    runAnkiDroidSync(context);
  }

  // ── Entity navigation ─────────────────────────────────────────────────────

  Future<void> _openEntity(Entity entity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => EntityScreen(
              entity: entity,
              storage: _controller.storage,
              allEntities: _controller.entities,
              allCollections: _controller.collections,
              allTags: _controller.tags,
            ),
      ),
    );
    await _controller.reloadData();
  }

  Future<void> _openTemplates() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesScreen()),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _controller.reloadData();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: LoadingState());
    }

    final tabTitle = switch (_currentTab) {
      0 => 'Collections',
      1 => 'Inbox',
      _ => 'Projects',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(tabTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.sensors),
            tooltip: 'Sources',
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SourcesScreen()),
                ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settings') {
                _openSettings();
              } else if (v == 'templates') {
                _openTemplates();
              } else if (v == 'obsidian') {
                launchObsidianApp(context);
              }
            },
            itemBuilder:
                (_) => const [
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                  PopupMenuItem(value: 'templates', child: Text('Templates')),
                  PopupMenuItem(
                    value: 'obsidian',
                    child: Text('Open Obsidian'),
                  ),
                ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          CollectionsScreen(controller: _controller, onOpenEntity: _openEntity),
          const InboxScreen(),
          ProjectsScreen(key: _projectsKey),
        ],
      ),
      floatingActionButton: switch (_currentTab) {
        0 => AppFab(
          tooltip: 'Add to collection',
          onTap:
              () => showQuickAddSheet(
                context,
                entities: _controller.entities,
                collections: _controller.collections,
                storage: _controller.storage,
                onCreated: (entity) async {
                  await _controller.reloadData();
                  if (mounted) await _openEntity(entity);
                },
              ),
        ),
        1 => null,
        _ => AppFab(
          tooltip: 'New project',
          onTap: () => _projectsKey.currentState?.showCreateDialog(context),
        ),
      },
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (i) => setState(() => _currentTab = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.hub_outlined),
              activeIcon: Icon(Icons.hub),
              label: 'COLLECTIONS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inbox_outlined),
              activeIcon: Icon(Icons.inbox),
              label: 'INBOX',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.checklist_outlined),
              activeIcon: Icon(Icons.checklist),
              label: 'PROJECTS',
            ),
          ],
        ),
      ),
    );
  }
}
