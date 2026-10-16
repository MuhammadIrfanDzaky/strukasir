import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';
import 'subscription.dart';

/// Fitur di luar paket (bagian `locked_features` dari GET /menu) + paket termurah yang membukanya.
/// Ditampilkan terkunci ke owner sebagai ajakan upgrade; fitur yang sengaja dimatikan owner tidak termasuk.
class LockedFeature {
  const LockedFeature({required this.key, required this.label, required this.description, required this.planCode, required this.planName});

  factory LockedFeature.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'] as Map<String, dynamic>;
    return LockedFeature(
      key: j['key'] as String,
      label: j['label'] as String,
      description: j['description'] as String? ?? '',
      planCode: plan['code'] as String,
      planName: plan['name'] as String,
    );
  }

  final String key;
  final String label;
  final String description;
  final String planCode;
  final String planName;
}

/// Lencana kecil "🔒 Tumbuh" di samping fitur terkunci (amber = warna ajakan paket).
class LockedBadge extends StatelessWidget {
  const LockedBadge(this.feature, {super.key});

  final LockedFeature feature;

  @override
  Widget build(BuildContext context) => AppBadge(feature.planName, tone: AppTone.warning, icon: Icons.lock_rounded);
}

/// Penjelasan fitur terkunci + ajakan membuka paket. [canUpgrade] false (kasir) → minta ke owner.
Future<void> showLockedFeature(BuildContext context, LockedFeature f, {bool canUpgrade = true}) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Buka ${f.label}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(f.description, style: AppType.body.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpace.s4),
            Container(
              padding: const EdgeInsets.all(AppSpace.s3),
              decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.smAll),
              child: Text(
                canUpgrade
                    ? 'Fitur ini tersedia mulai paket ${f.planName}. Upgrade untuk langsung memakainya. Data Anda tetap aman.'
                    : 'Fitur ini tersedia mulai paket ${f.planName}. Minta owner untuk upgrade paket.',
                style: AppType.body.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(canUpgrade ? 'Nanti' : 'Tutup')),
          if (canUpgrade)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                openUpgrade(context);
              },
              child: Text('Lihat paket ${f.planName}'),
            ),
        ],
      ),
    );

/// Kumpulan fitur terkunci di satu layar (Pelanggan, Dashboard) sebagai ajakan upgrade, hanya untuk owner.
/// Tidak tampil bila semua [keys] sudah ada di paket. [compact]: satu baris ringkas yang bisa ditutup.
class LockedFeaturesPanel extends ConsumerStatefulWidget {
  const LockedFeaturesPanel({super.key, required this.keys, required this.title, this.compact = false});

  final List<String> keys;
  final String title;
  final bool compact;

  @override
  ConsumerState<LockedFeaturesPanel> createState() => _LockedFeaturesPanelState();
}

class _LockedFeaturesPanelState extends ConsumerState<LockedFeaturesPanel> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    final owner = session is LoggedIn && session.user.can('settings.manage');
    final menu = ref.watch(menuProvider).value?.menu;
    final locked = [for (final k in widget.keys) ?menu?.locked(k)];
    if (!owner || locked.isEmpty || _hidden) return const SizedBox.shrink();
    // Paket termurah yang membuka fitur pertama (urutan keys = prioritas).
    final plan = locked.first.planName;

    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.s3, AppSpace.s2, AppSpace.s1, AppSpace.s2),
        decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.smAll),
        child: Row(children: [
          const Icon(Icons.lock_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpace.s2),
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.s1, runSpacing: AppSpace.s1, children: [
              Text('${widget.title}:', style: AppType.label.copyWith(color: AppColors.warning)),
              for (final f in locked)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  onTap: () => showLockedFeature(context, f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(f.label, style: AppType.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
          TextButton(onPressed: () => openUpgrade(context), child: Text('Paket $plan')),
          IconButton(
            tooltip: 'Tutup',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _hidden = true),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: AppType.title),
        const SizedBox(height: AppSpace.s1),
        Text('Buka dengan upgrade paket. Penjualan Anda sudah tercatat, jadi laporannya langsung terisi.',
            style: AppType.caption.copyWith(color: AppColors.inkMuted)),
        const SizedBox(height: AppSpace.s3),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 720 ? 2 : 1;
          final w = (c.maxWidth - (cols - 1) * AppSpace.s2) / cols;
          return Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
            for (final f in locked)
              SizedBox(
                width: w,
                child: Material(
                  color: AppColors.surfaceSunken,
                  borderRadius: AppRadius.smAll,
                  child: InkWell(
                    borderRadius: AppRadius.smAll,
                    onTap: () => showLockedFeature(context, f),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.s3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.label, style: AppType.bodyStrong),
                            Text(f.description,
                                style: AppType.caption.copyWith(color: AppColors.inkMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        const SizedBox(width: AppSpace.s2),
                        LockedBadge(f),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: AppSpace.s3),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: () => openUpgrade(context), child: Text('Lihat paket $plan')),
        ),
      ]),
    );
  }
}
