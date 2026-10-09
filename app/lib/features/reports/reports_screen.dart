import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';
import 'dashboard_charts.dart';

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum _Range { today, week, days30, month }

/// Dashboard owner: angka utama dengan perbandingan periode sebelumnya + grafik penjualan.
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
      _Range.days30 => now.subtract(const Duration(days: 29)),
      _Range.month => DateTime(now.year, now.month),
    };
    final res = await ref.read(sessionProvider.notifier).authed((api, token) =>
        api.get('/reports/summary?from=${_isoDate(from)}&to=${_isoDate(now)}', token: token));
    return res['data'] as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final narrow = context.widthClass != WidthClass.expanded;
    final gutter = compact ? AppSpace.s3 : AppSpace.s5;
    void select(_Range r) => setState(() {
          _range = r;
          _report = _load();
        });
    const labels = {_Range.today: 'Hari ini', _Range.week: '7 hari', _Range.days30: '30 hari', _Range.month: 'Bulan ini'};
    // HP: chip yang bisa digeser (4 tombol segmen tidak muat); layar lebih lebar: tombol segmen.
    final Widget range = compact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final r in _Range.values)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.s2),
                  child: ChoiceChip(
                    label: Text(labels[r]!),
                    showCheckmark: false,
                    selected: _range == r,
                    onSelected: (_) => select(r),
                  ),
                ),
            ]),
          )
        : SegmentedButton<_Range>(
            expandedInsets: narrow ? EdgeInsets.zero : null,
            showSelectedIcon: false,
            segments: [for (final r in _Range.values) ButtonSegment(value: r, label: Text(labels[r]!))],
            selected: {_range},
            onSelectionChanged: (s) => select(s.first),
          );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(gutter, AppSpace.s4, gutter, AppSpace.s3),
        child: Row(children: [
          if (narrow) Expanded(child: range) else range,
          if (!narrow) const Spacer(),
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
            return LayoutBuilder(builder: (context, box) => _Dashboard(
                  report: snap.data!,
                  width: box.maxWidth - gutter * 2,
                  gutter: gutter,
                  range: _range,
                  customersOn: ref.watch(menuProvider).value?.menu.customersOn ?? false,
                  loyaltyUnit: ref.watch(menuProvider).value?.menu.loyalty?.unit,
                ));
          },
        ),
      ),
    ]);
  }
}

