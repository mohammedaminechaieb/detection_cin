import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../image_postprocessing/presentation/viewmodels/postprocessing_viewmodel.dart';
import '../viewmodels/captured_cards_viewmodel.dart';

class ResultPreviewScreen extends StatelessWidget {
  const ResultPreviewScreen({
    super.key,
    required this.onRetake,
    required this.onConfirm,
  });

  final VoidCallback onRetake;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Vérification'),
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
                        ),
                      if (card.back != null) ...[
                        const SizedBox(height: 16),
                        _CardImage(
                          label: 'Verso',
                          bytes: processed?.back ?? card.back!,
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
  const _CardImage({required this.label, required this.bytes});

  final String label;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ],
    );
  }
}