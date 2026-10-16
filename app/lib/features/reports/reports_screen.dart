import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../inventory/inventory_models.dart';
import '../inventory/inventory_screen.dart';
import '../menu/menu_controller.dart';
import '../outlets/outlets_screen.dart';
import '../session/session_controller.dart';
import '../subscription/locked_feature.dart';
import 'dashboard_charts.dart';
import '../../core/ui/toast.dart';

String _isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum _Range { today, week, days30, month }

/// Dashboard owner: angka utama dengan perbandingan periode sebelumnya + grafik penjualan.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Range _range = _Range.today;

  /// Multi-outlet: null = semua outlet.
  String? _outlet;
  late Future<Map<String, dynamic>> _report = _load();

  String get _outletQuery => _outlet == null ? '' : '&outlet=$_outlet';

  (DateTime, DateTime) get _period {
    final now = DateTime.now();
    final from = switch (_range) {
      _Range.today => now,
      _Range.week => now.subtract(const Duration(days: 6)),
      _Range.days30 => now.subtract(const Duration(days: 29)),
      _Range.month => DateTime(now.year, now.month),
    };
    return (from, now);
  }

  Future<Map<String, dynamic>> _load() async {
    final (from, to) = _period;
    final res = await ref
        .read(sessionProvider.notifier)
        .authed((api, token) => api.get('/reports/summary?from=${_isoDate(from)}&to=${_isoDate(to)}$_outletQuery', token: token));
    return res['data'] as Map<String, dynamic>;
  }

  /// Unduh CSV periode yang sedang dilihat: tautan bertanda tangan dibuka di browser → folder Download.
  Future<void> _export() async {
    final (from, to) = _period;
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s4, 0, AppSpace.s4, AppSpace.s2),
                child: Text('Unduh CSV (Excel / Google Sheets) · ${_isoDate(from)} s/d ${_isoDate(to)}', style: AppType.bodyStrong),
              ),
              for (final (key, label, sub) in const [
                ('orders', 'Penjualan per transaksi', 'Nomor, kasir, pelanggan, total, metode bayar'),
                ('items', 'Penjualan per item', 'Produk, kategori, qty, diskon, modal'),
                ('tax', 'Rekap pajak (PB1) per hari', 'Untuk lapor pajak daerah'),
                ('cash', 'Kas keluar / masuk', 'Pengeluaran & setoran per shift'),
              ])
                ListTile(title: Text(label), subtitle: Text(sub), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.pop(context, key)),
              const SizedBox(height: AppSpace.s2),
            ],
          ),
        ),
      ),
    );
    if (type == null || !mounted) return;
    final messenger = AppToast.of(context);
    try {
      final res = await ref
          .read(sessionProvider.notifier)
          .authed(
            (api, token) =>
                api.post('/reports/export-link', token: token, data: {'type': type, 'from': _isoDate(from), 'to': _isoDate(to), 'outlet': ?_outlet}),
          );
      final ok = await launchUrl(Uri.parse((res['data'] as Map)['url'] as String), mode: LaunchMode.externalApplication);
      messenger.showSnackBar(
        SnackBar(content: Text(ok ? 'Mengunduh di browser. File tersimpan di folder Download.' : 'Browser tidak bisa dibuka di perangkat ini.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
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
            child: Row(
              children: [
                for (final r in _Range.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.s2),
                    child: ChoiceChip(label: Text(labels[r]!), showCheckmark: false, selected: _range == r, onSelected: (_) => select(r)),
                  ),
              ],
            ),
          )
        : SegmentedButton<_Range>(
            expandedInsets: narrow ? EdgeInsets.zero : null,
            showSelectedIcon: false,
            segments: [for (final r in _Range.values) ButtonSegment(value: r, label: Text(labels[r]!))],
            selected: {_range},
            onSelectionChanged: (s) => select(s.first),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.s4, gutter, AppSpace.s3),
          child: Row(
            children: [
              if (narrow) Expanded(child: range) else range,
              if (!narrow) const Spacer(),
              if (!compact && (ref.watch(menuProvider).value?.menu.multiOutlet ?? false))
                OutletPicker(
                  value: _outlet,
                  allLabel: 'Semua outlet',
                  onChanged: (v) => setState(() {
                    _outlet = v;
                    _report = _load();
                  }),
                ),
              IconButton(tooltip: 'Unduh CSV / Excel', onPressed: _export, icon: const Icon(Icons.download_rounded)),
              IconButton(tooltip: 'Muat ulang', onPressed: () => setState(() => _report = _load()), icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
        ),
        // HP: pilihan outlet di baris sendiri (baris atas sudah penuh).
        if (compact && (ref.watch(menuProvider).value?.menu.multiOutlet ?? false))
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpace.s2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutletPicker(
                value: _outlet,
                allLabel: 'Semua outlet',
                maxWidth: 280,
                onChanged: (v) => setState(() {
                  _outlet = v;
                  _report = _load();
                }),
              ),
            ),
          ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _report,
            builder: (context, snap) {
              if (snap.hasError) {
                final e = snap.error;
                return AppErrorState(message: e is ApiException ? e.message : '$e', onRetry: () => setState(() => _report = _load()));
              }
              if (!snap.hasData) return const AppLoading();
              return LayoutBuilder(
                builder: (context, box) => _Dashboard(
                  report: snap.data!,
                  width: box.maxWidth - gutter * 2,
                  gutter: gutter,
                  range: _range,
                  customersOn: ref.watch(menuProvider).value?.menu.customersOn ?? false,
                  loyaltyUnit: ref.watch(menuProvider).value?.menu.loyalty?.unit,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String _dayLabel(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// Isi dashboard owner: KPI dengan perbandingan periode sebelumnya, lalu grafik.
class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.report, required this.width, required this.gutter, required this.range, this.customersOn = false, this.loyaltyUnit});

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

    // KPI utama: 2 kolom di HP, 4 di layar lebar; angka kecil: 2 kolom di HP, sebaris di layar lebar.
    final kpiCols = wide ? 4 : 2;
    final stripCols = wide ? 5 : 2;

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
    final activeHours = [
      for (final h in hourly)
        if ((h['orders'] as int) > 0) h['hour'] as int,
    ];
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

    final hourCard = DashPanel(
      title: 'Jam ramai',
      subtitle: hasSales && peakHour != null ? 'Puncak ${hourRange(peakHour['hour'] as int)} · ${rp(peakHour['sales'] as int)}' : null,
      children: [hasSales ? PeakColumnChart(bars: hourBars, labelEvery: hourBars.length > 12 ? 2 : 1) : const _NoData()],
    );
    final dayCard = range == _Range.today
        ? null
        : DashPanel(
            title: 'Hari tersibuk',
            subtitle: hasSales && peakDay != null
                ? 'Puncak hari ${const ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'][(peakDay['day'] as int) - 1]}'
                      ' · ${rp(peakDay['sales'] as int)}'
                : null,
            children: [
              hasSales
                  ? PeakColumnChart(
                      bars: [for (final d in weekday) (_days[(d['day'] as int) - 1], _days[(d['day'] as int) - 1], d['sales'] as int, d['orders'] as int)],
                    )
                  : const _NoData(),
            ],
          );

    final methodCard = DashPanel(
      title: 'Metode pembayaran',
      subtitle: 'Uang masuk per cara bayar',
      children: [
        ShareBar(
          parts: [
            ('Tunai', (byMethod['cash'] as int?) ?? 0, ChartColors.cash),
            ('Debit', (byMethod['debit'] as int?) ?? 0, ChartColors.debit),
            ('QRIS', (byMethod['qris'] as int?) ?? 0, ChartColors.qris),
            if (((byMethod['credit'] as int?) ?? 0) > 0) ('Kasbon', byMethod['credit'] as int, ChartColors.credit),
          ],
        ),
      ],
    );

    // ── laba-rugi ──
    final expenses = (r['expenses'] as Map?)?.cast<String, dynamic>() ?? const {};
    final expenseTotal = expenses['total'] as int? ?? 0;
    final stock = (r['stock'] as Map?)?.cast<String, dynamic>();
    final stockLoss = stock?['loss'] as int? ?? 0;
    final hasNet = expenseTotal > 0 || stockLoss != 0;
    final statementCard = DashPanel(
      title: 'Laba rugi',
      subtitle: 'Dari penjualan sampai laba ${hasNet ? 'bersih' : 'kotor'}',
      children: [
        ProfitStatement(
          lines: [
            (label: 'Penjualan', amount: sales, kind: '+', note: '${r['orders']} transaksi'),
            if (tax > 0) (label: 'Pajak', amount: tax, kind: '-', note: 'disetor, bukan milik usaha'),
            (label: 'HPP (modal)', amount: (r['cost'] as int?) ?? 0, kind: '-', note: null),
            (label: 'Laba kotor', amount: gp, kind: '=', note: netSales > 0 ? 'margin ${(gp * 100 / netSales).round()}%' : null),
            if (expenseTotal > 0) (label: 'Pengeluaran', amount: expenseTotal, kind: '-', note: 'kas keluar'),
            if (stockLoss != 0) (label: 'Kerugian stok', amount: stockLoss, kind: '-', note: 'terbuang & susut'),
            if (hasNet) (label: 'Laba bersih', amount: r['net_profit'] as int, kind: '=', note: null),
          ],
        ),
      ],
    );
    final expenseCard = (expenses['by_category'] as List?)?.isNotEmpty ?? false
        ? DashPanel(
            title: 'Pengeluaran',
            subtitle: 'Kas keluar · setor ke owner ${rp((expenses['withdrawals'] as int?) ?? 0)} tidak dihitung',
            children: [
              RankedBars(
                rows: [
                  for (final e in (expenses['by_category'] as List).cast<Map<String, dynamic>>())
                    (e['label'] as String, e['total'] as int, rp(e['total'] as int), null),
                ],
              ),
            ],
          )
        : null;

    final productCard = DashPanel(
      title: 'Produk terlaris',
      subtitle: 'Jumlah terjual',
      children: [
        if (products.isEmpty)
          const _NoData()
        else
          RankedBars(
            limit: 8,
            rows: [
              for (final p in products)
                (
                  p['name'] as String,
                  p['qty'] as int,
                  '${p['qty']}×',
                  p['profit'] == null ? rp(p['revenue'] as int) : '${rp(p['revenue'] as int)} · laba ${rp(p['profit'] as int)}',
                ),
            ],
          ),
      ],
    );
    final categoryCard = DashPanel(
      title: 'Per kategori',
      subtitle: 'Porsi omzet',
      children: [
        if (categories.isEmpty)
          const _NoData()
        else
          RankedBars(
            limit: 8,
            rows: [
              for (final c in categories)
                (
                  c['name'] as String,
                  c['revenue'] as int,
                  rp(c['revenue'] as int),
                  '${catTotal > 0 ? (c['revenue'] as int) * 100 ~/ catTotal : 0}% · ${c['qty']} item',
                ),
            ],
          ),
      ],
    );
    final cashierCard = DashPanel(
      title: 'Kasir',
      subtitle: 'Penjualan per kasir',
      children: [
        if (cashiers.isEmpty)
          const _NoData()
        else
          RankedBars(rows: [for (final c in cashiers) (c['name'] as String, c['sales'] as int, rp(c['sales'] as int), '${c['orders']} transaksi')]),
      ],
    );
    final outletCard = r['by_outlet'] is List
        ? DashPanel(
            title: 'Per outlet',
            subtitle: 'Penjualan tiap outlet',
            children: [
              RankedBars(
                rows: [
                  for (final o in (r['by_outlet'] as List).cast<Map<String, dynamic>>())
                    (o['name'] as String, o['sales'] as int, rp(o['sales'] as int), '${o['orders']} transaksi'),
                ],
              ),
            ],
          )
        : null;
    final promos = (r['promotions'] as Map?)?.cast<String, dynamic>() ?? const {};
    final promoCard = ((promos['promos'] as List?)?.isNotEmpty ?? false) || ((promos['vouchers'] as List?)?.isNotEmpty ?? false)
        ? DashPanel(
            title: 'Promo & voucher',
            subtitle: 'Potongan yang terpakai',
            children: [
              RankedBars(
                rows: [
                  for (final p in ((promos['promos'] as List?) ?? const []).cast<Map<String, dynamic>>())
                    (p['name'] as String, p['discount'] as int, '-${rp(p['discount'] as int)}', '${p['qty']} item'),
                  for (final v in ((promos['vouchers'] as List?) ?? const []).cast<Map<String, dynamic>>())
                    ('Voucher ${v['code']}', v['discount'] as int, '-${rp(v['discount'] as int)}', '${v['orders']} transaksi'),
                ],
              ),
            ],
          )
        : null;

    final credit = (r['credit'] as Map?)?.cast<String, dynamic>();
    final creditCard = customersOn && credit != null && ((credit['outstanding'] as int? ?? 0) > 0 || (credit['issued'] as int? ?? 0) > 0)
        ? DashPanel(
            title: 'Kasbon / piutang',
            subtitle: 'Piutang sekarang ${rp(credit['outstanding'] as int)} · ${credit['debtors']} member',
            children: [
              _MiniStats(items: [('Kasbon baru', rp(credit['issued'] as int)), ('Dilunasi', rp(credit['repaid'] as int))]),
              const SizedBox(height: AppSpace.s3),
              RankedBars(
                rows: [
                  for (final d in (credit['top'] as List).cast<Map<String, dynamic>>())
                    ('${d['name']} · ${d['code']}', d['balance'] as int, rp(d['balance'] as int), 'sisa kasbon'),
                ],
              ),
            ],
          )
        : null;
    final tierCard = customersOn && _list('by_tier').isNotEmpty
        ? DashPanel(
            title: 'Per tingkat member',
            subtitle: 'Penjualan & diskon tingkat',
            children: [
              RankedBars(
                rows: [
                  for (final t in _list('by_tier'))
                    (
                      t['name'] as String,
                      t['sales'] as int,
                      rp(t['sales'] as int),
                      '${t['customers']} member · ${t['orders']} transaksi · diskon ${rp(t['discount'] as int)}',
                    ),
                ],
              ),
            ],
          )
        : null;

    final cols = wide ? 2 : 1;
    final stripItems = <(String, String)>[
      ('Diskon', rp(r['discounts'] as int)),
      if ((r['service'] as int) > 0) ('Service', rp(r['service'] as int)),
      if (tax > 0) ('Pajak', rp(tax)),
      ('Void', '${voids['orders']} · ${rp(voids['refunded'] as int)}'),
      if ((r['rounding'] as int? ?? 0) != 0) ('Pembulatan', rp(r['rounding'] as int)),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
      children: [
        DashSection('Ringkasan', caption: '${_dayLabel(from)}${from == to ? '' : ' – ${_dayLabel(to)}'} · $_previousLabel'),
        KpiGrid(
          columns: kpiCols,
          height: wide ? 148 : 156,
          children: [
            KpiTile(label: 'Penjualan', value: rp(sales), current: sales, previous: prev['sales'] as int?, hero: true),
            KpiTile(label: 'Transaksi', value: '${r['orders']}', current: r['orders'] as int, previous: prev['orders'] as int?),
            KpiTile(label: 'Rata-rata / transaksi', value: rp(r['average'] as int), current: r['average'] as int, previous: prev['average'] as int?),
            KpiTile(
              label: 'Laba kotor',
              value: rp(gp),
              current: gp,
              previous: prev['gross_profit'] as int?,
              note: netSales > 0 ? 'margin ${(gp * 100 / netSales).round()}%' : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s3),
        MetricStrip(items: stripItems, columns: math.min(stripItems.length, stripCols)),
        if (((r['cost_missing_items'] as int?) ?? 0) > 0) _MissingCostNote(count: r['cost_missing_items'] as int),
        const DashSection('Keuangan'),
        DashGrid(
          columns: cols,
          children: [
            statementCard,
            methodCard,
            ?expenseCard,
            if (stock != null) _StockCard(stock: stock),
          ],
        ),
        const DashSection('Pola penjualan'),
        if (trend.length > 1) ...[
          DashPanel(
            title: 'Tren penjualan',
            subtitle: 'Total ${rp(sales)} dalam ${trend.length} hari · sentuh grafik untuk detail',
            children: [SalesTrendChart(points: trend)],
          ),
          const SizedBox(height: AppSpace.s3),
        ],
        DashGrid(columns: cols, children: [hourCard, ?dayCard]),
        const DashSection('Produk & tim'),
        DashGrid(columns: cols, children: [productCard, categoryCard, cashierCard, ?outletCard, ?promoCard]),
        if (customersOn) ...[
          const DashSection('Pelanggan'),
          DashGrid(columns: cols, children: [..._customerCards(r), ?creditCard, ?tierCard, if (loyaltyUnit != null) _loyaltyCard(r, loyaltyUnit!)]),
        ],
        // Owner di paket tanpa stok / member: laporan yang bisa dibuka dengan upgrade.
        const Padding(
          padding: EdgeInsets.only(top: AppSpace.s6),
          child: LockedFeaturesPanel(
            title: 'Laporan lain di paket lebih tinggi',
            keys: ['inventory', 'member_tiers', 'loyalty', 'customer_credit', 'multi_outlet'],
          ),
        ),
        const SizedBox(height: AppSpace.s4),
        Text(
          'Penjualan = order lunas (void tidak dihitung). Laba kotor = penjualan − pajak − HPP; margin = laba kotor ÷ (penjualan − pajak).',
          style: AppType.caption.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
  }
}

/// Member vs non-member (porsi penjualan) + pelanggan teratas. Member = warna utama,
/// non-member = abu-abu (penekanan pada member); label & nilai selalu tertulis.
List<Widget> _customerCards(Map<String, dynamic> r) {
  final c = (r['customers'] as Map<String, dynamic>?) ?? const {};
  final orders = r['orders'] as int;
  final sales = r['sales'] as int;
  final memberOrders = (c['orders'] as int?) ?? 0;
  final memberSales = (c['sales'] as int?) ?? 0;
  final top = ((c['top'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final share = orders > 0 ? memberOrders * 100 ~/ orders : 0;

  return [
    DashPanel(
      title: 'Pelanggan member',
      subtitle: orders == 0 ? null : '$memberOrders dari $orders transaksi ($share%) oleh member',
      children: [
        if (orders == 0)
          const _NoData()
        else ...[
          _MiniStats(items: [('Member belanja', '${c['active'] ?? 0}'), ('Baru', '${c['new'] ?? 0}'), ('Kembali', '${c['returning'] ?? 0}')]),
          const SizedBox(height: AppSpace.s3),
          ShareBar(parts: [('Member', memberSales, ChartColors.series), ('Non-member', sales - memberSales, ChartColors.muted)]),
        ],
      ],
    ),
    DashPanel(
      title: 'Pelanggan teratas',
      subtitle: 'Belanja terbanyak',
      empty: 'Belum ada transaksi member di periode ini.',
      children: [
        if (top.isNotEmpty)
          RankedBars(rows: [for (final t in top) ('${t['name']} · ${t['code']}', t['sales'] as int, rp(t['sales'] as int), '${t['orders']} transaksi')]),
      ],
    ),
  ];
}

/// Program loyalitas: stempel/poin yang keluar vs ditukar, dan hadiah yang paling sering ditukar.
Widget _loyaltyCard(Map<String, dynamic> r, String unit) {
  final l = (r['loyalty'] as Map<String, dynamic>?) ?? const {};
  final rewards = ((l['rewards'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final discount = rewards.fold<int>(0, (s, x) => s + (x['discount'] as int));
  return DashPanel(
    title: 'Program loyalitas',
    subtitle: 'Hadiah ditukar senilai ${rp(discount)}',
    children: [
      _MiniStats(items: [('${unit[0].toUpperCase()}${unit.substring(1)} keluar', '${l['earned'] ?? 0}'), ('Ditukar', '${l['redeemed'] ?? 0}')]),
      const SizedBox(height: AppSpace.s3),
      if (rewards.isEmpty)
        const _Caption('Belum ada hadiah ditukar di periode ini.')
      else
        RankedBars(rows: [for (final x in rewards) (x['name'] as String, x['count'] as int, '${x['count']}×', 'potongan ${rp(x['discount'] as int)}')]),
    ],
  );
}

/// Angka kecil sejajar di dalam panel (latar lembut, dibagi rata).
class _MiniStats extends StatelessWidget {
  const _MiniStats({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, it) in items.indexed) ...[
        if (i > 0) const SizedBox(width: AppSpace.s2),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s3, vertical: AppSpace.s2),
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: AppRadius.mdAll),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: AppColors.inkMuted),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(it.$2, style: AppType.bodyStrong),
                ),
              ],
            ),
          ),
        ),
      ],
    ],
  );
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '$count item terjual belum punya harga modal, jadi laba kotor terlihat lebih besar dari sebenarnya. '
            'Isi modal di Kelola Menu (berlaku untuk penjualan berikutnya).',
            style: AppType.body.copyWith(color: AppColors.warning),
          ),
        ),
      ],
    ),
  );
}

