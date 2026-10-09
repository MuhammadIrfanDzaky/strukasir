import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';

/// Tingkat member (GET /menu `member_tiers`, GET /customers `tier`).
class MemberTier {
  const MemberTier({
    required this.id,
    required this.name,
    this.threshold = 0,
    this.discountBp = 0,
    this.earnMultiplier = 1,
    this.color = 'silver',
    this.manual = false,
  });

  factory MemberTier.fromJson(Map<String, dynamic> j) => MemberTier(
        id: j['id'] as String,
        name: j['name'] as String,
        threshold: j['threshold'] as int? ?? 0,
        discountBp: j['discount_bp'] as int? ?? 0,
        earnMultiplier: j['earn_multiplier'] as int? ?? 1,
        color: j['color'] as String? ?? 'silver',
        manual: j['manual'] as bool? ?? false,
      );

  final String id;
  final String name;

  /// Rp (dasar belanja) atau jumlah kunjungan.
  final int threshold;
  final int discountBp;
  final int earnMultiplier;

  /// bronze | silver | gold | platinum | indigo
  final String color;

  /// Dikunci manual oleh owner (bukan dari belanja).
  final bool manual;

  /// "diskon 15% · stempel 2×" (kosong bila tanpa manfaat).
  String get benefits => [
        if (discountBp > 0) 'diskon ${percentBp(discountBp)}',
        if (earnMultiplier > 1) 'stempel/poin $earnMultiplier×',
      ].join(' · ');
}

/// Warna lencana per tingkat (latar, teks). Nama tingkat selalu tertulis: warna bukan satu-satunya penanda.
(Color, Color) tierColors(String color) => switch (color) {
      'bronze' => (const Color(0xFFFDE7D3), const Color(0xFF9A3412)),
      'gold' => (AppColors.accentSoft, AppColors.warning),
      'platinum' => (const Color(0xFF1E293B), const Color(0xFFF1F5F9)),
      'indigo' => (AppColors.primarySoft, AppColors.primaryStrong),
      _ => (const Color(0xFFE2E8F0), const Color(0xFF334155)),
    };

const tierColorLabels = {'bronze': 'Perunggu', 'silver': 'Perak', 'gold': 'Emas', 'platinum': 'Platinum', 'indigo': 'Nila'};

/// Lencana kecil nama tingkat (mis. "★ Gold").
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.dense = false});

  final MemberTier tier;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tierColors(tier.color);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 1 : 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(tier.manual ? Icons.lock_rounded : Icons.workspace_premium_rounded, size: dense ? 12 : 14, color: fg),
        const SizedBox(width: 3),
        Text(tier.name, style: AppType.caption.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12)),
      ]),
    );
  }
}
