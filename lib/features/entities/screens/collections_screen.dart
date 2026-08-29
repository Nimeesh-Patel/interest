import 'package:flutter/material.dart';

import '../controllers/entity_list_controller.dart';
import '../models/collection.dart';
import '../models/entity.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/bottom_sheet_menu.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/input_dialog.dart';
import '../../../shared/widgets/list_row.dart';
import '../../../shared/widgets/select_chip.dart';
import '../../../shared/widgets/snack.dart';

/// Self-contained Collections tab: collection filter chips, entity list, search,
/// sort, and all entity/collection CRUD. Receives [controller] (owned by
/// HomeScreen) and [onOpenEntity] callback for navigation.
class CollectionsScreen extends StatefulWidget {
  final EntityListController controller;
  final Future<void> Function(Entity entity) onOpenEntity;

  const CollectionsScreen({
    super.key,
    required this.controller,
    required this.onOpenEntity,
  });

  @override
  State<CollectionsScreen> createState() => CollectionsScreenState();
}

class CollectionsScreenState extends State<CollectionsScreen> {
  bool _isAddingCollection = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _newCollectionController =
      TextEditingController();
  final FocusNode _addFocus = FocusNode();

  EntityListController get _ctrl => widget.controller;

  @override
  void dispose() {
    _searchController.dispose();
    _addController.dispose();
    _newCollectionController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  // ── Entity operations ─────────────────────────────────────────────────────

  void _addEntity(String name) {
    _ctrl.addEntity(name);
    _addController.clear();
  }

  void _deleteEntity(Entity entity) => _ctrl.deleteEntity(entity);

  // ── Collection operations ─────────────────────────────────────────────────

  void _addCollection(String name) {
    setState(() => _isAddingCollection = false);
    _newCollectionController.clear();
    _ctrl.addCollection(name);
  }

  void _showCollectionOptions(Collection category) {
    showBottomSheetMenu(
      context,
      items: [
        BottomSheetMenuItem(
          icon: Icons.edit,
          label: 'Rename',
          onTap: () => _showRenameCollection(category),
        ),
        BottomSheetMenuItem(
          icon: Icons.delete,
          label: 'Delete',
          isDestructive: true,
          onTap: () => _deleteCollection(category),
        ),
      ],
    );
  }

  void _showRenameCollection(Collection category) async {
    final name = await showInputDialog(
      context,
      title: 'Rename collection',
      initialValue: category.name,
      confirmLabel: 'Rename',
    );
    if (name != null) _ctrl.renameCollection(category, name);
  }

  void _deleteCollection(Collection category) {
    final error = _ctrl.deleteCollection(category);
    if (error != null) showSnack(context, error);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Widget _buildCollectionFilter() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          SelectChip(
            label: 'All',
            selected: _ctrl.selectedCollectionId == null,
            onTap: () => setState(() => _ctrl.selectedCollectionId = null),
          ),
          for (final cat in _ctrl.collections)
            SelectChip(
              label: cat.name,
              selected: _ctrl.selectedCollectionId == cat.id,
              onTap: () => setState(() => _ctrl.selectedCollectionId = cat.id),
              onLongPress: () => _showCollectionOptions(cat),
            ),
          if (_isAddingCollection)
            Container(
              width: 140,
              margin: const EdgeInsets.only(left: 4),
              child: TextField(
                controller: _newCollectionController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Collection name',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: _addCollection,
                onEditingComplete: () {},
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _isAddingCollection = true),
              child: Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddBar() {
    final catName =
        _ctrl.collections
            .firstWhere(
              (c) => c.id == _ctrl.selectedCollectionId,
              orElse: () => Collection(id: '', name: 'collection'),
            )
            .name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addController,
              focusNode: _addFocus,
              decoration: InputDecoration(
                hintText: 'Add to $catName…',
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: _addEntity,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppColors.textSecondary,
            onPressed: () => _addEntity(_addController.text),
            tooltip: 'Add note',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search…',
          prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
          suffixIcon:
              _ctrl.searchQuery.isNotEmpty
                  ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _ctrl.searchQuery = '');
                    },
                  )
                  : null,
          isDense: true,
        ),
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _ctrl.searchQuery = v),
      ),
    );
  }

  static const _sortLabels = {
    'latest': 'Latest',
    'oldest': 'Oldest',
    'high_score': 'Highest Score',
    'low_score': 'Lowest Score',
    'alpha': 'A–Z',
    'alpha_rev': 'Z–A',
  };

  Widget _buildSortBar() {
    final items = _ctrl.filtered;
    final count = items.length;
    final sortLabel = _sortLabels[_ctrl.sortOrder] ?? 'Latest';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 8),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? "note" : "notes"}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showSortSheet,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sortLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.unfold_more,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showBottomSheetMenu(
      context,
      items: [
        for (final entry in _sortLabels.entries)
          BottomSheetMenuItem(
            icon: _ctrl.sortOrder == entry.key ? Icons.check : Icons.sort,
            label: entry.value,
            onTap: () => setState(() => _ctrl.sortOrder = entry.key),
          ),
      ],
    );
  }

  Widget _buildEntityList() {
    final items = _ctrl.filtered;
    if (items.isEmpty) {
      return EmptyState(
        message:
            _ctrl.searchQuery.isEmpty ? 'Nothing here yet.' : 'No results.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: kFabListBottomPad),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final entity = items[i];
        final catName =
            _ctrl.collections
                .firstWhere(
                  (c) => c.id == entity.collectionId,
                  orElse: () => Collection(id: '', name: ''),
                )
                .name;
        return ListRow(
          onTap: () => widget.onOpenEntity(entity),
          onLongPress: () => _showEntityOptions(entity),
          padding: const EdgeInsets.symmetric(
            horizontal: kScreenHPad,
            vertical: 13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entity.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (entity.score != null)
                          Text(
                            '★${entity.score!.toStringAsFixed(entity.score! % 1 == 0 ? 0 : 1)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.score,
                            ),
                          ),
                        if (catName.isNotEmpty)
                          Text(
                            catName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        for (final tag in entity.tags.take(2))
                          Text(
                            '#$tag',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.accent,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRelative(entity.updatedAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiscoveryWarning() {
    final count = _ctrl.discoveryErrors.length;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count collection discovery ${count == 1 ? "problem" : "problems"}. '
        'Ambiguous or unreadable notes were not loaded.\n'
        '${_ctrl.discoveryErrors.join('\n')}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  void _showEntityOptions(Entity entity) {
    showBottomSheetMenu(
      context,
      items: [
        BottomSheetMenuItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          isDestructive: true,
          onTap: () => _deleteEntity(entity),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isAddingCollection) {
          setState(() {
            _isAddingCollection = false;
            _newCollectionController.clear();
          });
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCollectionFilter(),
          if (_ctrl.selectedCollectionId != null) _buildAddBar(),
          _buildSearchBar(),
          if (_ctrl.discoveryErrors.isNotEmpty) _buildDiscoveryWarning(),
          _buildSortBar(),
          Expanded(child: _buildEntityList()),
        ],
      ),
    );
  }
}