const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String _dayLabel(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Isi dashboard owner: KPI dengan perbandingan periode sebelumnya, lalu grafik.
class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.report,
    required this.width,
    required this.gutter,
    required this.range,
    this.customersOn = false,
    this.loyaltyUnit,
  });

  final Map<String, dynamic> report;
  final double width;
  final double gutter;
  final _Range range;

  /// Fitur pelanggan aktif → tampilkan bagian member.
  final bool customersOn;

  /// Satuan program loyalitas yang berjalan ("stempel"/"poin"); null = tidak ada program.
  final String? loyaltyUnit;

  List<Map<String, dynamic>> _list(String key) => ((report[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  String get _previousLabel => switch (range) {
        _Range.today => 'dibanding kemarin',
        _Range.week => 'dibanding 7 hari sebelumnya',
        _Range.days30 => 'dibanding 30 hari sebelumnya',
        _Range.month => 'dibanding periode yang sama sebelumnya',
      };

  @override
  Widget build(BuildContext context) {
    final r = report;
    final prev = (r['previous'] as Map<String, dynamic>?) ?? const {};
    final voids = r['voids'] as Map<String, dynamic>;
    final sales = r['sales'] as int;
    final tax = r['tax'] as int;
    final gp = (r['gross_profit'] as int?) ?? 0;
    final netSales = sales - tax;
    final wide = width >= 720;

    // KPI utama: 2 kolom di HP, 4 di layar lebar.
    final kpiCols = wide ? 4 : 2;
    final kpiWidth = (width - AppSpace.s3 * (kpiCols - 1)) / kpiCols;
    final smallCols = columnsFor(width, minItem: 150, spacing: AppSpace.s3, min: 2, max: 5);
    final smallWidth = (width - AppSpace.s3 * (smallCols - 1)) / smallCols;

    Widget pair(Widget a, Widget? b) => b == null
        ? a
        : wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                const SizedBox(width: AppSpace.s3),
                Expanded(child: b),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: AppSpace.s3), b]);

    // ── tren harian (rentang > 1 hari), hari kosong diisi nol ──
    final today = DateTime.now();
    final from = DateTime.tryParse(r['from'] as String? ?? '') ?? today;
    final to = DateTime.tryParse(r['to'] as String? ?? '') ?? today;
    final byDate = {for (final d in _list('daily')) d['date'] as String: d};
    final trend = <(String, String, int, int)>[
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1)))
        () {
          final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          final row = byDate[key];
          return ('${d.day}/${d.month}', _dayLabel(d), (row?['sales'] as int?) ?? 0, (row?['orders'] as int?) ?? 0);
        }(),
    ];

    // ── jam ramai: tampilkan jam operasional (jam pertama–terakhir yang ada transaksi) ──
    final hourly = _list('hourly');
    final activeHours = [for (final h in hourly) if ((h['orders'] as int) > 0) h['hour'] as int];
    final firstHour = activeHours.isEmpty ? 7 : math.max(0, activeHours.reduce(math.min) - 1);
    final lastHour = activeHours.isEmpty ? 22 : math.min(23, activeHours.reduce(math.max) + 1);
    final hourBars = <(String, String, int, int)>[
      for (final h in hourly)
        if ((h['hour'] as int) >= firstHour && (h['hour'] as int) <= lastHour)
          (
            '${h['hour']}',
            'Pukul ${(h['hour'] as int).toString().padLeft(2, '0')}.00–${((h['hour'] as int) + 1).toString().padLeft(2, '0')}.00',
            h['sales'] as int,
            h['orders'] as int,
          ),
    ];
    final peakHour = hourly.isEmpty ? null : hourly.reduce((a, b) => (b['sales'] as int) > (a['sales'] as int) ? b : a);

    final weekday = _list('weekday');
    final peakDay = weekday.isEmpty ? null : weekday.reduce((a, b) => (b['sales'] as int) > (a['sales'] as int) ? b : a);

    final byMethod = (r['by_method'] as Map<String, dynamic>?) ?? const {};
    final categories = _list('by_category');
    final catTotal = categories.fold<int>(0, (s, c) => s + (c['revenue'] as int));
    final products = _list('top_products');
    final cashiers = _list('by_cashier');
    final hasSales = (r['orders'] as int) > 0;

    String hourRange(int h) => '${h.toString().padLeft(2, '0')}.00–${(h + 1).toString().padLeft(2, '0')}.00';

    final hourCard = AppSectionCard(title: 'Jam ramai', children: [
      if (hasSales && peakHour != null)
        _Caption('Paling ramai pukul ${hourRange(peakHour['hour'] as int)} · ${rp(peakHour['sales'] as int)}'),
      const SizedBox(height: AppSpace.s3),
      hasSales
          ? PeakColumnChart(bars: hourBars, labelEvery: hourBars.length > 12 ? 2 : 1)
          : const _NoData(),
    ]);
    final dayCard = range == _Range.today
        ? null
        : AppSectionCard(title: 'Hari tersibuk', children: [
            if (hasSales && peakDay != null)
              _Caption('Paling ramai hari ${const ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'][(peakDay['day'] as int) - 1]}'
                  ' · ${rp(peakDay['sales'] as int)}'),
            const SizedBox(height: AppSpace.s3),
            hasSales
                ? PeakColumnChart(bars: [
                    for (final d in weekday)
                      (_days[(d['day'] as int) - 1], _days[(d['day'] as int) - 1], d['sales'] as int, d['orders'] as int),
                  ])
                : const _NoData(),
          ]);

    final methodCard = AppSectionCard(title: 'Metode pembayaran', children: [
      ShareBar(parts: [
        ('Tunai', (byMethod['cash'] as int?) ?? 0, ChartColors.cash),
        ('Debit', (byMethod['debit'] as int?) ?? 0, ChartColors.debit),
        ('QRIS', (byMethod['qris'] as int?) ?? 0, ChartColors.qris),
      ]),
    ]);
    final categoryCard = AppSectionCard(title: 'Penjualan per kategori', children: [
      if (categories.isEmpty)
        const _NoData()
      else
        RankedBars(rows: [
          for (final c in categories)
            (
              c['name'] as String,
              c['revenue'] as int,
              rp(c['revenue'] as int),
              '${catTotal > 0 ? (c['revenue'] as int) * 100 ~/ catTotal : 0}% · ${c['qty']} item',
            ),
        ]),
    ]);

    return ListView(padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter), children: [
      _Caption('${_dayLabel(from)}${from == to ? '' : ' – ${_dayLabel(to)}'} · naik/turun $_previousLabel'),
      const SizedBox(height: AppSpace.s3),
      Wrap(spacing: AppSpace.s3, runSpacing: AppSpace.s3, children: [
        KpiTile(label: 'Penjualan', value: rp(sales), current: sales, previous: prev['sales'] as int?, hero: true, width: kpiWidth),
        KpiTile(label: 'Transaksi', value: '${r['orders']}', current: r['orders'] as int, previous: prev['orders'] as int?, width: kpiWidth),
        KpiTile(label: 'Rata-rata / transaksi', value: rp(r['average'] as int), current: r['average'] as int, previous: prev['average'] as int?, width: kpiWidth),
        KpiTile(
          label: 'Laba kotor',
          value: rp(gp),
          current: gp,
          previous: prev['gross_profit'] as int?,
          note: netSales > 0 ? 'margin ${(gp * 100 / netSales).round()}%' : null,
          width: kpiWidth,
        ),
      ]),
      const SizedBox(height: AppSpace.s3),
      Wrap(spacing: AppSpace.s3, runSpacing: AppSpace.s3, children: [
        AppStatCard('HPP (modal)', rp((r['cost'] as int?) ?? 0), width: smallWidth),
        AppStatCard('Diskon', rp(r['discounts'] as int), width: smallWidth),
        if ((r['service'] as int) > 0) AppStatCard('Service', rp(r['service'] as int), width: smallWidth),
        if (tax > 0) AppStatCard('Pajak', rp(tax), width: smallWidth),
        AppStatCard('Void', '${voids['orders']} · ${rp(voids['refunded'] as int)}', width: smallWidth),
      ]),
      if (((r['cost_missing_items'] as int?) ?? 0) > 0) _MissingCostNote(count: r['cost_missing_items'] as int),
      if (trend.length > 1) ...[
        const SizedBox(height: AppSpace.s4),
        AppSectionCard(title: 'Tren penjualan', children: [
          _Caption('Total ${rp(sales)} dalam ${trend.length} hari · sentuh grafik untuk detail per hari'),
          const SizedBox(height: AppSpace.s3),
          SalesTrendChart(points: trend),
        ]),
      ],
      const SizedBox(height: AppSpace.s3),
      pair(hourCard, dayCard),
      const SizedBox(height: AppSpace.s3),
      pair(methodCard, categoryCard),
      const SizedBox(height: AppSpace.s3),
      pair(
        AppSectionCard(title: 'Produk terlaris', children: [
          if (products.isEmpty)
            const _NoData()
          else
            RankedBars(rows: [
              for (final p in products)
                (
                  p['name'] as String,
                  p['qty'] as int,
                  '${p['qty']}×',
                  p['profit'] == null ? rp(p['revenue'] as int) : '${rp(p['revenue'] as int)} · laba ${rp(p['profit'] as int)}',
                ),
            ]),
        ]),
        AppSectionCard(title: 'Kasir', children: [
          if (cashiers.isEmpty)
            const _NoData()
          else
            RankedBars(rows: [
              for (final c in cashiers) (c['name'] as String, c['sales'] as int, rp(c['sales'] as int), '${c['orders']} transaksi'),
            ]),
        ]),
      ),
      if (customersOn) ...[
        const SizedBox(height: AppSpace.s3),
        _customerCards(r, pair),
      ],
      if (customersOn && _list('by_tier').isNotEmpty) ...[
        const SizedBox(height: AppSpace.s3),
        AppSectionCard(title: 'Penjualan per tingkat member', children: [
          RankedBars(rows: [
            for (final t in _list('by_tier'))
              (
                t['name'] as String,
                t['sales'] as int,
                rp(t['sales'] as int),
                '${t['customers']} member · ${t['orders']} transaksi · diskon ${rp(t['discount'] as int)}',
              ),
          ]),
        ]),
      ],
      if (customersOn && loyaltyUnit != null) ...[
        const SizedBox(height: AppSpace.s3),
        _loyaltyCard(r, loyaltyUnit!, smallWidth),
      ],
      const SizedBox(height: AppSpace.s3),
      Text('Penjualan = order lunas (void tidak dihitung). Laba kotor = penjualan − pajak − HPP; margin = laba kotor ÷ (penjualan − pajak).',
          style: AppType.caption.copyWith(color: AppColors.inkMuted)),
    ]);
  }
}

