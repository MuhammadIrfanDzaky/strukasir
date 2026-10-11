import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Logo Strukasir: struk bergerigi berisi huruf S dan titik amber ("S." = struk beres). `reversed` untuk latar ink.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.reversed = false});

  final double size;
  final bool reversed;

  @override
  Widget build(BuildContext context) => Image.asset(
        reversed ? 'assets/brand/mark_reversed.png' : 'assets/brand/mark.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Strukasir',
      );
}

/// Logo + wordmark "STRUKASIR" (huruf kapital, ExtraBold, warna tinta).
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 40, this.reversed = false});

  final double height;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final style = AppType.headline.copyWith(
      fontSize: height * 0.56,
      height: 1,
      letterSpacing: height * 0.012,
      color: reversed ? AppColors.onInk : AppColors.ink,
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      BrandMark(size: height, reversed: reversed),
      SizedBox(width: height * 0.18),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('STRUKASIR', style: style, textScaler: TextScaler.noScaling, maxLines: 1),
        ),
      ),
    ]);
  }
}

enum AppTone { neutral, brand, success, warning, danger }

({Color bg, Color fg}) _toneColors(AppTone tone) => switch (tone) {
      AppTone.neutral => (bg: AppColors.surfaceSunken, fg: AppColors.inkMuted),
      AppTone.brand => (bg: AppColors.primarySoft, fg: AppColors.primaryStrong),
      AppTone.success => (bg: AppColors.successSoft, fg: AppColors.success),
      AppTone.warning => (bg: AppColors.warningSoft, fg: AppColors.warning),
      AppTone.danger => (bg: AppColors.dangerSoft, fg: AppColors.danger),
    };

/// Label status berbentuk pil. Warna tidak pernah jadi satu-satunya penanda: selalu ada teks.
class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = AppTone.neutral, this.icon});

  /// Status order dari API: paid / open / void.
  factory AppBadge.orderStatus(String status, {Key? key}) => switch (status) {
        'paid' => AppBadge('Lunas', key: key, tone: AppTone.success, ),
        'open' => AppBadge('Belum bayar', key: key, tone: AppTone.warning, ),
        _ => AppBadge('Void', key: key, tone: AppTone.danger, ),
      };

  final String label;
  final AppTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpace.s1),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c.fg), const SizedBox(width: AppSpace.s1)],
        Text(label, style: AppType.caption.copyWith(color: c.fg, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Lingkaran inisial nama staf.
class AppAvatar extends StatelessWidget {
  const AppAvatar(this.name, {super.key, this.size = 48});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
      child: Text(initials, style: AppType.title.copyWith(color: AppColors.primaryStrong, fontSize: size * 0.36)),
    );
  }
}

class AppLoading extends StatelessWidget {
  const AppLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Keadaan kosong: ikon, judul, keterangan, aksi opsional.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        // Bisa di-scroll: di HP landscape tingginya bisa lebih kecil dari isi.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.s6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.surfaceSunken, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpace.s4),
              Text(title, style: AppType.title, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: AppSpace.s1),
                Text(message!, style: AppType.body.copyWith(color: AppColors.inkMuted), textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: AppSpace.s4), action!],
            ]),
          ),
        ),
      );
}

/// Gagal memuat + tombol coba lagi.
class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, required this.onRetry, this.title = 'Gagal memuat'});

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: title,
        message: message,
        action: FilledButton(onPressed: onRetry, child: const Text('Coba lagi'), ),
      );
}

/// Baris label kiri, nilai kanan (ringkasan total, laporan).
class AppSummaryRow extends StatelessWidget {
  const AppSummaryRow(this.label, this.value, {super.key, this.emphasis = false, this.valueColor});

  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final labelStyle = emphasis ? AppType.title : AppType.body.copyWith(color: AppColors.inkMuted);
    final valueStyle = (emphasis ? AppType.moneyLg : AppType.bodyStrong).copyWith(color: valueColor ?? AppColors.ink);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: emphasis ? AppSpace.s1 : 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(child: Text(label, style: labelStyle)),
        Text(value, style: valueStyle),
      ]),
    );
  }
}

/// Kartu angka ringkas untuk laporan. `emphasis` = angka utama (penjualan) di atas primary.
class AppStatCard extends StatelessWidget {
  const AppStatCard(this.label, this.value, {super.key, this.emphasis = false, this.width = 220});

  final String label;
  final String value;
  final bool emphasis;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(AppSpace.s4),
        decoration: BoxDecoration(
          color: emphasis ? AppColors.primary : AppColors.surface,
          borderRadius: AppRadius.lgAll,
          border: emphasis ? null : Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.overline.copyWith(color: emphasis ? AppColors.primarySoft : AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: (emphasis ? AppType.moneyLg : AppType.titleLg)
                    .copyWith(color: emphasis ? AppColors.onPrimary : AppColors.ink)),
          ),
        ]),
      );
}

/// Kartu berjudul untuk mengelompokkan isi (laporan, pengaturan).
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({super.key, required this.title, required this.children, this.trailing, this.empty = 'Belum ada data.'});

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final String empty;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: AppType.title)),
              ?trailing,
            ]),
            const SizedBox(height: AppSpace.s3),
            if (children.isEmpty)
              Text(empty, style: AppType.body.copyWith(color: AppColors.inkMuted))
            else
              ...children,
          ]),
        ),
      );
}

/// Label kecil huruf kapital di atas kelompok isi.
class AppOverline extends StatelessWidget {
  const AppOverline(this.text, {super.key, this.color = AppColors.inkMuted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: AppType.overline.copyWith(color: color));
}
