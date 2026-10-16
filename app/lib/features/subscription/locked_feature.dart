import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
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
