import 'package:flutter/material.dart';

import '../models/anki_card.dart';
import '../services/anki_connect_service.dart';
import '../services/anki_storage_service.dart';
import '../../../shared/constants/app_theme.dart';

class AnkiCardEditorScreen extends StatefulWidget {
  final AnkiCard? card;

  const AnkiCardEditorScreen({super.key, this.card});

  @override
  State<AnkiCardEditorScreen> createState() => _AnkiCardEditorScreenState();
}

class _AnkiCardEditorScreenState extends State<AnkiCardEditorScreen> {
  late AnkiNoteType _noteType;
  late final TextEditingController _deckController;
  late final TextEditingController _frontController;
  late final TextEditingController _backController;
  late final TextEditingController _textController;
  late final TextEditingController _tagsController;

  List<String> _deckSuggestions = [];
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final c = widget.card;
    _noteType = c?.noteType ?? AnkiNoteType.basic;
    _deckController = TextEditingController(text: c?.deck ?? '');
    _frontController = TextEditingController(text: c?.front ?? '');
    _backController = TextEditingController(text: c?.back ?? '');
    _textController = TextEditingController(text: c?.text ?? '');
    _tagsController = TextEditingController(
      text: (c?.tags ?? []).join(', '),
    );
    _loadDeckSuggestions();
  }

  @override
  void dispose() {
    _deckController.dispose();
    _frontController.dispose();
    _backController.dispose();
    _textController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadDeckSuggestions() async {
    final decks = await AnkiConnectService.deckNames();
    if (mounted && decks != null) {
      setState(() => _deckSuggestions = decks);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _save() async {
    final deck = _deckController.text.trim();
    if (deck.isEmpty) {
      _showSnack('Deck name is required.');
      return;
    }
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    setState(() => _saving = true);

    if (widget.card != null) {
      final updated = widget.card!.copyWith(
        noteType: _noteType,
        deck: deck,
        tags: tags,
        updatedAt: DateTime.now().toUtc(),
        front: _frontController.text,
        back: _backController.text,
        text: _textController.text,
      );
      await AnkiStorageService.saveCard(updated);
    } else {
      await AnkiStorageService.createNewCard(
        noteType: _noteType,
        deck: deck,
        tags: tags,
        front: _frontController.text,
        back: _backController.text,
        text: _textController.text,
      );
    }

    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.card == null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await _onWillPop();
        if (ok) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'New Card' : 'Edit Card'),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildNoteTypeToggle(),
            const SizedBox(height: 16),
            _buildDeckField(),
            const SizedBox(height: 16),
            _buildContentFields(),
            const SizedBox(height: 16),
            _buildTagsField(),
            const SizedBox(height: 8),
            if (widget.card?.ankiId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Anki ID: ${widget.card!.ankiId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteTypeToggle() {
    return Row(
      children: [
        const Text('Type:', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const Text('Basic'),
          selected: _noteType == AnkiNoteType.basic,
          onSelected: (_) {
            setState(() => _noteType = AnkiNoteType.basic);
            _markDirty();
          },
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Cloze'),
          selected: _noteType == AnkiNoteType.cloze,
          onSelected: (_) {
            setState(() => _noteType = AnkiNoteType.cloze);
            _markDirty();
          },
        ),
      ],
    );
  }

  Widget _buildDeckField() {
    if (_deckSuggestions.isEmpty) {
      return TextField(
        controller: _deckController,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Deck',
          hintText: 'e.g. Philosophy',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => _markDirty(),
      );
    }
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _deckController.text),
      optionsBuilder: (value) {
        final q = value.text.toLowerCase();
        return _deckSuggestions.where((d) => d.toLowerCase().contains(q));
      },
      onSelected: (value) {
        _deckController.text = value;
        _markDirty();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // Sync internal controller with ours on first build
        if (_deckController.text.isNotEmpty && controller.text.isEmpty) {
          controller.text = _deckController.text;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Deck',
            hintText: 'e.g. Philosophy',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            _deckController.text = v;
            _markDirty();
          },
        );
      },
    );
  }

  Widget _buildContentFields() {
    if (_noteType == AnkiNoteType.cloze) {
      return TextField(
        controller: _textController,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          labelText: 'Text',
          hintText: 'Use {{c1::...}} for cloze deletions',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        maxLines: 6,
        onChanged: (_) => _markDirty(),
      );
    }
    return Column(
      children: [
        TextField(
          controller: _frontController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Front',
            hintText: 'Question',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 4,
          onChanged: (_) => _markDirty(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _backController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Back',
            hintText: 'Answer',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          maxLines: 4,
          onChanged: (_) => _markDirty(),
        ),
      ],
    );
  }

  Widget _buildTagsField() {
    return TextField(
      controller: _tagsController,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Tags',
        hintText: 'tag1, tag2, tag3',
        border: OutlineInputBorder(),
      ),
      onChanged: (_) => _markDirty(),
    );
  }
}
