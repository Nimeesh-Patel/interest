import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/readwise_book.dart';
import '../services/readwise_service.dart';

class ReadwiseScreen extends StatefulWidget {
  const ReadwiseScreen({super.key});

  @override
  State<ReadwiseScreen> createState() => _ReadwiseScreenState();
}

class _ReadwiseScreenState extends State<ReadwiseScreen> {
  String? _token;
  List<ReadwiseBook>? _books;
  bool _loading = false;
  String? _error;
  final Set<int> _importing = {};
  final Map<int, String> _importResults = {};
  bool _importingAll = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted || vaultPath == null) return;
    final token = await ReadwiseService.getToken(vaultPath);
    if (!mounted) return;
    setState(() => _token = token);
    if (token != null && token.isNotEmpty) _fetchBooks();
  }

  Future<void> _fetchBooks() async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final books = await ReadwiseService.fetchBooks(token);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (books == null) {
        _error = 'Failed to fetch books — check your token and network.';
      } else {
        _books = books;
      }
    });
  }

  Future<void> _importBook(ReadwiseBook book) async {
    final token = _token;
    if (token == null || token.isEmpty) return;
    setState(() => _importing.add(book.id));

    final highlights = await ReadwiseService.fetchHighlights(token, book.id);
    if (!mounted) return;

    if (highlights == null) {
      setState(() {
        _importing.remove(book.id);
        _importResults[book.id] = 'Failed to fetch highlights';
      });
      return;
    }

    final vaultPath = await VaultService.getVaultPath();
    if (!mounted) return;

    if (vaultPath == null) {
      setState(() {
        _importing.remove(book.id);
        _importResults[book.id] = 'No vault configured';
      });
      return;
    }

    final result =
        await ReadwiseService.importBook(book, highlights, vaultPath);
    if (!mounted) return;

    setState(() {
      _importing.remove(book.id);
      if (result.error != null) {
        _importResults[book.id] = 'Error: ${result.error}';
      } else if (result.created > 0) {
        _importResults[book.id] = 'Imported (${highlights.length} highlights)';
      } else {
        _importResults[book.id] = 'Updated';
      }
    });
  }

  Future<void> _importAll() async {
    final books = _books;
    if (books == null || books.isEmpty) return;
    setState(() => _importingAll = true);
    for (final book in books) {
      if (!mounted) break;
      await _importBook(book);
    }
    if (mounted) setState(() => _importingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Readwise'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_books != null && _books!.isNotEmpty)
            _importingAll
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Import all books',
                    onPressed: _importAll,
                  ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_token == null || _token!.isEmpty) {
      return const EmptyState(
        message: 'Add your Readwise access token in Settings to get started.',
        icon: Icons.book_outlined,
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.red.shade700, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _fetchBooks,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_books == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_books!.isEmpty) {
      return const EmptyState(
        message: 'No books found in your Readwise library.',
        icon: Icons.library_books_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _books!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _buildBookTile(_books![i]),
    );
  }

  Widget _buildBookTile(ReadwiseBook book) {
    final isImporting = _importing.contains(book.id);
    final result = _importResults[book.id];

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        book.title.isNotEmpty ? book.title : 'Untitled',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (book.author.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(book.author,
                style:
                    const TextStyle(fontSize: 13, color: Colors.black87)),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              _chip(book.category),
              const SizedBox(width: 6),
              _chip('${book.numHighlights} highlights'),
              if (book.lastHighlightAt != null) ...[
                const SizedBox(width: 6),
                _chip(_formatDate(book.lastHighlightAt)),
              ],
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 4),
            Text(
              result,
              style: TextStyle(
                fontSize: 12,
                color: result.startsWith('Error')
                    ? Colors.red.shade700
                    : Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
      trailing: isImporting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(
              onPressed: _importingAll ? null : () => _importBook(book),
              child: const Text('Import'),
            ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      );

  String _formatDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
