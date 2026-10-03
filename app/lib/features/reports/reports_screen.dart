import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
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
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          SegmentedButton<_Range>(
            segments: const [
              ButtonSegment(value: _Range.today, label: Text('Hari ini')),
              ButtonSegment(value: _Range.week, label: Text('7 hari')),
              ButtonSegment(value: _Range.month, label: Text('Bulan ini')),
            ],
            selected: {_range},
            onSelectionChanged: (s) => setState(() {
              _range = s.first;
              _report = _load();
            }),
          ),
          const Spacer(),
          IconButton(onPressed: () => setState(() => _report = _load()), icon: const Icon(Icons.refresh)),
        ]),
      ),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _report,
          builder: (context, snap) {
            if (snap.hasError) {
              final e = snap.error;
              return Center(child: Text(e is ApiException ? e.message : '$e'));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final r = snap.data!;
            final byMethod = r['by_method'] as Map<String, dynamic>;
            final voids = r['voids'] as Map<String, dynamic>;

            return ListView(padding: const EdgeInsets.all(12), children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                _Stat('Penjualan', rp(r['sales'] as int), emphasis: true),
                _Stat('Order lunas', '${r['orders']}'),
                _Stat('Rata-rata / order', rp(r['average'] as int)),
                _Stat('Diskon', rp(r['discounts'] as int)),
                if ((r['service'] as int) > 0) _Stat('Service', rp(r['service'] as int)),
                if ((r['tax'] as int) > 0) _Stat('Pajak', rp(r['tax'] as int)),
                _Stat('Void', '${voids['orders']} order · ${rp(voids['refunded'] as int)}'),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: _Section('Per metode bayar', [
                    for (final m in const [('cash', 'Tunai'), ('debit', 'Debit'), ('qris', 'QRIS')])
                      _Row(m.$2, rp(byMethod[m.$1] as int)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Section('Per kasir', [
                    for (final c in (r['by_cashier'] as List).cast<Map<String, dynamic>>())
                      _Row('${c['name']} (${c['orders']})', rp(c['sales'] as int)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              _Section('Produk terlaris', [
                for (final p in (r['top_products'] as List).cast<Map<String, dynamic>>())
                  _Row('${p['qty']}× ${p['name']}', rp(p['revenue'] as int)),
              ]),
              if ((r['daily'] as List).length > 1) ...[
                const SizedBox(height: 12),
                _Section('Per hari', [
                  for (final d in (r['daily'] as List).cast<Map<String, dynamic>>())
                    _Row('${d['date']} (${d['orders']})', rp(d['sales'] as int)),
                ]),
              ],
              const SizedBox(height: 8),
              Text('Penjualan = order lunas (void tidak dihitung).', style: theme.textTheme.bodySmall),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        color: emphasis ? theme.colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: emphasis ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (children.isEmpty) const Text('Belum ada data.') else ...children,
          ]),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(label)), Text(value)]),
      );
}
