import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/components/action_buttons.dart';
import '../../../document_detection/domain/entities/detected_document.dart' show CardSide;
import '../../../document_detection/presentation/viewmodels/detection_viewmodel.dart';
import '../../../image_postprocessing/domain/entities/enhancement_settings.dart';
import '../../../image_postprocessing/presentation/viewmodels/postprocessing_viewmodel.dart';
import '../../../../core/services/capture_storage_service.dart';
import '../viewmodels/captured_cards_viewmodel.dart';
import 'edit_capture_screen.dart';

class ResultPreviewScreen extends StatefulWidget {
  const ResultPreviewScreen({
    super.key,
    required this.onRetake,
    required this.onConfirmed,
    this.storageService = const CaptureStorageService(),
  });

  final VoidCallback onRetake;

  /// Called once the capture has actually finished saving to disk - not
  /// the same moment "Valider" is tapped, since saving is async and can
  /// fail. See `_confirm`.
  final VoidCallback onConfirmed;

  final CaptureStorageService storageService;

  @override
  State<ResultPreviewScreen> createState() => _ResultPreviewScreenState();
}

class _ResultPreviewScreenState extends State<ResultPreviewScreen> {
  bool _isSaving = false;
  String? _saveError;

  Future<void> _edit(CardSide side, Uint8List currentBytes) async {
    final repository = context.read<DetectionViewModel>().repository;
    final newBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => EditCaptureScreen(
          imageBytes: currentBytes,
          repository: repository,
          label: side == CardSide.front ? 'Recto' : 'Verso',
        ),
      ),
    );
    if (newBytes == null || !mounted) return;

    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    capturedCardsViewModel.setCapture(side, newBytes);
    _reprocess();
  }

  /// Re-runs postprocessing with whatever `EnhancementSettings` are
  /// currently active - needs both sides, so no-ops until both exist.
  void _reprocess() {
    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    final card = capturedCardsViewModel.card;
    if (card.front == null || card.back == null) return;
    context.read<PostprocessingViewModel>().process(card.front!, card.back!);
  }

  Future<void> _openEnhancementPicker() async {
    final processing = context.read<PostprocessingViewModel>();
    final result = await showModalBottomSheet<EnhancementSettings>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _EnhancementPickerSheet(initial: processing.settings),
    );
    if (result == null || !mounted) return;

    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    final card = capturedCardsViewModel.card;
    if (card.front == null || card.back == null) return;
    processing.process(card.front!, card.back!, settings: result);
  }

  Future<void> _confirm() async {
    if (_isSaving) return; // guards a double-tap from firing two saves

    final capturedCardsViewModel = context.read<CapturedCardsViewModel>();
    final processing = context.read<PostprocessingViewModel>();
    final card = capturedCardsViewModel.card;
    final processed = processing.result;

    if (card.front == null || card.back == null || processed == null) {
      // Shouldn't normally be reachable (the button is disabled until
      // enhancement finishes - see `build`), but guard anyway rather
      // than crash on a null bang if something raced.
      setState(() => _saveError = 'La carte n\'est pas encore prête à être enregistrée.');
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      // The print page may still be composing (it's the slower, second
      // postprocessing stage - see `PostprocessingViewModel`). Saving
      // doesn't need to block on it: if it isn't ready yet, fall back to
      // the enhanced front/back so "Valider" never hangs waiting on the
      // print layout specifically, which the person isn't looking at
      // when they tap this button.
      final printPage = processed.printPage ?? processed.front;
      final saved = await widget.storageService.save(
        rawFront: card.front!,
        rawBack: card.back!,
        enhancedFront: processed.front,
        enhancedBack: processed.back,
        printPage: printPage,
      );
      if (!mounted) return;
      await _showSavedConfirmation(saved.directory);
      if (!mounted) return;
      widget.onConfirmed();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Échec de l\'enregistrement : $e';
      });
    }
  }

  Future<void> _showSavedConfirmation(String directory) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
        title: const Text('Carte enregistrée', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Les images ont été enregistrées sur l\'appareil.',
          style: const TextStyle(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          PrimaryActionButton(
            label: 'OK',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Vérification'),
        actions: [
          IconButton(
            onPressed: _openEnhancementPicker,
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
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [
                      if (card.front != null)
                        _CardImage(
                          label: 'Recto',
                          bytes: processed?.front ?? card.front!,
                          onEdit: () => _edit(CardSide.front, card.front!),
                        ),
                      if (card.back != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _CardImage(
                          label: 'Verso',
                          bytes: processed?.back ?? card.back!,
                          onEdit: () => _edit(CardSide.back, card.back!),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      _PrintPageSection(processing: processing),
                    ],
                  );
                },
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _saveError!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Consumer<PostprocessingViewModel>(
                builder: (context, processing, _) {
                  // Deliberately does NOT wait on `processing.
                  // isComposingPrintPage` - the print page is a
                  // secondary artifact of the enhanced front/back, and
                  // making the person wait for it before they can even
                  // tap "Valider" was adding a delay unrelated to what
                  // they're actually reviewing on this screen.
                  final isReady = !processing.isProcessing && processing.result != null;
                  return Row(
                    children: [
                      Expanded(
                        child: SecondaryActionButton(
                          label: 'Reprendre',
                          onPressed: _isSaving ? null : widget.onRetake,
                          icon: Icons.refresh,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: PrimaryActionButton(
                          label: 'Valider',
                          isLoading: _isSaving,
                          onPressed: isReady ? _confirm : null,
                          icon: Icons.check,
                        ),
                      ),
                    ],
                  );
                },
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
    if (processing.printPageError != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Page à imprimer indisponible : ${processing.printPageError}',
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      );
    }

    final printPage = processing.result?.printPage;

    if (printPage == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
            ),
            SizedBox(width: AppSpacing.md),
            Text('Préparation de la page à imprimer...', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return _CardImage(label: 'Page à imprimer', bytes: printPage);
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.label, required this.bytes, this.onEdit});

  final String label;
  final Uint8List bytes;

  /// If non-null, shows an "Ajuster" button under the image, opening
  /// `EditCaptureScreen` (crop + rotate). Omitted for the composed
  /// print-page preview, which isn't something you'd edit directly -
  /// it's derived from the front/back, which you'd edit instead.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Ajuster'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(0, kMinTouchTarget),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: AppColors.surface),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
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
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.md,
          bottom: AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Options d\'amélioration',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Contraste', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<ContrastLevel>(
              segments: ContrastLevel.values
                  .map((level) => ButtonSegment(value: level, label: Text(level.label)))
                  .toList(),
              selected: {_settings.contrastLevel},
              onSelectionChanged: (selected) {
                setState(() => _settings = _settings.copyWith(contrastLevel: selected.first));
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Netteté', style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text(
                'Accentue le texte et les bords',
                style: TextStyle(color: AppColors.textTertiary),
              ),
              value: _settings.sharpenEnabled,
              onChanged: (value) => setState(() => _settings = _settings.copyWith(sharpenEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mode scan (N&B)', style: TextStyle(color: AppColors.textPrimary)),
              subtitle: const Text(
                'Convertit en noir et blanc, comme un scanner',
                style: TextStyle(color: AppColors.textTertiary),
              ),
              value: _settings.grayscale,
              onChanged: (value) => setState(() => _settings = _settings.copyWith(grayscale: value)),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryActionButton(
              label: 'Appliquer',
              onPressed: () => Navigator.of(context).pop(_settings),
            ),
          ],
        ),
      ),
    );
  }
}