/// Member vs non-member (porsi penjualan) + pelanggan teratas. Member = warna utama,
/// non-member = abu-abu (penekanan pada member); label & nilai selalu tertulis.
Widget _customerCards(Map<String, dynamic> r, Widget Function(Widget, Widget?) pair) {
  final c = (r['customers'] as Map<String, dynamic>?) ?? const {};
  final orders = r['orders'] as int;
  final sales = r['sales'] as int;
  final memberOrders = (c['orders'] as int?) ?? 0;
  final memberSales = (c['sales'] as int?) ?? 0;
  final top = ((c['top'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final share = orders > 0 ? memberOrders * 100 ~/ orders : 0;

  return pair(
    AppSectionCard(title: 'Pelanggan member', children: [
      if (orders == 0)
        const _NoData()
      else ...[
        _Caption('$memberOrders dari $orders transaksi ($share%) oleh member · '
            '${c['active'] ?? 0} member belanja: ${c['new'] ?? 0} baru, ${c['returning'] ?? 0} kembali'),
        const SizedBox(height: AppSpace.s3),
        ShareBar(parts: [
          ('Member', memberSales, ChartColors.series),
          ('Non-member', sales - memberSales, ChartColors.muted),
        ]),
      ],
    ]),
    AppSectionCard(title: 'Pelanggan teratas', empty: 'Belum ada transaksi member di periode ini.', children: [
      if (top.isNotEmpty)
        RankedBars(rows: [
          for (final t in top) ('${t['name']} · ${t['code']}', t['sales'] as int, rp(t['sales'] as int), '${t['orders']} transaksi'),
        ]),
    ]),
  );
}

/// Program loyalitas: stempel/poin yang keluar vs ditukar, dan hadiah yang paling sering ditukar.
Widget _loyaltyCard(Map<String, dynamic> r, String unit, double tileWidth) {
  final l = (r['loyalty'] as Map<String, dynamic>?) ?? const {};
  final rewards = ((l['rewards'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final discount = rewards.fold<int>(0, (s, x) => s + (x['discount'] as int));
  return AppSectionCard(title: 'Program loyalitas', children: [
    Wrap(spacing: AppSpace.s3, runSpacing: AppSpace.s3, children: [
      AppStatCard('${unit[0].toUpperCase()}${unit.substring(1)} keluar', '${l['earned'] ?? 0}', width: tileWidth),
      AppStatCard('Ditukar', '${l['redeemed'] ?? 0}', width: tileWidth),
      AppStatCard('Nilai hadiah', rp(discount), width: tileWidth),
    ]),
    const SizedBox(height: AppSpace.s3),
    if (rewards.isEmpty)
      const _Caption('Belum ada hadiah ditukar di periode ini.')
    else
      RankedBars(rows: [
        for (final x in rewards) (x['name'] as String, x['count'] as int, '${x['count']}×', 'potongan ${rp(x['discount'] as int)}'),
      ]),
  ]);
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppType.caption.copyWith(color: AppColors.inkMuted));
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
        child: Text('Belum ada penjualan di periode ini.', style: AppType.body.copyWith(color: AppColors.inkMuted)),
      );
}

class _MissingCostNote extends StatelessWidget {
  const _MissingCostNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: AppSpace.s3),
        padding: const EdgeInsets.all(AppSpace.s3),
        decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.warning),
          const SizedBox(width: AppSpace.s2),
          Expanded(
            child: Text(
              '$count item terjual belum punya harga modal, jadi laba kotor terlihat lebih besar dari sebenarnya. '
              'Isi modal di Kelola Menu (berlaku untuk penjualan berikutnya).',
              style: AppType.body.copyWith(color: AppColors.warning),
            ),
          ),
        ]),
      );
}
