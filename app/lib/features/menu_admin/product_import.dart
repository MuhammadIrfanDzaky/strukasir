import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/csv_import.dart';
import 'menu_admin_api.dart';

/// Import produk dari CSV (mis. export dari POS lama). Alur umum di [importCsv].
Future<void> importProducts(BuildContext context, WidgetRef ref) {
  final api = ref.read(menuAdminApiProvider);
  return importCsv(
    context,
    CsvImportSpec(
      title: 'Import produk dari CSV',
      columns: const [
        ('Nama Produk', 'wajib'),
        ('Harga Jual', 'wajib, mis. 18000 atau Rp 18.000'),
        ('Kategori', 'kategori baru dibuat otomatis'),
        ('Kode Produk', 'opsional, mis. BB03'),
        ('Modal / HPP', 'opsional'),
        ('Aktif, Favorit', 'opsional, isi ya / tidak'),
      ],
      example: 'Kode Produk,Nama Produk,Kategori,Harga Jual,Modal\nBB03,Air Mineral,Non Coffee,6000,3000',
      note: 'Produk yang sudah ada (kode atau nama sama) diperbarui, sisanya ditambahkan.',
      run: (csv, dryRun) => api.importProducts(csv, dryRun: dryRun),
      summary: (result) {
        final newCategories = ((result['categories_created'] as List?) ?? const []).cast<String>();
        return [
          AppSummaryRow('Produk baru', '${result['created']}'),
          AppSummaryRow('Produk diperbarui', '${result['updated']}'),
          AppSummaryRow('Kategori baru', '${newCategories.length}'),
          if (newCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s1),
              child: Text(newCategories.join(', '), style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ),
        ];
      },
      doneMessage: (result) => 'Import selesai: ${result['created']} produk baru, ${result['updated']} diperbarui.',
    ),
  );
}
