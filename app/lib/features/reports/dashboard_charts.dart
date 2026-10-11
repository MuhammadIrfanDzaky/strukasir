import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';

/// Warna grafik dashboard. Satu seri = indigo merek; "emphasis" = puncak berwarna, sisanya abu-abu;
/// kategori (metode bayar) memakai slot 1–3 palet tervalidasi (blue, orange, aqua) dengan urutan tetap.
abstract final class ChartColors {
  static const series = AppColors.primary;
  static const muted = Color(0xFFCBD5E1); // de-emphasis (slate-300)
  static const grid = AppColors.line;
  static const cash = Color(0xFF2A78D6);
  static const debit = Color(0xFFEB6834);
  static const qris = Color(0xFF1BAF7A); // kontras < 3:1 → selalu ada label & nilai di legenda
  static const credit = Color(0xFF94A3B8); // kasbon: uang belum diterima → netral (abu-abu)
}

/// Rupiah ringkas untuk sumbu & label: 950 → "950", 15.000 → "15rb", 1.250.000 → "1,25jt".
String rpShort(int v) {
  if (v.abs() >= 1000000) {
    final jt = v / 1000000;
    final s = jt >= 10 ? jt.toStringAsFixed(0) : jt.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '${s.replaceAll('.', ',')}jt';
  }
  if (v.abs() >= 1000) return '${(v / 1000).round()}rb';
  return '$v';
}

/// Skala sumbu "bulat": jarak garis 1 / 2 / 2,5 / 5 × 10^n dan batas atas kelipatannya,
/// mis. maks 2,06jt dengan 4 garis → jarak 500rb, batas 2,5jt (label 500rb, 1jt, 1,5jt …).
({double max, double step}) niceAxis(num maxValue, {int ticks = 4}) {
  if (maxValue <= 0) return (max: 4, step: 1);
  final raw = maxValue / ticks;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  var step = 10 * exp;
  for (final m in const [1, 2, 2.5, 5, 10]) {
    if (m * exp >= raw) {
      step = m * exp;
      break;
    }
  }
  return (max: step * (maxValue / step).ceil(), step: step);
}

TextStyle get _axis => AppType.caption.copyWith(color: AppColors.inkMuted, fontSize: 11);

/// Tren penjualan harian (satu seri: garis 2px + area tipis). Sentuh/arahkan → tanggal & nilai.
class SalesTrendChart extends StatelessWidget {
  const SalesTrendChart({super.key, required this.points});

  /// (label tanggal pendek, label tanggal lengkap, penjualan, transaksi)
  final List<(String short, String full, int sales, int orders)> points;

