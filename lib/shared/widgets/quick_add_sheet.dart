import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/entities/models/category.dart';
import '../../features/entities/models/entity.dart';
import '../../features/entities/services/markdown_storage_service.dart';
import '../constants/app_spacing.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_theme.dart';

Future<void> showQuickAddSheet(
  BuildContext context, {
  required List<Entity> entities,
  required List<Category> categories,
  required List<String> tags,
  required List allEntityLinks,
  required MarkdownStorageService storage,
  required void Function(Entity) onCreated,
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
      categories: categories,
      tags: tags,
      allEntityLinks: allEntityLinks,
      storage: storage,
      onCreated: onCreated,
    ),
  );
}

class _QuickAddSheetContent extends StatefulWidget {
  final List<Entity> entities;
  final List<Category> categories;
  final List<String> tags;
  final List allEntityLinks;
  final MarkdownStorageService storage;
  final void Function(Entity) onCreated;

  const _QuickAddSheetContent({
    required this.entities,
    required this.categories,
    required this.tags,
    required this.allEntityLinks,
    required this.storage,
    required this.onCreated,
  });

  @override
  State<_QuickAddSheetContent> createState() => _QuickAddSheetContentState();
}

class _QuickAddSheetContentState extends State<_QuickAddSheetContent> {
  final _nameController = TextEditingController();
  String? _selectedCategoryId;
  bool _adding = false;

  static const _prefsKey = 'last_used_category';

  @override
  void initState() {
    super.initState();
    _loadLastCategory();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadLastCategory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (!mounted) return;
      if (saved != null &&
          widget.categories.any((c) => c.id == saved)) {
        setState(() => _selectedCategoryId = saved);
      } else if (widget.categories.isNotEmpty) {
        setState(() => _selectedCategoryId = widget.categories.first.id);
      }
    } catch (_) {}
  }

  Future<void> _saveLastCategory(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, id);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _adding) return;
    setState(() => _adding = true);

    final catId = _selectedCategoryId ??
        (widget.categories.isNotEmpty ? widget.categories.first.id : 'default');

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = MarkdownStorageService.generateEntityId(name, widget.entities);
    final entity = Entity(
      id: id,
      name: name,
      categoryId: catId,
      createdAt: now,
      updatedAt: now,
    );

    widget.entities.add(entity);
    widget.storage.saveData(
      entities: widget.entities,
      categories: widget.categories,
      tags: widget.tags,
      entityLinks: widget.allEntityLinks.cast(),
    );

    if (catId != 'default') await _saveLastCategory(catId);
    if (!mounted) return;
    Navigator.pop(context);
    widget.onCreated(entity);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderMid,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(kScreenHPad, 16, kScreenHPad, 12),
            child: Row(
              children: [
                Text('Add entity',
                    style: AppTextStyles.entityName.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                GestureDetector(
                  onTap: _submit,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _adding ? AppColors.accentDim : AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Add',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ),
              ],
            ),
          ),
          // Name field
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: kScreenHPad),
            child: TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Entity name…',
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
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
              ),
            ),
          ),
          // Category chips
          if (widget.categories.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: kScreenHPad, vertical: 8),
                children: widget.categories.map((cat) {
                  final selected = _selectedCategoryId == cat.id;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCategoryId = cat.id),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accentDim
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : AppColors.border,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        cat.name,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: selected
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
