import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/constants/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/book.dart';
import '../services/book_storage_service.dart';
import '../services/hardcover_service.dart';
import '../services/hardcover_sync_service.dart';

class HardcoverScreen extends StatefulWidget {
  const HardcoverScreen({super.key});

  @override
  State<HardcoverScreen> createState() => _HardcoverScreenState();
}

class _HardcoverScreenState extends State<HardcoverScreen> {
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
    final token = await HardcoverService.getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _noToken = 'No Hardcover token configured. Add one in Settings.';
          _loading = false;
        });
      }
      return;
    }

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
        backgroundColor: result.error != null ? Colors.red.shade700 : null,
      ),
    );
    if (result.error == null) await _loadBooks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardcover'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_noToken == null && !_loading)
            _syncing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Sync with Hardcover',
                    onPressed: _syncing ? null : _sync,
                  ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
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
              Text(_error!, style: const TextStyle(color: Colors.red)),
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
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
                  Colors.amber.shade700,
                ),
              if (book.hardcoverId != null)
                _chip('HC', Colors.indigo.shade400),
              if (book.readwiseId != null)
                _chip('RW', Colors.teal.shade400),
              if (book.numHighlights != null && book.numHighlights! > 0)
                _chip('${book.numHighlights} highlights', Colors.grey),
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
      _ => Colors.grey,
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
