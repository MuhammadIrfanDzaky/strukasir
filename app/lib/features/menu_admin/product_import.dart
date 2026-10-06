import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import 'menu_admin_api.dart';

/// Import produk dari CSV (mis. export dari POS lama): jelaskan format → pilih file → pratinjau
/// (server memeriksa tanpa menyimpan) → konfirmasi → simpan. Satu baris salah = tidak ada yang disimpan.
Future<void> importProducts(BuildContext context, WidgetRef ref) async {
  final pick = await showDialog<bool>(context: context, builder: (_) => const _FormatDialog());
  if (pick != true || !context.mounted) return;

  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
  if (file == null || !context.mounted) return;

  final String csv;
  try {
    final bytes = await file.xFile.readAsBytes();
    if (bytes.length > 512 * 1024) throw const FormatException('File terlalu besar (maks. 512 KB).');
    // UTF-8 (umum); file dari Excel Windows lama kadang Latin-1.
    csv = _decode(bytes);
  } on FormatException catch (e) {
    if (context.mounted) _snack(context, e.message);
    return;
  }

  final api = ref.read(menuAdminApiProvider);
  Map<String, dynamic>? preview;
  if (!context.mounted) return;
  preview = await _withProgress(context, () => api.importProducts(csv, dryRun: true));
  if (preview == null || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _PreviewDialog(fileName: file.name, result: preview!),
  );
  if (confirmed != true || !context.mounted) return;

  final result = await _withProgress(context, () => api.importProducts(csv, dryRun: false));
  if (result != null && context.mounted) {
    final errors = (result['errors'] as List?) ?? const [];
    _snack(
      context,
      errors.isEmpty
          ? 'Import selesai: ${result['created']} produk baru, ${result['updated']} diperbarui.'
          : 'Import dibatalkan: ${errors.length} baris bermasalah.',
    );
  }
}

String _decode(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

/// Jalankan [task] sambil menampilkan dialog "Memeriksa…"; error API → snackbar & null.
Future<Map<String, dynamic>?> _withProgress(BuildContext context, Future<Map<String, dynamic>> Function() task) async {
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            SizedBox(width: AppSpace.s4),
            Expanded(child: Text('Memeriksa file…')),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } on ApiException catch (e) {
    if (context.mounted) _snack(context, e.message);
    return null;
  } finally {
    navigator.pop();
  }
}

class _FormatDialog extends StatelessWidget {
  const _FormatDialog();

  @override
  Widget build(BuildContext context) {
    final muted = AppType.body.copyWith(color: AppColors.inkMuted);
    return AlertDialog(
      scrollable: true,
      title: const Text('Import produk dari CSV'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pakai file CSV dari Excel / Google Sheets, atau hasil export POS lama. Baris pertama berisi judul kolom:',
              style: muted,
            ),
            const SizedBox(height: AppSpace.s3),
            for (final (col, note) in const [
              ('Nama Produk', 'wajib'),
              ('Harga Jual', 'wajib, mis. 18000 atau Rp 18.000'),
              ('Kategori', 'kategori baru dibuat otomatis'),
              ('Kode Produk', 'opsional, mis. BB03'),
              ('Modal / HPP', 'opsional'),
              ('Aktif, Favorit', 'opsional, isi ya / tidak'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s1),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '• $col ', style: AppType.bodyStrong),
                  TextSpan(text: '— $note', style: muted),
                ])),
              ),
            const SizedBox(height: AppSpace.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.s3),
              decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.mdAll),
              child: const Text(
                'Kode Produk,Nama Produk,Kategori,Harga Jual,Modal\nBB03,Air Mineral,Non Coffee,6000,3000',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: AppSpace.s3),
            Text(
              'Produk yang sudah ada (kode atau nama sama) diperbarui, sisanya ditambahkan. '
              'Anda akan melihat ringkasan dulu sebelum disimpan.',
              style: muted,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Pilih file CSV'),
        ),
      ],
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({required this.fileName, required this.result});

  final String fileName;
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final errors = ((result['errors'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final newCategories = ((result['categories_created'] as List?) ?? const []).cast<String>();
    final ok = errors.isEmpty;

    return AlertDialog(
      scrollable: true,
      title: Text(ok ? 'Siap di-import' : 'Ada yang perlu diperbaiki'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(fileName, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpace.s3),
            if (ok) ...[
              AppSummaryRow('Produk baru', '${result['created']}'),
              AppSummaryRow('Produk diperbarui', '${result['updated']}'),
              AppSummaryRow('Kategori baru', '${newCategories.length}'),
              if (newCategories.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s1),
                  child: Text(newCategories.join(', '), style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                ),
            ] else ...[
              Text(
                'Tidak ada yang disimpan. Perbaiki baris berikut di file, lalu import lagi:',
                style: AppType.body.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpace.s2),
              for (final e in errors.take(30))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 72, child: AppBadge('Baris ${e['row']}', tone: AppTone.danger)),
                      const SizedBox(width: AppSpace.s2),
                      Expanded(child: Text('${e['message']}', style: AppType.body)),
                    ],
                  ),
                ),
              if (errors.length > 30)
                Text('…dan ${errors.length - 30} kesalahan lain.', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ok ? 'Batal' : 'Tutup')),
        if (ok) FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
      ],
    );
  }
}
