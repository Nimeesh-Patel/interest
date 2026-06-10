import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/entities/models/collection.dart';
import '../../features/entities/models/entity.dart';
import '../../features/entities/services/markdown_storage_service.dart';
import '../constants/app_spacing.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_theme.dart';
import 'accent_button.dart';
import 'select_chip.dart';

Future<void> showQuickAddSheet(
  BuildContext context, {
  required List<Entity> entities,
  required List<Collection> collections,
  required MarkdownStorageService storage,
  required void Function(Entity) onCreated,
  String? initialCollection,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      side: BorderSide(color: AppColors.borderMid),
    ),
    builder: (ctx) => _QuickAddSheetContent(
      entities: entities,
      collections: collections,
      storage: storage,
      onCreated: onCreated,
      initialCollection: initialCollection,
    ),
  );
}

class _QuickAddSheetContent extends StatefulWidget {
  final List<Entity> entities;
  final List<Collection> collections;
  final MarkdownStorageService storage;
  final void Function(Entity) onCreated;
  final String? initialCollection;

  const _QuickAddSheetContent({
    required this.entities,
    required this.collections,
    required this.storage,
    required this.onCreated,
    this.initialCollection,
  });

  @override
  State<_QuickAddSheetContent> createState() => _QuickAddSheetContentState();
}

class _QuickAddSheetContentState extends State<_QuickAddSheetContent> {
  final _nameController = TextEditingController();
  final _collectionController = TextEditingController();
  bool _adding = false;

  static const _prefsKey = 'last_used_collection';

  @override
  void initState() {
    super.initState();
    _prefillCollection();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _collectionController.dispose();
    super.dispose();
  }

  Future<void> _prefillCollection() async {
    if (widget.initialCollection != null && widget.initialCollection!.isNotEmpty) {
      _collectionController.text = widget.initialCollection!;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (!mounted) return;
      if (saved != null && saved.isNotEmpty) {
        setState(() => _collectionController.text = saved);
      } else if (widget.collections.isNotEmpty) {
        setState(() => _collectionController.text = widget.collections.first.name);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final collection = _collectionController.text.trim();
    if (name.isEmpty || collection.isEmpty || _adding) return;
    setState(() => _adding = true);

    final now = DateTime.now().millisecondsSinceEpoch;
    final entity = Entity(
      id: MarkdownStorageService.generateEntityId(name, widget.entities),
      name: name,
      collection: collection,
      createdAt: now,
      updatedAt: now,
    );

    widget.entities.add(entity);
    await widget.storage.saveEntity(entity);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, collection);
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context);
    widget.onCreated(entity);
  }

  @override
  Widget build(BuildContext context) {
    final current = _collectionController.text.trim();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderMid,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kScreenHPad, 16, kScreenHPad, 12),
            child: Row(
              children: [
                Text('Add to collection',
                    style: AppTextStyles.entityName.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                AccentButton(
                  label: 'Add',
                  enabled: !_adding,
                  onTap: _submit,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ],
            ),
          ),
          // Note name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: AppTextStyles.bodyLarge,
              decoration: _fieldDecoration('Name…'),
            ),
          ),
          const SizedBox(height: 8),
          // Collection (free text — any value creates/uses a collection)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: TextField(
              controller: _collectionController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              style: AppTextStyles.bodyMedium,
              decoration: _fieldDecoration('Collection…'),
            ),
          ),
          // Existing collections as quick-fill chips
          if (widget.collections.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: kScreenHPad, vertical: 8),
                children: widget.collections.map((coll) {
                  return SelectChip(
                    label: coll.name,
                    selected: current == coll.name,
                    onTap: () => setState(
                        () => _collectionController.text = coll.name),
                  );
                }).toList(),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      );
}
