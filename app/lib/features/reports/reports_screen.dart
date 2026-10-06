import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../session/session_controller.dart';

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum _Range { today, week, month }

/// Laporan penjualan untuk owner.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Range _range = _Range.today;
  late Future<Map<String, dynamic>> _report = _load();

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();
    final from = switch (_range) {
      _Range.today => now,
      _Range.week => now.subtract(const Duration(days: 6)),
      _Range.month => DateTime(now.year, now.month),
    };
    final res = await ref.read(sessionProvider.notifier).authed((api, token) =>
        api.get('/reports/summary?from=${_isoDate(from)}&to=${_isoDate(now)}', token: token));
    return res['data'] as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final gutter = compact ? AppSpace.s3 : AppSpace.s5;
    final range = SegmentedButton<_Range>(
      // HP: tombol rentang mengisi lebar layar.
      expandedInsets: compact ? EdgeInsets.zero : null,
      showSelectedIcon: !compact,
      segments: [
        const ButtonSegment(value: _Range.today, label: Text('Hari ini')),
        const ButtonSegment(value: _Range.week, label: Text('7 hari')),
        ButtonSegment(value: _Range.month, label: Text(compact ? 'Bulan' : 'Bulan ini')),
      ],
      selected: {_range},
      onSelectionChanged: (s) => setState(() {
        _range = s.first;
        _report = _load();
      }),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.s4, gutter, AppSpace.s3),
        child: Row(children: [
          if (compact) Expanded(child: range) else range,
          if (!compact) const Spacer(),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => setState(() => _report = _load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _report,
          builder: (context, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return AppErrorState(
                message: e is ApiException ? e.message : '$e',
                onRetry: () => setState(() => _report = _load()),
              );
            }
            if (!snap.hasData) return const AppLoading();
            final r = snap.data!;
            final byMethod = r['by_method'] as Map<String, dynamic>;
            final voids = r['voids'] as Map<String, dynamic>;

            final byMethodCard = AppSectionCard(title: 'Per metode bayar', children: [
              for (final m in const [('cash', 'Tunai'), ('debit', 'Debit'), ('qris', 'QRIS')])
                AppSummaryRow(m.$2, rp(byMethod[m.$1] as int)),
            ]);
            final byCashierCard = AppSectionCard(title: 'Per kasir', children: [
              for (final c in (r['by_cashier'] as List).cast<Map<String, dynamic>>())
                AppSummaryRow('${c['name']} (${c['orders']})', rp(c['sales'] as int)),
            ]);

            return LayoutBuilder(builder: (context, box) {
              final width = box.maxWidth - gutter * 2;
              // Kartu angka: 2 kolom di HP, bertambah sesuai lebar (min ±170 dp per kartu).
              final cols = columnsFor(width, minItem: 170, spacing: AppSpace.s3, min: 2, max: 5);
              final cardWidth = (width - AppSpace.s3 * (cols - 1)) / cols;
              return ListView(padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter), children: [
              Wrap(spacing: AppSpace.s3, runSpacing: AppSpace.s3, children: [
                AppStatCard('Penjualan', rp(r['sales'] as int), emphasis: true, width: cardWidth),
                AppStatCard('Order lunas', '${r['orders']}', width: cardWidth),
                AppStatCard('Rata-rata / order', rp(r['average'] as int), width: cardWidth),
                AppStatCard('Diskon', rp(r['discounts'] as int), width: cardWidth),
                if ((r['service'] as int) > 0) AppStatCard('Service', rp(r['service'] as int), width: cardWidth),
                if ((r['tax'] as int) > 0) AppStatCard('Pajak', rp(r['tax'] as int), width: cardWidth),
                AppStatCard('Void', '${voids['orders']} order · ${rp(voids['refunded'] as int)}', width: cardWidth),
              ]),
              const SizedBox(height: AppSpace.s4),
              if (width < 560) ...[
                byMethodCard,
                const SizedBox(height: AppSpace.s3),
                byCashierCard,
              ] else
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: byMethodCard),
                  const SizedBox(width: AppSpace.s3),
                  Expanded(child: byCashierCard),
                ]),
              const SizedBox(height: AppSpace.s3),
              AppSectionCard(title: 'Produk terlaris', children: [
                for (final p in (r['top_products'] as List).cast<Map<String, dynamic>>())
                  AppSummaryRow('${p['qty']}× ${p['name']}', rp(p['revenue'] as int)),
              ]),
              if ((r['daily'] as List).length > 1) ...[
                const SizedBox(height: AppSpace.s3),
                AppSectionCard(title: 'Per hari', children: [
                  for (final d in (r['daily'] as List).cast<Map<String, dynamic>>())
                    AppSummaryRow('${d['date']} (${d['orders']})', rp(d['sales'] as int)),
                ]),
              ],
              const SizedBox(height: AppSpace.s3),
              Text('Penjualan = order lunas (void tidak dihitung).',
                  style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ]);
            });
          },
        ),
      ),
    ]);
  }
}
