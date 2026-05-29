import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/widgets/bottom_sheet_menu.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/book.dart';
import '../models/hardcover_book.dart';
import '../services/book_storage_service.dart';
import '../services/hardcover_service.dart';
import '../services/hardcover_sync_service.dart';
import '../../../shared/constants/app_theme.dart';

class HardcoverScreen extends StatefulWidget {
  const HardcoverScreen({super.key});

  @override
  State<HardcoverScreen> createState() => HardcoverScreenState();
}

class HardcoverScreenState extends State<HardcoverScreen> {
  List<Book>? _books;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String? _noToken;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final vaultPath = await VaultService.getVaultPath();
    if (vaultPath == null) {
      if (mounted) {
        setState(() {
          _error = 'No vault path set.';
          _loading = false;
        });
      }
      return;
    }

    final token = await HardcoverService.getToken(vaultPath);
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _noToken = 'No Hardcover token configured. Add one in Settings.';
          _loading = false;
        });
      }
      return;
    }

    try {
      final books = await BookStorageService.loadBooks(vaultPath);
      books.sort((a, b) => a.title.compareTo(b.title));
      if (mounted) {
        setState(() {
          _books = books;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final result = await HardcoverSyncService.sync();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.summary),
        backgroundColor: result.error != null ? AppColors.destructive : null,
      ),
    );
    if (result.error == null) await _loadBooks();
  }

  // Public entry points called by HomeScreen
  Future<void> sync() => _sync();
  void openSearchSheet() => _openSearchSheet(context);

  Future<void> _openSearchSheet(BuildContext ctx) async {
    final added = await showModalBottomSheet<bool>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _SearchSheet(existingBooks: _books ?? []),
    );
    if (added == true) await _loadBooks();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          if (_syncing)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_noToken != null) {
      return EmptyState(
        icon: Icons.book_outlined,
        message: _noToken!,
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(kScreenHPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppColors.destructive)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadBooks();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_books == null || _books!.isEmpty) {
      return EmptyState(
        icon: Icons.book_outlined,
        message: 'No books yet. Tap sync to import your Hardcover library.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: kFabListBottomPad),
      itemCount: _books!.length,
      itemBuilder: (context, i) => _BookTile(book: _books![i]),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 4),
      title: Text(
        book.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.authors.isNotEmpty)
            Text(
              book.authors.join(', '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (book.status != null) _statusChip(book.status!),
              if (book.rating != null)
                _chip(
                  '★ ${book.rating!.toStringAsFixed(1)}',
                  AppColors.score,
                ),
              if (book.hardcoverId != null)
                _chip('HC', AppColors.accent),
              if (book.readwiseId != null)
                _chip('RW', AppColors.accent),
              if (book.numHighlights != null && book.numHighlights! > 0)
                _chip('${book.numHighlights} highlights', AppColors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = switch (status) {
      'read' => Colors.green.shade600,
      'reading' => Colors.blue.shade600,
      'want_to_read' => Colors.amber.shade700,
      'paused' => Colors.orange.shade600,
      'dnf' => Colors.red.shade400,
      _ => AppColors.textSecondary,
    };
    final label = switch (status) {
      'want_to_read' => 'Want to read',
      'reading' => 'Reading',
      'read' => 'Read',
      'paused' => 'Paused',
      'dnf' => 'DNF',
      _ => status,
    };
    return _chip(label, color);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ── Search-and-add bottom sheet ───────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.existingBooks});
  final List<Book> existingBooks;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _controller = TextEditingController();
  List<HardcoverBook>? _results;
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _searching = true;
      _results = null;
      _searchError = null;
    });
    final vaultPath = await VaultService.getVaultPath();
    final token = vaultPath != null ? await HardcoverService.getToken(vaultPath) : null;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() { _searching = false; _searchError = 'No token configured.'; });
      return;
    }
    final results = await HardcoverService.searchBooks(token, trimmed);
    if (mounted) {
      setState(() {
        _searching = false;
        _results = results ?? [];
        _searchError = results == null ? 'Search failed. Check your connection.' : null;
      });
    }
  }

  bool _alreadyInVault(HardcoverBook hc) =>
      widget.existingBooks.any((b) =>
          b.hardcoverId == hc.bookId ||
          b.title.toLowerCase() == hc.title.toLowerCase());

  void _onResultTap(HardcoverBook hc) {
    showBottomSheetMenu(context, items: [
      BottomSheetMenuItem(
        icon: Icons.bookmark_outline,
        label: 'Want to read',
        onTap: () => _addBook(hc, 1),
      ),
      BottomSheetMenuItem(
        icon: Icons.menu_book_outlined,
        label: 'Reading',
        onTap: () => _addBook(hc, 2),
      ),
      BottomSheetMenuItem(
        icon: Icons.check_circle_outline,
        label: 'Read',
        onTap: () => _addBook(hc, 3),
      ),
      BottomSheetMenuItem(
        icon: Icons.pause_circle_outline,
        label: 'Paused',
        onTap: () => _addBook(hc, 4),
      ),
      BottomSheetMenuItem(
        icon: Icons.cancel_outlined,
        label: 'Did not finish',
        onTap: () => _addBook(hc, 5),
      ),
    ]);
  }

  Future<void> _addBook(HardcoverBook hc, int statusId) async {
    if (_alreadyInVault(hc)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${hc.title}" is already in your vault')),
        );
        Navigator.pop(context, false);
      }
      return;
    }

    final vaultPath = await VaultService.getVaultPath();
    if (vaultPath == null) return;
    final token = await HardcoverService.getToken(vaultPath);
    if (token == null) return;

    // Add to Hardcover library — tolerate failure (untested mutation; next sync reconciles)
    await HardcoverService.insertUserBook(token, hc.bookId, statusId);

    final existingAliases = widget.existingBooks.map((b) => b.alias).toSet();
    final alias = BookStorageService.generateAlias(hc.title, hc.authors, existing: existingAliases);
    const statusSlugs = {1: 'want_to_read', 2: 'reading', 3: 'read', 4: 'paused', 5: 'dnf'};
    final now = DateTime.now().millisecondsSinceEpoch;
    final book = Book(
      alias: alias,
      title: hc.title,
      authors: hc.authors,
      hardcoverId: hc.bookId,
      status: statusSlugs[statusId] ?? 'read',
      createdAt: now,
      updatedAt: now,
    );
    await BookStorageService.createBook(vaultPath, book);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${hc.title}"')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return SizedBox(
      height: screenHeight * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(kScreenHPad, 16, kScreenHPad, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search Hardcover…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: _search,
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(kScreenHPad),
          child: Text(_searchError!, style: const TextStyle(color: AppColors.destructive)),
        ),
      );
    }
    if (_results == null) {
      return const Center(
        child: Text('Type a title and press Search', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    if (_results!.isEmpty) {
      return const EmptyState(icon: Icons.search_off, message: 'No results found.');
    }
    return ListView.builder(
      itemCount: _results!.length,
      itemBuilder: (context, i) {
        final hc = _results![i];
        final alreadyAdded = _alreadyInVault(hc);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: kScreenHPad, vertical: 2),
          title: Text(
            hc.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: alreadyAdded ? AppColors.textTertiary : null,
            ),
          ),
          subtitle: hc.authors.isNotEmpty
              ? Text(
                  hc.authors.join(', '),
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                )
              : null,
          trailing: alreadyAdded
              ? const Text('In vault', style: TextStyle(fontSize: 12, color: AppColors.textTertiary))
              : const Icon(Icons.add, size: 20),
          onTap: alreadyAdded ? null : () => _onResultTap(hc),
        );
      },
    );
  }
}