  @override
  Widget build(BuildContext context) {
    final axis = niceAxis(points.map((p) => p.$3).fold(0, math.max), ticks: 5);
    final maxY = axis.max;
    final step = (points.length / 6).ceil().clamp(1, 1000);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: axis.step,
            getDrawingHorizontalLine: (_) => const FlLine(color: ChartColors.grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: axis.step,
                getTitlesWidget: (v, meta) => Text(rpShort(v.round()), style: _axis),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= points.length || (i % step != 0 && i != points.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(points[i].$1, style: _axis),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            getTouchedSpotIndicator: (bar, spots) => [
              for (final _ in spots)
                TouchedSpotIndicatorData(
                  const FlLine(color: AppColors.lineStrong, strokeWidth: 1, dashArray: [4, 4]),
                  FlDotData(
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 5, color: ChartColors.series, strokeWidth: 2, strokeColor: AppColors.surface),
                  ),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.ink,
              tooltipBorderRadius: AppRadius.smAll,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${points[s.x.round()].$2}\n',
                    AppType.caption.copyWith(color: AppColors.onInkMuted),
                    children: [
                      TextSpan(
                        text: rp(points[s.x.round()].$3),
                        style: AppType.bodyStrong.copyWith(color: AppColors.onInk),
                      ),
                      TextSpan(
                        text: ' · ${points[s.x.round()].$4} trx',
                        style: AppType.caption.copyWith(color: AppColors.onInkMuted),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (final (i, p) in points.indexed) FlSpot(i.toDouble(), p.$3.toDouble())],
              color: ChartColors.series,
              barWidth: 2,
              isCurved: false,
              dotData: FlDotData(show: points.length <= 14),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ChartColors.series.withValues(alpha: 0.18), ChartColors.series.withValues(alpha: 0.02)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kolom per jam / per hari dengan "emphasis": kolom tertinggi berwarna, sisanya abu-abu.
class PeakColumnChart extends StatelessWidget {
  const PeakColumnChart({super.key, required this.bars, this.labelEvery = 1, this.height = 180});

  /// (label sumbu, label tooltip, penjualan, transaksi)
  final List<(String axis, String tooltip, int sales, int orders)> bars;
  final int labelEvery;
  final double height;

  @override
  Widget build(BuildContext context) {
    final peak = bars.map((b) => b.$3).fold(0, math.max);
    final axis = niceAxis(peak, ticks: 2);
    final maxY = axis.max;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: axis.step,
            getDrawingHorizontalLine: (_) => const FlLine(color: ChartColors.grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: axis.step,
                getTitlesWidget: (v, meta) => Text(rpShort(v.round()), style: _axis),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i % labelEvery != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(bars[i].$1, style: _axis),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.ink,
              tooltipBorderRadius: AppRadius.smAll,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, _, _, _) {
                final b = bars[group.x];
                return BarTooltipItem(
                  '${b.$2}\n',
                  AppType.caption.copyWith(color: AppColors.onInkMuted),
                  children: [
                    TextSpan(
                      text: rp(b.$3),
                      style: AppType.bodyStrong.copyWith(color: AppColors.onInk),
                    ),
                    TextSpan(
                      text: ' · ${b.$4} trx',
                      style: AppType.caption.copyWith(color: AppColors.onInkMuted),
                    ),
                  ],
                );
              },
            ),
          ),
          barGroups: [
            for (final (i, b) in bars.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: b.$3.toDouble(),
                    color: b.$3 == peak && peak > 0 ? ChartColors.series : ChartColors.muted,
                    width: bars.length > 12 ? 8 : 18,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Bagian-dari-keseluruhan: satu batang 100% bersegmen (celah 2px) + legenda dengan nilai & persen.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.parts});

  /// (label, nilai, warna)
  final List<(String, int, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold(0, (s, p) => s + p.$2);
    final shown = parts.where((p) => p.$2 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 18,
              // stretch: segmen tanpa anak harus diberi tinggi penuh, kalau tidak tingginya 0.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, p) in shown.indexed) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, (p.$2 * 1000 / total).round()),
                      child: ColoredBox(color: p.$3),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          Container(
            height: 18,
            decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(6)),
          ),
        const SizedBox(height: AppSpace.s3),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: AppSpace.s2),
                Expanded(child: Text(p.$1, style: AppType.body)),
                Text(rp(p.$2), style: AppType.bodyStrong),
                SizedBox(
                  width: 52,
                  child: Text(
                    total > 0 ? '${(p.$2 * 100 / total).round()}%' : '–',
                    textAlign: TextAlign.right,
                    style: AppType.body.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Judul bagian dashboard: label kapital abu-abu + keterangan. Hierarki lewat tipografi, bukan warna.
class DashSection extends StatelessWidget {
  const DashSection(this.label, {super.key, this.caption});

  final String label;
  final String? caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, AppSpace.s6, 2, AppSpace.s3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppType.overline.copyWith(color: AppColors.inkMuted)),
        if (caption != null) ...[const SizedBox(height: 2), Text(caption!, style: AppType.caption.copyWith(color: AppColors.inkMuted))],
      ],
    ),
  );
}

/// Panel dashboard: judul + keterangan, lalu isi. Datar (garis tipis), tanpa ikon hiasan.
class DashPanel extends StatelessWidget {
  const DashPanel({super.key, required this.title, required this.children, this.subtitle, this.trailing, this.empty = 'Belum ada data di periode ini.'});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final String empty;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpace.s4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.lgAll,
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: AppColors.inkMuted),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpace.s4),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
            child: Text(empty, style: AppType.body.copyWith(color: AppColors.inkMuted)),
          )
        else
          ...children,
      ],
    ),
  );
}

