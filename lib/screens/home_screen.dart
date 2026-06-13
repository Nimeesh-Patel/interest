import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/integrations_config_service.dart';
import '../core/vault_service.dart';
import '../features/entities/controllers/entity_list_controller.dart';
import '../features/entities/models/entity.dart';
import '../features/entities/screens/collections_screen.dart';
import '../features/entities/screens/entity_screen.dart';
import '../features/projects/screens/projects_screen.dart';
import '../features/resurface/screens/resurface_screen.dart';
import '../features/resurface/services/anki_sync_runner.dart';
import '../features/bookmarks/x_bookmark_service.dart';
import '../features/bookmarks/x_bookmark_storage_service.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/templates/screens/templates_screen.dart';
import 'sources_screen.dart';
import '../shared/constants/app_theme.dart';
import '../shared/utils/obsidian_launcher.dart';
import '../shared/widgets/app_fab.dart';
import '../shared/widgets/input_dialog.dart';
import '../shared/widgets/progress.dart';
import '../shared/widgets/quick_add_sheet.dart';
import '../shared/widgets/snack.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _shareChannel = MethodChannel('people.nimee/share');
  static final _deeplinkChannel = MethodChannel('com.nimeesh.interest/deeplink');

  final _projectsKey = GlobalKey<ProjectsScreenState>();
  final _resurfaceKey = GlobalKey<ResurfaceScreenState>();

  late final _controller = EntityListController(
    onDataChanged: () {
      if (mounted) setState(() {});
    },
  );

  bool _isLoading = true;
  String? _pendingDeeplinkNote;
  // Tabs: 0=Notes, 1=Collections, 2=Projects
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _shareChannel.setMethodCallHandler(_onShareMethod);
    _deeplinkChannel.setMethodCallHandler(_onDeeplinkMethod);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final url =
          await _shareChannel.invokeMethod<String?>('getInitialShareUrl');
      if (url != null && mounted) _ingestShareUrl(url);
      final noteName =
          await _deeplinkChannel.invokeMethod<String?>('getInitialDeeplinkNote');
      if (noteName != null && mounted) _openNoteFromDeeplink(noteName);
      final syncAnki =
          await _deeplinkChannel.invokeMethod<bool>('getInitialSyncAnki') ??
              false;
      if (syncAnki && mounted) _syncAnkiFromDeeplink();
    });
  }

  Future<void> _loadData() async {
    await _controller.loadData();
    if (mounted) setState(() => _isLoading = false);
    final vault = await VaultService.getVaultPath();
    if (vault != null) {
      await IntegrationsConfigService.migrateFromPrefs(vault);
    }
    if (mounted && _pendingDeeplinkNote != null) {
      final name = _pendingDeeplinkNote!;
      _pendingDeeplinkNote = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resurfaceKey.currentState?.openNoteByName(name);
      });
    }
  }

  Future<void> _onShareMethod(MethodCall call) async {
    if (call.method == 'onShareIntent') {
      final url = call.arguments as String?;
      if (url != null && mounted) _ingestShareUrl(url);
    }
  }

  Future<void> _onDeeplinkMethod(MethodCall call) async {
    if (call.method == 'openNote') {
      final name = call.arguments as String?;
      if (name != null && mounted) _openNoteFromDeeplink(name);
    } else if (call.method == 'syncAnki') {
      if (mounted) _syncAnkiFromDeeplink();
    }
  }

  /// `interest://sync-anki` — an external app (the Obsidian plugin) triggers
  /// the same whole-vault AnkiDroid push as the Sources screen row, with the
  /// standard result UI. No navigation, no new write path.
  void _syncAnkiFromDeeplink() {
    showSnack(context, 'Syncing problem notes to AnkiDroid…');
    runAnkiDroidSync(context);
  }

  void _openNoteFromDeeplink(String rawName) {
    final decoded = Uri.decodeComponent(rawName);
    setState(() => _currentTab = 0);
    final state = _resurfaceKey.currentState;
    if (state != null) {
      state.openNoteByName(decoded);
    } else {
      _pendingDeeplinkNote = decoded;
    }
  }

  Future<void> _ingestShareUrl(String url) async {
    final vault = await VaultService.getVaultPath();
    if (vault == null || !mounted) return;

    final (error, meta) = await XBookmarkService.fetchMetadata(url);
    if (error != null) {
      if (mounted) showSnack(context, error);
      return;
    }
    if (!mounted) return;

    final name = await showInputDialog(
      context,
      title: 'Save bookmark',
      hintText: 'Note name (optional)',
      confirmLabel: 'Save',
      cancelLabel: 'Skip',
      capitalization: TextCapitalization.none,
    );
    if (!mounted) return;

    final String baseSlug;
    if (name != null && name.isNotEmpty) {
      baseSlug = name;
    } else if (meta?.tweetText != null && meta!.tweetText!.isNotEmpty) {
      final words =
          meta.tweetText!.trim().split(RegExp(r'\s+')).take(7).join(' ');
      baseSlug = words;
    } else {
      baseSlug = 'x-${meta?.tweetId ?? 'bookmark'}';
    }

    final dirPath = VaultService.bookmarksPath(vault);
    final slug = XBookmarkStorageService.uniqueSlug(
        baseSlug.isNotEmpty ? baseSlug : 'x-${meta?.tweetId ?? 'bookmark'}',
        dirPath);

    if (meta == null) return;
    final saveError = await XBookmarkStorageService.save(vault, slug, meta);
    if (!mounted) return;
    showSnack(context, saveError ?? 'Saved to Bookmarks');
  }

  // ── Entity navigation ─────────────────────────────────────────────────────

  Future<void> _openEntity(Entity entity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EntityScreen(
          entity: entity,
          storage: _controller.storage,
          allEntities: _controller.entities,
          allCollections: _controller.collections,
          allTags: _controller.tags,
          onOpenNoteByPath: (path) async {
            Navigator.of(context).pop();
            setState(() => _currentTab = 0);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _resurfaceKey.currentState?.openNoteByPath(path);
            });
          },
        ),
      ),
    );
    await _controller.reloadData();
  }

  /// Called by ResurfaceScreen when its note router finds `collection:`.
  /// Reloads once on a miss so entities created outside the app still resolve.
  Future<void> _openEntityByPath(String filePath) async {
    var matches = _controller.entities.where((e) => e.sourcePath == filePath);
    if (matches.isEmpty) {
      await _controller.reloadData();
      matches = _controller.entities.where((e) => e.sourcePath == filePath);
      if (matches.isEmpty) return;
    }
    await _openEntity(matches.first);
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

    final notesState = _resurfaceKey.currentState;
    final notesCanGoBack = _currentTab == 0 && (notesState?.canGoBack ?? false);
    final notesEditPath = _currentTab == 0 ? notesState?.currentEditFilePath : null;
    final notesIsSearchable = _currentTab == 0 && (notesState?.isSearchable ?? false);
    final notesSearchActive = notesState?.isSearchActive ?? false;

    final tabTitle = switch (_currentTab) {
      0 => notesState?.navTitle ?? 'Notes',
      1 => 'Collections',
      _ => 'Projects',
    };

    return Scaffold(
      appBar: AppBar(
        leading: notesCanGoBack
            ? BackButton(onPressed: () {
                notesState!.goBack();
                setState(() {});
              })
            : null,
        title: Text(tabTitle),
        actions: [
          if (notesIsSearchable)
            IconButton(
              icon: Icon(notesSearchActive ? Icons.close : Icons.search),
              tooltip: notesSearchActive ? 'Close search' : 'Search notes',
              onPressed: () {
                notesState!.toggleSearch();
                setState(() {});
              },
            ),
          if (notesEditPath != null) ...[
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: 'Open in Obsidian',
              onPressed: () => notesState!.launchObsidianForCurrentNote(context),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit note',
              onPressed: () async {
                await notesState!.openEditForCurrentNote(context);
                setState(() {});
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.sensors),
            tooltip: 'Sources',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SourcesScreen()),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'settings') { _openSettings(); }
              else if (v == 'templates') { _openTemplates(); }
              else if (v == 'obsidian') { launchObsidianApp(context); }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'templates', child: Text('Templates')),
              PopupMenuItem(value: 'obsidian', child: Text('Open Obsidian')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          ResurfaceScreen(
            key: _resurfaceKey,
            onNavigationChanged: () => setState(() {}),
            onOpenEntity: _openEntityByPath,
          ),
          CollectionsScreen(
            controller: _controller,
            onOpenEntity: _openEntity,
          ),
          ProjectsScreen(key: _projectsKey),
        ],
      ),
      floatingActionButton: switch (_currentTab) {
        1 => AppFab(
            tooltip: 'Add to collection',
            onTap: () => showQuickAddSheet(
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
        2 => AppFab(
            tooltip: 'New project',
            onTap: () => _projectsKey.currentState?.showCreateDialog(context),
          ),
        _ => null,
      },
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (i) {
            if (i == 0 && _currentTab == 0) {
              _resurfaceKey.currentState?.resetStack();
            }
            setState(() => _currentTab = i);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories_outlined),
              activeIcon: Icon(Icons.auto_stories),
              label: 'NOTES',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.hub_outlined),
              activeIcon: Icon(Icons.hub),
              label: 'COLLECTIONS',
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