/// Stok bahan (fitur `inventory`): pembelian & kerugian di periode, nilai stok & bahan menipis sekarang.
class _StockCard extends ConsumerWidget {
  const _StockCard({required this.stock});

  final Map<String, dynamic> stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final low = (stock['low'] as List? ?? const []).cast<Map<String, dynamic>>();
    final canManage = ((ref.watch(sessionProvider).value as LoggedIn?)?.user.can('inventory.manage')) ?? false;
    final countDiff = stock['count_diff'] as int? ?? 0;
    return DashPanel(
      title: 'Stok bahan',
      subtitle: 'Kerugian stok mengurangi laba bersih',
      trailing: canManage
          ? TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InventoryScreen())),
              child: const Text('Buka'),
            )
          : null,
      children: [
        _MiniStats(items: [('Nilai stok', rp(stock['value'] as int? ?? 0)), ('Pembelian', rp(stock['purchases'] as int? ?? 0))]),
        const SizedBox(height: AppSpace.s2),
        _MiniStats(items: [('Terbuang', rp(stock['waste'] as int? ?? 0)), ('Selisih opname', '${countDiff > 0 ? '+' : ''}${rp(countDiff)}')]),
        if (low.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s3),
          Text('Stok menipis', style: AppType.bodyStrong.copyWith(color: AppColors.danger)),
          const SizedBox(height: AppSpace.s1),
          Wrap(
            spacing: AppSpace.s2,
            runSpacing: AppSpace.s2,
            children: [
              for (final i in low)
                AppBadge(
                  '${i['name']} ${qtyText((i['stock'] as num).toDouble())} ${i['unit']}${i['outlet'] == null ? '' : ' · ${i['outlet']}'}',
                  tone: AppTone.danger,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