/// Grid panel: [columns] per baris, tiap baris sama tinggi; sisa ganjil melebar penuh.
class DashGrid extends StatelessWidget {
  const DashGrid({super.key, required this.children, required this.columns, this.spacing = AppSpace.s3});

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final row = children.sublist(i, math.min(i + columns, children.length));
      rows.add(row.length == 1 ? row.first : EqualHeightRow(spacing: spacing, children: row));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in rows.indexed) ...[if (i > 0) SizedBox(height: spacing), r],
      ],
    );
  }
}

/// Batang horizontal berlabel (urut terbesar): nama + nilai, batang tipis, keterangan kecil.
/// Satu warna: batang teratas indigo, sisanya abu-abu — penekanan pada yang terbesar saja.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.rows, this.highlightFirst = true, this.limit});

  /// (nama, nilai batang, teks nilai, keterangan kecil opsional)
  final List<(String, int, String, String?)> rows;
  final bool highlightFirst;

  /// Tampilkan paling banyak N baris (sisanya diringkas).
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown = limit == null ? rows : rows.take(limit!).toList();
    final max = rows.map((r) => r.$2).fold(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, r) in shown.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: i == shown.length - 1 ? 0 : AppSpace.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(r.$1, style: AppType.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpace.s2),
                    Text(r.$3, style: AppType.bodyStrong),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, box) {
                    final w = max > 0 ? box.maxWidth * r.$2 / max : 0.0;
                    return Stack(
                      children: [
                        Container(
                          height: 4,
                          decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(2)),
                        ),
                        Container(
                          width: math.max(w, r.$2 > 0 ? 3 : 0),
                          height: 4,
                          decoration: BoxDecoration(
                            color: highlightFirst && i == 0 ? ChartColors.series : ChartColors.muted,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (r.$4 != null && r.$4!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.$4!,
                    style: AppType.caption.copyWith(color: AppColors.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        if (limit != null && rows.length > limit!)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.s2),
            child: Text('+${rows.length - limit!} lainnya', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ),
      ],
    );
  }
}

/// Naik/turun dibanding periode sebelumnya: panah + persen (hijau/merah hanya di teks ini).
class DeltaText extends StatelessWidget {
  const DeltaText({super.key, required this.current, required this.previous, this.onDark = false});

  final int current;
  final int previous;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final muted = onDark ? AppColors.primarySoft : AppColors.inkMuted;
    if (previous == 0) {
      return Text(current > 0 ? 'baru di periode ini' : 'sama dengan sebelumnya', style: AppType.caption.copyWith(color: muted));
    }
    final pct = (current - previous) * 100 / previous;
    final up = pct >= 0;
    final fg = onDark ? AppColors.onPrimary : (up ? AppColors.success : AppColors.danger);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${up ? '▲' : '▼'} ${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0).replaceAll('.', ',')}%',
            style: AppType.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: ' vs sebelumnya',
            style: AppType.caption.copyWith(color: muted),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Kartu KPI: label, angka besar, perbandingan + keterangan. Satu kartu utama (hero) berwarna merek;
/// sisanya putih. Tinggi mengikuti KpiGrid supaya satu baris sama tinggi.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.current, this.previous, this.note, this.hero = false});

  final String label;
  final String value;
  final int? current;
  final int? previous;

  /// Keterangan kecil, mis. "margin 52%".
  final String? note;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final muted = hero ? AppColors.primarySoft : AppColors.inkMuted;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: hero ? AppColors.primary : AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: hero ? null : Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(color: muted),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: (hero ? AppType.moneyLg : AppType.headline).copyWith(color: hero ? AppColors.onPrimary : AppColors.ink)),
          ),
          const SizedBox(height: AppSpace.s1),
          if (current != null && previous != null) DeltaText(current: current!, previous: previous!, onDark: hero),
          if (note != null)
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}

/// Baris KPI sama tinggi: [columns] per baris (2 di HP, 4 di layar lebar).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, required this.columns, this.height = 140});

  final List<Widget> children;
  final int columns;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final row = children.sublist(i, math.min(i + columns, children.length));
      rows.add(
        SizedBox(
          height: height * scale.clamp(1.0, 1.5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[if (j > 0) const SizedBox(width: AppSpace.s3), Expanded(child: j < row.length ? row[j] : const SizedBox())],
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final (i, r) in rows.indexed) ...[if (i > 0) const SizedBox(height: AppSpace.s3), r],
      ],
    );
  }
}

