import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(points[i].$1, style: _axis));
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
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 5,
                      color: ChartColors.series,
                      strokeWidth: 2,
                      strokeColor: AppColors.surface,
                    ),
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
                      TextSpan(text: rp(points[s.x.round()].$3), style: AppType.bodyStrong.copyWith(color: AppColors.onInk)),
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
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(bars[i].$1, style: _axis));
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
                    TextSpan(text: rp(b.$3), style: AppType.bodyStrong.copyWith(color: AppColors.onInk)),
                    TextSpan(text: ' · ${b.$4} trx', style: AppType.caption.copyWith(color: AppColors.onInkMuted)),
                  ],
                );
              },
            ),
          ),
          barGroups: [
            for (final (i, b) in bars.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: b.$3.toDouble(),
                  color: b.$3 == peak && peak > 0 ? ChartColors.series : ChartColors.muted,
                  width: bars.length > 12 ? 8 : 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (total > 0)
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 18,
            // stretch: segmen tanpa anak harus diberi tinggi penuh, kalau tidak tingginya 0.
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, p) in shown.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(flex: math.max(1, (p.$2 * 1000 / total).round()), child: ColoredBox(color: p.$3)),
              ],
            ]),
          ),
        )
      else
        Container(height: 18, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(6))),
      const SizedBox(height: AppSpace.s3),
      for (final p in parts)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3))),
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
          ]),
        ),
    ]);
  }
}

/// Batang horizontal berlabel (urut terbesar): nama di atas, batang + nilai di bawah.
/// Satu warna (besaran), label selalu terlihat — tidak bergantung pada hover.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.rows, this.highlightFirst = true});

  /// (nama, nilai batang, teks nilai, keterangan kecil opsional)
  final List<(String, int, String, String?)> rows;
  final bool highlightFirst;

  @override
  Widget build(BuildContext context) {
    final max = rows.map((r) => r.$2).fold(0, math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Text(r.$1, style: AppType.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: AppSpace.s2),
              Text(r.$3, style: AppType.bodyStrong),
            ]),
            const SizedBox(height: 4),
            LayoutBuilder(builder: (context, box) {
              final w = max > 0 ? box.maxWidth * r.$2 / max : 0.0;
              return Stack(children: [
                Container(height: 8, decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(4))),
                Container(
                  width: math.max(w, r.$2 > 0 ? 4 : 0),
                  height: 8,
                  decoration: BoxDecoration(
                    color: highlightFirst && i == 0 ? ChartColors.series : ChartColors.series.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ]);
            }),
            if (r.$4 != null) ...[
              const SizedBox(height: 2),
              Text(r.$4!, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ],
          ]),
        ),
    ]);
  }
}

/// Kartu angka dengan perbandingan ke periode sebelumnya (ikon + teks, bukan warna saja).
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.current,
    this.previous,
    this.note,
    this.hero = false,
    this.width = 220,
  });

  final String label;
  final String value;
  final int? current;
  final int? previous;

  /// Keterangan kecil, mis. "margin 52%".
  final String? note;
  final bool hero;
  final double width;

  @override
  Widget build(BuildContext context) {
    final fg = hero ? AppColors.onPrimary : AppColors.ink;
    final muted = hero ? AppColors.primarySoft : AppColors.inkMuted;
    Widget? delta;
    if (current != null && previous != null) {
      if (previous == 0) {
        delta = Text(current! > 0 ? 'Baru di periode ini' : 'Sama dengan sebelumnya', style: AppType.caption.copyWith(color: muted));
      } else {
        final pct = (current! - previous!) * 100 / previous!;
        final up = pct >= 0;
        final color = hero ? AppColors.onPrimary : (up ? AppColors.success : AppColors.danger);
        delta = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${up ? 'naik' : 'turun'} ${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0).replaceAll('.', ',')}%',
              style: AppType.caption.copyWith(color: color, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]);
      }
    }
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: hero ? AppColors.primary : AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: hero ? null : Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline.copyWith(color: muted)),
        const SizedBox(height: AppSpace.s2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: (hero ? AppType.moneyLg : AppType.titleLg).copyWith(color: fg)),
        ),
        if (delta != null) ...[const SizedBox(height: AppSpace.s1), delta],
        if (note != null) Text(note!, style: AppType.caption.copyWith(color: muted)),
      ]),
    );
  }
}
