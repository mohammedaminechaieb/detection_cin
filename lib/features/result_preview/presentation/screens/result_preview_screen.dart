import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../document_detection/domain/entities/detected_document.dart' show CardSide;
import '../../../document_detection/presentation/viewmodels/detection_viewmodel.dart';
import '../../../image_postprocessing/domain/entities/enhancement_settings.dart';
import '../../../image_postprocessing/presentation/viewmodels/postprocessing_viewmodel.dart';
import '../viewmodels/captured_cards_viewmodel.dart';
import 'recrop_screen.dart';

class ResultPreviewScreen extends StatelessWidget {
  const ResultPreviewScreen({
    super.key,
    required this.onRetake,
    required this.onConfirm,
  });

  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  Future<void> _recrop(BuildContext context, CardSide side, Uint8List currentBytes) async {
    final repository = context.read<DetectionViewModel>().repository;
    final newBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => RecropScreen(
          imageBytes: currentBytes,
          repository: repository,
          label: side == CardSide.front ? 'Recto' : 'Verso',
        ),
      ),
    );
    if (newBytes == null || !context.mounted) return;

    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    capturedCardsViewModel.setCapture(side, newBytes);
    _reprocess(context);
  }

  /// Re-runs postprocessing with whatever `EnhancementSettings` are
  /// currently active - needs both sides, so no-ops until both exist.
  void _reprocess(BuildContext context) {
    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    final card = capturedCardsViewModel.card;
    if (card.front == null || card.back == null) return;
    context.read<PostprocessingViewModel>().process(card.front!, card.back!);
  }

  Future<void> _openEnhancementPicker(BuildContext context) async {
    final processing = context.read<PostprocessingViewModel>();
    final result = await showModalBottomSheet<EnhancementSettings>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      builder: (_) => _EnhancementPickerSheet(initial: processing.settings),
    );
    if (result == null || !context.mounted) return;

    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    final card = capturedCardsViewModel.card;
    if (card.front == null || card.back == null) return;
    processing.process(card.front!, card.back!, settings: result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Vérification'),
        actions: [
          IconButton(
            onPressed: () => _openEnhancementPicker(context),
            icon: const Icon(Icons.tune),
            tooltip: 'Options d\'amélioration',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Consumer2<CapturedCardsViewModel, PostprocessingViewModel>(
                builder: (context, captured, processing, _) {
                  final card = captured.card;
                  final processed = processing.result;

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (card.front != null)
                        _CardImage(
                          label: 'Recto',
                          bytes: processed?.front ?? card.front!,
                          onRecrop: () => _recrop(context, CardSide.front, card.front!),
                        ),
                      if (card.back != null) ...[
                        const SizedBox(height: 16),
                        _CardImage(
                          label: 'Verso',
                          bytes: processed?.back ?? card.back!,
                          onRecrop: () => _recrop(context, CardSide.back, card.back!),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _PrintPageSection(processing: processing),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRetake,
                      child: const Text('Reprendre'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onConfirm,
                      child: const Text('Valider'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrintPageSection extends StatelessWidget {
  const _PrintPageSection({required this.processing});

  final PostprocessingViewModel processing;

  @override
  Widget build(BuildContext context) {
    if (processing.error != null) {
      return Text(
        'Page à imprimer indisponible : ${processing.error}',
        style: const TextStyle(color: Colors.redAccent),
      );
    }

    if (processing.isProcessing || processing.result == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
            SizedBox(width: 12),
            Text('Préparation de la page à imprimer...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return _CardImage(label: 'Page à imprimer', bytes: processing.result!.printPage);
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.label, required this.bytes, this.onRecrop});

  final String label;
  final Uint8List bytes;

  /// If non-null, shows a "Recadrer" button under the image. Omitted for
  /// the composed print-page preview, which isn't something you'd recrop
  /// directly (it's derived from the front/back, which you'd recrop
  /// instead).
  final VoidCallback? onRecrop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            if (onRecrop != null)
              TextButton.icon(
                onPressed: onRecrop,
                icon: const Icon(Icons.crop, size: 18),
                label: const Text('Recadrer'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ],
    );
  }
}

class _EnhancementPickerSheet extends StatefulWidget {
  const _EnhancementPickerSheet({required this.initial});

  final EnhancementSettings initial;

  @override
  State<_EnhancementPickerSheet> createState() => _EnhancementPickerSheetState();
}

class _EnhancementPickerSheetState extends State<_EnhancementPickerSheet> {
  late EnhancementSettings _settings = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Options d\'amélioration',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            const Text('Contraste', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            SegmentedButton<ContrastLevel>(
              segments: ContrastLevel.values
                  .map((level) => ButtonSegment(value: level, label: Text(level.label)))
                  .toList(),
              selected: {_settings.contrastLevel},
              onSelectionChanged: (selected) {
                setState(() => _settings = _settings.copyWith(contrastLevel: selected.first));
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Netteté', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Accentue le texte et les bords',
                style: TextStyle(color: Colors.white54),
              ),
              value: _settings.sharpenEnabled,
              onChanged: (value) => setState(() => _settings = _settings.copyWith(sharpenEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mode scan (N&B)', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Convertit en noir et blanc, comme un scanner',
                style: TextStyle(color: Colors.white54),
              ),
              value: _settings.grayscale,
              onChanged: (value) => setState(() => _settings = _settings.copyWith(grayscale: value)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_settings),
                child: const Text('Appliquer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}