/// Satu baris laporan laba-rugi. [kind]: '+' / '-' (baris biasa) atau '=' (subtotal, ditebalkan).
typedef StatementLine = ({String label, int amount, String kind, String? note});

/// Laba-rugi ringkas seperti laporan keuangan: baris biasa, subtotal dengan garis di atasnya,
/// hasil akhir paling tebal. Merah hanya bila hasil akhir rugi.
class ProfitStatement extends StatelessWidget {
  const ProfitStatement({super.key, required this.lines});

  final List<StatementLine> lines;

  @override
  Widget build(BuildContext context) {
    final last = lines.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, l) in lines.indexed)
          Container(
            margin: EdgeInsets.only(top: l.kind == '=' && i > 0 ? AppSpace.s1 : 0),
            padding: EdgeInsets.symmetric(vertical: l.kind == '=' ? AppSpace.s2 : 5),
            decoration: l.kind == '=' && i > 0
                ? const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.lineStrong)),
                  )
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: l.label, style: l.kind == '=' ? AppType.bodyStrong : AppType.body),
                        if (l.note != null)
                          TextSpan(
                            text: '  ${l.note}',
                            style: AppType.caption.copyWith(color: AppColors.inkMuted),
                          ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${l.kind == '-' ? '−' : ''}${rp(l.amount)}',
                  style:
                      (i == last
                              ? AppType.titleLg
                              : l.kind == '='
                              ? AppType.bodyStrong
                              : AppType.body)
                          .copyWith(color: i == last && l.amount < 0 ? AppColors.danger : AppColors.ink),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Angka kecil berderet (diskon, void, …) dalam satu panel, dibagi rata dengan garis tipis.
class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.items, required this.columns});

  /// (label, nilai)
  final List<(String, String)> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <List<(String, String)>>[];
    for (var i = 0; i < items.length; i += columns) {
      rows.add(items.sublist(i, math.min(i + columns, items.length)));
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          for (final (ri, row) in rows.indexed) ...[
            if (ri > 0) const Divider(height: 1, color: AppColors.line),
            EqualHeightRow(
              spacing: 0,
              children: [
                for (var j = 0; j < columns; j++)
                  DecoratedBox(
                    // Garis pemisah kolom di sisi kiri (bukan VerticalDivider: tingginya belum diketahui saat diukur).
                    decoration: BoxDecoration(
                      border: j > 0 ? const Border(left: BorderSide(color: AppColors.line)) : null,
                    ),
                    child: j >= row.length
                        ? const SizedBox()
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row[j].$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.caption.copyWith(color: AppColors.inkMuted),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(row[j].$2, style: AppType.title),
                                ),
                              ],
                            ),
                          ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Baris berkolom sama lebar yang semua anaknya setinggi anak tertinggi. Pengganti IntrinsicHeight
/// untuk isi yang tidak mendukung ukuran intrinsik (grafik & batang memakai LayoutBuilder): tiap anak
/// diukur dulu tanpa batas tinggi, lalu ditata ulang dengan tinggi baris.
class EqualHeightRow extends MultiChildRenderObjectWidget {
  const EqualHeightRow({super.key, required super.children, this.spacing = AppSpace.s3});

  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEqualHeightRow(spacing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderEqualHeightRow).spacing = spacing;
}

class _EqualHeightParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _EqualHeightParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _EqualHeightParentData> {
  _RenderEqualHeightRow(this._spacing);

  double _spacing;
  set spacing(double v) {
    if (v == _spacing) return;
    _spacing = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualHeightParentData) child.parentData = _EqualHeightParentData();
  }

  @override
  void performLayout() {
    final n = childCount;
    if (n == 0) {
      size = constraints.smallest;
      return;
    }
    final w = math.max(0.0, (constraints.maxWidth - _spacing * (n - 1)) / n);
    var h = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
      h = math.max(h, child.size.height);
      child = childAfter(child);
    }
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: w, height: h));
      (child.parentData! as _EqualHeightParentData).offset = Offset(x, 0);
      x += w + _spacing;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(constraints.maxWidth, h));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);
}
