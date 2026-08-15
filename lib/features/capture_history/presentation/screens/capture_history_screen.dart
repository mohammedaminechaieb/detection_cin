import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/capture_storage_service.dart';
import '../../../../core/theme/app_theme.dart';

/// Browses past captures saved via [CaptureStorageService.save] - a
/// simple list of everything still on disk in the app's private
/// `captures/` folder, newest first, with a way to reopen, share, or
/// delete each one.
///
/// This isn't wired to any particular navigation entry point in this
/// diff - push it (`Navigator.push(MaterialPageRoute(builder: (_) =>
/// const CaptureHistoryScreen()))`) from wherever makes sense in your
/// app (a button on the camera screen's top bar is a natural spot).
class CaptureHistoryScreen extends StatefulWidget {
  const CaptureHistoryScreen({super.key, this.storageService = const CaptureStorageService()});

  final CaptureStorageService storageService;

  @override
  State<CaptureHistoryScreen> createState() => _CaptureHistoryScreenState();
}

class _CaptureHistoryScreenState extends State<CaptureHistoryScreen> {
  late Future<List<SavedCapture>> _capturesFuture;

  @override
  void initState() {
    super.initState();
    _capturesFuture = widget.storageService.listCaptures();
  }

  void _reload() {
    setState(() => _capturesFuture = widget.storageService.listCaptures());
  }

  Future<void> _delete(SavedCapture capture) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Supprimer cette carte ?'),
        content: const Text('Cette action est définitive et supprime les images enregistrées localement.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.storageService.deleteCapture(capture.directory);
    if (!mounted) return;
    _reload();
  }

  Future<void> _share(SavedCapture capture) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(capture.frontPath),
          XFile(capture.backPath),
          XFile(capture.printPagePath),
        ],
        text: 'CIN - ${_formatDate(capture.savedAt)}',
      ),
    );
  }

  void _openDetail(SavedCapture capture) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CaptureDetailScreen(capture: capture)),
    );
  }

  String _formatDate(DateTime date) {
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(date.day)}/${pad(date.month)}/${date.year} à ${pad(date.hour)}:${pad(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Historique'),
      ),
      body: FutureBuilder<List<SavedCapture>>(
        future: _capturesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final captures = snapshot.data ?? const [];
          if (captures.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Aucune carte enregistrée pour l\'instant.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: captures.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final capture = captures[index];
                return _CaptureListTile(
                  capture: capture,
                  dateLabel: _formatDate(capture.savedAt),
                  onTap: () => _openDetail(capture),
                  onShare: () => _share(capture),
                  onDelete: () => _delete(capture),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CaptureListTile extends StatelessWidget {
  const _CaptureListTile({
    required this.capture,
    required this.dateLabel,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  final SavedCapture capture;
  final String dateLabel;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Image.file(
                  File(capture.frontPath),
                  width: 64,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  dateLabel,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, color: AppColors.textSecondary),
                tooltip: 'Partager',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                tooltip: 'Supprimer',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureDetailScreen extends StatelessWidget {
  const _CaptureDetailScreen({required this.capture});

  final SavedCapture capture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Détail'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _DetailImage(label: 'Recto', path: capture.frontPath),
            const SizedBox(height: AppSpacing.md),
            _DetailImage(label: 'Verso', path: capture.backPath),
            const SizedBox(height: AppSpacing.md),
            _DetailImage(label: 'Page à imprimer', path: capture.printPagePath),
          ],
        ),
      ),
    );
  }
}

class _DetailImage extends StatelessWidget {
  const _DetailImage({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: AppColors.surface),
            child: Image.file(File(path), fit: BoxFit.contain, width: double.infinity),
          ),
        ),
      ],
    );
  }
}