import 'package:flutter/material.dart';

import '../../../core/integrations_config_service.dart';
import '../../../core/vault_service.dart';
import '../../../shared/widgets/empty_state.dart';
import '../models/resurface_card.dart';
import '../services/resurface_service.dart';

class ResurfaceScreen extends StatefulWidget {
  const ResurfaceScreen({super.key});

  @override
  State<ResurfaceScreen> createState() => _ResurfaceScreenState();
}

class _ResurfaceScreenState extends State<ResurfaceScreen> {
  List<ResurfaceCard> _cards = [];
  int _currentIndex = 0;
  bool _backRevealed = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted) return;
    if (vaultPath == null) {
      setState(() {
        _loading = false;
        _error = 'No vault configured.';
      });
      return;
    }
    final config = await IntegrationsConfigService.load(vaultPath);
    final cards = await ResurfaceService.scan(
      vaultPath,
      excludedFolders: config.resurfaceExcludedFolders,
    );
    if (!mounted) return;
    cards.shuffle();
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  void _toggleBack() => setState(() => _backRevealed = !_backRevealed);

  void _goNext() {
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _backRevealed = false;
      });
    }
  }

  void _goPrev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _backRevealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resurface'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_loading && _cards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_currentIndex + 1} / ${_cards.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
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
    if (_error != null) {
      return EmptyState(icon: Icons.error_outline, message: _error!);
    }
    if (_cards.isEmpty) {
      return const EmptyState(
        icon: Icons.auto_awesome_outlined,
        message: 'No resurfaceable notes found.\nAdd a *** separator to a note.',
      );
    }

    final card = _cards[_currentIndex];

    return GestureDetector(
      onTap: _toggleBack,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          _goNext();
        } else if (v > 200) {
          _goPrev();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.sourceFile,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    card.front,
                    style: const TextStyle(fontSize: 16, height: 1.55),
                  ),
                  const SizedBox(height: 24),
                  if (!_backRevealed)
                    _TapToRevealHint()
                  else ...[
                    Divider(thickness: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      card.back,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: _currentIndex > 0 ? _goPrev : null,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 18),
                    onPressed: _currentIndex < _cards.length - 1 ? _goNext : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapToRevealHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'tap to reveal',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
