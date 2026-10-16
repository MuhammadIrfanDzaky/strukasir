import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../session/session_controller.dart';

/// Satu paket dari server (GET /signup/options → `plans`, GET /subscription → `plans`).
class PlanInfo {
  const PlanInfo({
    required this.code,
    required this.name,
    this.tagline,
    required this.priceMonth,
    required this.priceYear,
    this.maxOutlets,
    this.maxDevices,
    this.maxStaff,
    this.trialDays,
    this.features = const [],
    this.prices = const {},
    this.recommended = false,
  });

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
        code: j['code'] as String,
        name: j['name'] as String,
        tagline: j['tagline'] as String?,
        priceMonth: j['price_month'] as int,
        priceYear: j['price_year'] as int,
        maxOutlets: j['max_outlets'] as int?,
        maxDevices: j['max_devices'] as int?,
        maxStaff: j['max_staff'] as int?,
        trialDays: j['trial_days'] as int?,
        features: (j['features'] as List? ?? const []).cast<String>(),
        prices: (j['prices'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, v as int)),
        recommended: j['recommended'] as bool? ?? false,
      );

  /// Disorot di app sebagai "Paling banyak dipilih".
  final bool recommended;

  /// Harga efektif per bulan untuk periode (setelah diskon periode & referral).
  int perMonth(String period, [int percent = 0]) => (discounted(period, percent) / periodMonths(period)).round();

  /// Patokan harian, dibulatkan ke atas per Rp10 (mis. Rp830/hari).
  int perDay(String period, [int percent = 0]) => ((perMonth(period, percent) / 30) / 10).ceil() * 10;

  final String code;
  final String name;
  final String? tagline;
  final int priceMonth;
  final int priceYear;

  /// Null = tanpa batas.
  final int? maxOutlets;
  final int? maxDevices;
  final int? maxStaff;

  /// Hanya paket gratis: lama masa coba.
  final int? trialDays;
  final List<String> features;

  /// Harga per periode dari server (sudah termasuk diskon periode): month, quarter, half, year.
  final Map<String, int> prices;

  bool get free => priceMonth == 0;

  /// Harga satu periode; tanpa data server dihitung dengan aturan yang sama (dibulatkan ke ratusan).
  int base(String period) =>
      prices[period] ?? ((priceMonth * periodMonths(period) * (100 - periodDiscount(period)) / 100) / 100).round() * 100;

  String price(String period) => free ? 'Gratis ${trialDays ?? 7} hari' : 'Rp${rupiah(base(period))}/${periodLabel(period)}';

  /// Harga setelah diskon referral, dibulatkan ke ratusan (sama dengan server).
  int discounted(String period, int percent) => ((base(period) * (100 - percent) / 100) / 100).round() * 100;

  /// Harga yang ditampilkan di tombol/dialog, sudah termasuk diskon.
  String priceWith(String period, int percent) => percent == 0 || free
      ? price(period)
      : 'Rp${rupiah(discounted(period, percent))}/${periodLabel(period)} (diskon $percent%)';

  String get limits => [
        _limit(maxOutlets, 'outlet'),
        _limit(maxDevices, 'tablet'),
        _limit(maxStaff, 'pengguna'),
      ].join(' · ');

  static String _limit(int? max, String noun) => max == null ? '$noun tanpa batas' : '$max $noun';

  /// Isi paket yang ditampilkan di kartu (ringkas, berurutan dari dasar ke lanjutan).
  List<String> get highlights => [
        'Kasir, struk & open bill',
        'Laporan penjualan',
        if (features.contains('promotions')) 'Promo & voucher',
        if (features.contains('loyalty')) 'Member, poin & tingkat member',
        if (features.contains('customer_credit')) 'Kasbon pelanggan',
        if (features.contains('customer_messaging')) 'Pesan WhatsApp ke member',
        if (features.contains('inventory')) 'Stok bahan & resep (HPP)',
        if (features.contains('multi_outlet')) 'Multi-outlet',
      ];
}

/// Periode bayar (sama dengan `PlanCatalog::PERIODS` di server).
const periods = ['month', 'quarter', 'half', 'year'];

int periodMonths(String period) => switch (period) { 'quarter' => 3, 'half' => 6, 'year' => 12, _ => 1 };

int periodDiscount(String period) => switch (period) { 'quarter' => 10, 'half' => 15, 'year' => 20, _ => 0 };

String periodLabel(String period) => switch (period) { 'quarter' => '3 bulan', 'half' => '6 bulan', 'year' => '12 bulan', _ => 'bulan' };

/// Status paket usaha (GET /subscription).
class Subscription {
  const Subscription({
    required this.plan,
    required this.status,
    this.period,
    this.endsAt,
    this.daysLeft,
    this.requestedPlan,
    this.requestedPeriod,
    required this.usage,
    required this.plans,
    this.discountPercent = 0,
    this.discountReason,
    this.referral,
  });

  factory Subscription.fromJson(Map<String, dynamic> j) {
    final requested = j['requested'] as Map<String, dynamic>?;
    return Subscription(
      plan: PlanInfo.fromJson(j['plan'] as Map<String, dynamic>),
      status: j['status'] as String,
      period: j['period'] as String?,
      endsAt: j['ends_at'] == null ? null : DateTime.parse(j['ends_at'] as String).toLocal(),
      daysLeft: j['days_left'] as int?,
      requestedPlan: requested == null ? null : PlanInfo.fromJson(requested['plan'] as Map<String, dynamic>),
      requestedPeriod: requested?['period'] as String?,
      usage: (j['usage'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
      plans: (j['plans'] as List).cast<Map<String, dynamic>>().map(PlanInfo.fromJson).toList(),
      discountPercent: (j['discount'] as Map<String, dynamic>?)?['percent'] as int? ?? 0,
      discountReason: (j['discount'] as Map<String, dynamic>?)?['reason'] as String?,
      referral: j['referral'] == null ? null : ReferralInfo.fromJson(j['referral'] as Map<String, dynamic>),
    );
  }

  /// Diskon di pembayaran berikutnya: 25% (diajak, sekali) atau 50% (kupon pengajak).
  final int discountPercent;

  /// referred | referral_reward
  final String? discountReason;
  final ReferralInfo? referral;

  final PlanInfo plan;

  /// trial | awaiting_payment | active | expired
  final String status;
  final String? period;
  final DateTime? endsAt;
  final int? daysLeft;
  final PlanInfo? requestedPlan;
  final String? requestedPeriod;
  final Map<String, int> usage;
  final List<PlanInfo> plans;

  bool get expired => status == 'expired';

  /// Paket tertinggi yang ditawarkan sudah aktif: CTA cukup "Lihat paket".
  bool get top => plans.isNotEmpty && plans.last.code == plan.code && status == 'active';

  /// Baris singkat di bawah nama paket (sidebar).
  String get shortStatus => switch (status) {
        'expired' => plan.free ? 'Masa coba habis' : 'Paket habis',
        'trial' => daysLeft == 0 ? 'Coba: hari terakhir' : 'Coba: $daysLeft hari lagi',
        'awaiting_payment' => 'Belum dibayar · $daysLeft hari',
        _ => daysLeft == null ? 'Aktif' : 'Aktif $daysLeft hari lagi',
      };

  /// Status sangat singkat untuk kotak paket di sidebar (lebar ±90 dp).
  String get railStatus => switch (status) {
        'expired' => plan.free ? 'Coba habis' : 'Paket habis',
        'trial' => daysLeft == 0 ? 'Coba: hari ini' : 'Coba $daysLeft hari',
        'awaiting_payment' => 'Belum dibayar',
        _ => daysLeft == null ? 'Aktif' : '$daysLeft hari lagi',
      };
}

final subscriptionProvider = FutureProvider<Subscription>((ref) async {
  final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/subscription', token: token));
  return Subscription.fromJson(res['data'] as Map<String, dynamic>);
});

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Pilihan paket + bulanan/tahunan (form daftar & halaman Upgrade).
class PlanPicker extends StatelessWidget {
  const PlanPicker({
    super.key,
    required this.plans,
    required this.selected,
    required this.period,
    required this.onSelected,
    required this.onPeriod,
    this.current,
    this.currentLabel,
    this.discountPercent = 0,
  });

  /// Label di kartu paket aktif (mis. "Paket Anda · s/d 15 Nov").
  final String? currentLabel;

  /// Diskon referral yang berlaku (harga normal dicoret).
  final int discountPercent;

  final List<PlanInfo> plans;
  final String? selected;
  final String period;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onPeriod;

  /// Paket aktif sekarang (diberi label, tidak bisa dipilih).
  final String? current;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chip (bukan segmented) supaya tetap rapi di HP & huruf besar: baris turun bila tidak muat.
        Wrap(
          spacing: AppSpace.s2,
          runSpacing: AppSpace.s2,
          children: [
            for (final p in periods)
              ChoiceChip(
                showCheckmark: false,
                label: Text(periodDiscount(p) == 0 ? '1 bulan' : '${periodMonths(p)} bulan · hemat ${periodDiscount(p)}%'),
                selected: period == p,
                onSelected: (_) => onPeriod(p),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.s3),
        LayoutBuilder(builder: (context, c) {
          final columns = (c.maxWidth >= 960 ? 4 : (c.maxWidth >= 560 ? 2 : 1)).clamp(1, plans.isEmpty ? 1 : plans.length);
          final cards = [
            for (final (i, p) in plans.indexed)
              _PlanCard(
                plan: p,
                previous: i == 0 ? null : plans[i - 1],
                reserveTag: columns > 1,
                period: period,
                selected: p.code == selected,
                current: p.code == current,
                currentLabel: currentLabel,
                discountPercent: discountPercent,
                onTap: () => onSelected(p.code),
              ),
          ];
          if (columns == 1) {
            return Column(children: [
              for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: AppSpace.s2), child: card),
            ]);
          }
          return Column(children: [
            for (var i = 0; i < cards.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s3),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var k = 0; k < columns; k++) ...[
                        if (k > 0) const SizedBox(width: AppSpace.s3),
                        Expanded(child: i + k < cards.length ? cards[i + k] : const SizedBox()),
                      ],
                    ],
                  ),
                ),
              ),
          ]);
        }),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.period,
    required this.selected,
    required this.current,
    this.currentLabel,
    this.previous,
    this.discountPercent = 0,
    this.reserveTag = false,
    this.onTap,
  });

  final String? currentLabel;

  final int discountPercent;

  /// Sediakan ruang label walau kartu ini tanpa label (kolom berdampingan → harga sejajar).
  final bool reserveTag;

  final PlanInfo plan;

  /// Paket di bawahnya: fitur ditampilkan sebagai tambahan ("Semua di Mulai, plus:").
  final PlanInfo? previous;
  final String period;
  final bool selected;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    final months = periodMonths(period);
    final extras = previous == null ? plan.highlights : plan.highlights.where((h) => !previous!.highlights.contains(h)).toList();

    final Widget price;
    if (plan.free) {
      price = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Rp0', style: AppType.headline.copyWith(color: AppColors.ink)),
          TextSpan(text: '  ${plan.trialDays ?? 7} hari', style: AppType.body.copyWith(color: AppColors.inkMuted)),
        ])),
        Text('Lalu pilih paket untuk lanjut berjualan', style: muted),
      ]);
    } else {
      final normalMonth = plan.perMonth('month');
      final effMonth = plan.perMonth(period, discountPercent);
      final billed = plan.discounted(period, discountPercent);
      final saving = plan.priceMonth * months - billed;
      price = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (effMonth < normalMonth)
          Text('Rp${rupiah(normalMonth)}', style: muted.copyWith(decoration: TextDecoration.lineThrough)),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Rp${rupiah(effMonth)}', style: AppType.headline.copyWith(color: AppColors.ink)),
          TextSpan(text: ' /bulan', style: AppType.body.copyWith(color: AppColors.inkMuted)),
        ])),
        Text(
          months > 1 || discountPercent > 0
              ? 'Rp${rupiah(billed)} untuk $months bulan · hemat Rp${rupiah(saving)}'
              : '≈ Rp${rupiah(plan.perDay(period))} per hari',
          style: muted,
        ),
      ]);
    }

    return Material(
      color: selected ? AppColors.primarySoft : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (plan.recommended || current)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.s2),
                          child: current
                              ? AppBadge(currentLabel ?? 'Paket Anda', tone: AppTone.success)
                              : const _Tag('Paling banyak dipilih'),
                        )
                      else if (reserveTag)
                        const Opacity(
                          opacity: 0,
                          child: Padding(padding: EdgeInsets.only(bottom: AppSpace.s2), child: _Tag('Paling banyak dipilih')),
                        ),
                      Text(plan.name, style: AppType.title),
                      if (plan.tagline != null) Text(plan.tagline!, style: muted),
                    ]),
                  ),
                  const SizedBox(width: AppSpace.s2),
                  RadioDot(selected: selected),
                ],
              ),
              const SizedBox(height: AppSpace.s3),
              price,
              const SizedBox(height: AppSpace.s3),
              const Divider(height: 1),
              const SizedBox(height: AppSpace.s3),
              _LimitStrip(plan: plan, tinted: selected),
              const SizedBox(height: AppSpace.s3),
              if (previous != null)
                Text(extras.isEmpty ? 'Semua fitur ${previous!.name}, kapasitas lebih besar' : 'Semua di ${previous!.name}, plus:',
                    style: muted),
              for (final h in extras)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('+ $h', style: AppType.caption.copyWith(color: AppColors.ink)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kapasitas paket: tiga sel angka besar + satuan (∞ = tanpa batas).
class _LimitStrip extends StatelessWidget {
  const _LimitStrip({required this.plan, this.tinted = false});

  final PlanInfo plan;

  /// Kartu terpilih berlatar indigo muda → sel putih supaya tetap kontras.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final cells = [(plan.maxOutlets, 'outlet'), (plan.maxDevices, 'tablet'), (plan.maxStaff, 'pengguna')];
    return Container(
      decoration: BoxDecoration(
        color: tinted ? AppColors.surface : AppColors.surfaceSunken,
        borderRadius: AppRadius.smAll,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
      child: IntrinsicHeight(
        child: Row(children: [
          for (final (i, (max, noun)) in cells.indexed) ...[
            if (i > 0) const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
            Expanded(
              child: Semantics(
                label: max == null ? '$noun tanpa batas' : '$max $noun',
                excludeSemantics: true,
                child: Column(children: [
                  Text(max == null ? '∞' : '$max', style: AppType.title.copyWith(color: AppColors.ink, height: 1.2)),
                  Text(noun, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Label sorotan kecil (paket yang direkomendasikan).
class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text(text, style: AppType.caption.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700)),
      );
}

/// CTA di sidebar (tepat di atas tombol Keluar): paket sekarang + ajakan upgrade.
class PlanCta extends ConsumerWidget {
  const PlanCta({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).value;
    if (sub == null) return const SizedBox.shrink();
    // Paket berbayar aktif: kotak tenang di atas rail gelap. Masa coba / belum dibayar: amber (ajakan).
    // Habis: merah. Ajakan berupa pil kecil, bukan teks bergaris bawah.
    final calm = sub.status == 'active';
    final (bg, fg, muted) = sub.expired
        ? (AppColors.danger, AppColors.onPrimary, AppColors.onPrimary)
        : calm
            ? (AppColors.onInk.withValues(alpha: 0.08), AppColors.onInk, AppColors.onInkMuted)
            : (AppColors.accent, AppColors.onAccent, AppColors.onAccent);
    final cta = sub.expired ? (sub.plan.free ? 'Upgrade' : 'Perpanjang') : calm ? (sub.top ? null : 'Upgrade') : 'Upgrade';
    return SizedBox(
      width: width,
      child: Material(
        color: bg,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: () => openUpgrade(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sub.plan.name,
                    style: AppType.label.copyWith(color: fg, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(sub.railStatus,
                    style: AppType.caption.copyWith(color: muted, fontSize: 11, height: 1.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (cta != null) ...[
                  const SizedBox(height: AppSpace.s1 + 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: calm ? AppColors.accent : AppColors.ink,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(cta,
                        textAlign: TextAlign.center,
                        style: AppType.caption.copyWith(
                            color: calm ? AppColors.onAccent : AppColors.onInk, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void openUpgrade(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const UpgradeScreen()));

/// Halaman Upgrade paket: status paket, pemakaian, dan pilihan paket berbayar.
class UpgradeScreen extends ConsumerStatefulWidget {
  const UpgradeScreen({super.key});

  @override
  ConsumerState<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends ConsumerState<UpgradeScreen> {
  String? _selected;
  String _period = 'month';
  bool _busy = false;

  /// Bayar via QRIS. Bila pembayaran online belum aktif di server (503), permintaan dicatat untuk diproses manual.
  Future<void> _pay(PlanInfo plan, int discount) async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) =>
          api.post('/subscription/checkout', token: token, data: {'plan': plan.code, 'period': _period}));
      if (!mounted) return;
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => QrisPaymentDialog(plan: plan, period: _period, invoice: res['data'] as Map<String, dynamic>),
      );
      ref.invalidate(subscriptionProvider);
      if (paid == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pembayaran diterima. Paket ${plan.name} aktif.')));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 503) {
        await _request(plan, discount);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(PlanInfo plan, int discount) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).authed((api, token) =>
          api.post('/subscription/request', token: token, data: {'plan': plan.code, 'period': _period}));
      ref.invalidate(subscriptionProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Permintaan paket ${plan.name} tercatat'),
          content: Text(
            'Total ${plan.priceWith(_period, discount)}. Tim Strukasir akan menghubungi Anda lewat email / WhatsApp untuk '
            'pembayaran (transfer atau QRIS). Paket aktif begitu pembayaran diterima.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Mengerti'))],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subscriptionProvider);
    final isOwner = ref.watch(sessionProvider).value is LoggedIn &&
        (ref.watch(sessionProvider).value as LoggedIn).user.can('users.manage');
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Upgrade paket')),
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorState(message: e is ApiException ? e.message : '$e', onRetry: () => ref.invalidate(subscriptionProvider)),
        data: (sub) {
          final paid = sub.plans.where((p) => !p.free).toList();
          final chosen = paid.where((p) => p.code == _selected).firstOrNull;
          return ListView(
            padding: EdgeInsets.all(pad),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _CurrentPlan(sub: sub),
                      const SizedBox(height: AppSpace.s6),
                      const AppOverline('PILIH PAKET'),
                      const SizedBox(height: AppSpace.s2),
                      PlanPicker(
                        plans: paid,
                        selected: _selected,
                        period: _period,
                        // Paket berbayar sekarang bisa dipilih lagi untuk diperpanjang.
                        current: sub.plan.free ? null : sub.plan.code,
                        currentLabel: sub.status == 'active' && sub.endsAt != null
                            ? 'Paket Anda · s/d ${_shortDate(sub.endsAt!)}'
                            : 'Paket Anda',
                        discountPercent: sub.discountPercent,
                        onSelected: (c) => setState(() => _selected = c),
                        onPeriod: (p) => setState(() => _period = p),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      if (isOwner)
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: chosen == null || _busy ? null : () => _pay(chosen, sub.discountPercent),
                            style: FilledButton.styleFrom(minimumSize: const Size(240, AppSize.touchLg)),
                            child: Text(chosen == null
                                ? 'Pilih paket dulu'
                                : chosen.code == sub.plan.code
                                    ? 'Lanjut perpanjang'
                                    : 'Lanjut ke pembayaran'),
                          ),
                        )
                      else
                        Text('Hanya owner yang bisa mengganti paket.', style: AppType.body.copyWith(color: AppColors.inkMuted)),
                      const SizedBox(height: AppSpace.s2),
                      Text(
                        'Harga per usaha (bukan per outlet). Bayar dengan QRIS dari aplikasi bank / e-wallet apa pun; '
                        'paket langsung aktif begitu pembayaran diterima. Data tidak hilang saat paket habis.',
                        style: AppType.caption.copyWith(color: AppColors.inkMuted),
                      ),
                      if (sub.referral != null) ...[
                        const SizedBox(height: AppSpace.s6),
                        const AppOverline('REFERRAL'),
                        const SizedBox(height: AppSpace.s2),
                        _ReferralCard(info: sub.referral!),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final muted = AppType.body.copyWith(color: AppColors.inkMuted);
    final end = sub.endsAt == null ? null : _date(sub.endsAt!);
    final (String line, AppTone tone) = switch (sub.status) {
      'expired' => (
          sub.plan.free ? 'Masa coba berakhir $end. Pilih paket untuk lanjut berjualan.' : 'Paket berakhir $end. Perpanjang untuk lanjut berjualan.',
          AppTone.danger
        ),
      'trial' => ('Masa coba gratis sampai $end (${sub.daysLeft} hari lagi).', AppTone.warning),
      'awaiting_payment' => ('Menunggu pembayaran. Bisa dipakai sampai $end.', AppTone.warning),
      _ => (end == null ? 'Aktif.' : 'Aktif sampai $end.', AppTone.success),
    };
    final usage = [
      'Outlet ${sub.usage['outlets']}/${sub.plan.maxOutlets ?? '∞'}',
      'Tablet ${sub.usage['devices']}/${sub.plan.maxDevices ?? '∞'}',
      'Pengguna ${sub.usage['staff']}/${sub.plan.maxStaff ?? '∞'}',
    ].join('   ·   ');
    return Container(
      padding: const EdgeInsets.all(AppSpace.s5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppOverline('PAKET SAAT INI'),
          const SizedBox(height: AppSpace.s1),
          Row(
            children: [
              Text(sub.plan.name, style: AppType.headline),
              const SizedBox(width: AppSpace.s3),
              AppBadge(switch (sub.status) {
                'expired' => 'Habis',
                'trial' => 'Masa coba',
                'awaiting_payment' => 'Belum dibayar',
                _ => 'Aktif',
              }, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpace.s1),
          Text(line, style: muted),
          const SizedBox(height: AppSpace.s3),
          Text(usage, style: AppType.label.copyWith(color: AppColors.ink)),
          if (sub.requestedPlan != null) ...[
            const SizedBox(height: AppSpace.s3),
            const Divider(height: 1),
            const SizedBox(height: AppSpace.s3),
            Text(
              'Permintaan paket ${sub.requestedPlan!.name} (${periodMonths(sub.requestedPeriod ?? 'month')} bulan) '
              'menunggu pembayaran. Tim Strukasir akan menghubungi Anda.',
              style: muted,
            ),
          ],
        ],
      ),
    );
  }
}

/// Kode referral usaha ini & hasilnya (GET /subscription → `referral`).
class ReferralInfo {
  const ReferralInfo({
    required this.code,
    required this.invited,
    required this.paid,
    required this.rewardsAvailable,
    required this.referredPercent,
    required this.rewardPercent,
    required this.trialDays,
  });

  factory ReferralInfo.fromJson(Map<String, dynamic> j) => ReferralInfo(
        code: j['code'] as String? ?? '',
        invited: j['invited'] as int,
        paid: j['paid'] as int,
        rewardsAvailable: j['rewards_available'] as int,
        referredPercent: j['referred_percent'] as int,
        rewardPercent: j['reward_percent'] as int,
        trialDays: j['trial_days'] as int,
      );

  final String code;

  /// Usaha yang daftar dengan kode ini / yang sudah membayar paket.
  final int invited;
  final int paid;

  /// Kupon diskon pengajak yang belum dipakai.
  final int rewardsAvailable;
  final int referredPercent;
  final int rewardPercent;
  final int trialDays;
}

class _ReferralCard extends StatelessWidget {
  const _ReferralCard({required this.info});

  final ReferralInfo info;

  String get _message => 'Saya pakai Strukasir untuk kasir & laporan usaha. Daftar pakai kode ${info.code} '
      'supaya dapat coba gratis ${info.trialDays} hari dan diskon ${info.referredPercent}% saat berlangganan.';

  @override
  Widget build(BuildContext context) {
    final muted = AppType.body.copyWith(color: AppColors.inkMuted);
    return Container(
      padding: const EdgeInsets.all(AppSpace.s5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kode referral Anda', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          SelectableText(info.code, style: AppType.headline.copyWith(letterSpacing: 4)),
          const SizedBox(height: AppSpace.s2),
          Text(
            'Usaha yang daftar dengan kode ini dapat coba gratis ${info.trialDays} hari dan diskon ${info.referredPercent}% '
            'di pembayaran pertama. Anda dapat diskon ${info.rewardPercent}% untuk satu pembayaran setiap ada usaha ajakan '
            'yang mulai berlangganan.',
            style: muted,
          ),
          const SizedBox(height: AppSpace.s4),
          LayoutBuilder(builder: (context, c) {
            final tiles = [
              _ReferralStat(value: info.invited, label: 'Usaha diajak'),
              _ReferralStat(value: info.paid, label: 'Sudah berlangganan'),
              _ReferralStat(value: info.rewardsAvailable, label: 'Kupon ${info.rewardPercent}% siap pakai', highlight: info.rewardsAvailable > 0),
            ];
            final row = c.maxWidth >= 420;
            return row
                ? IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(width: AppSpace.s2), Expanded(child: t)],
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (i, t) in tiles.indexed) ...[if (i > 0) const SizedBox(height: AppSpace.s2), t],
                  ]);
          }),
          const SizedBox(height: AppSpace.s4),
          Wrap(
            spacing: AppSpace.s2,
            runSpacing: AppSpace.s2,
            children: [
              FilledButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_message)}'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Bagikan lewat WhatsApp'),
              ),
              OutlinedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: info.code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kode referral disalin')));
                },
                child: const Text('Salin kode'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Satu angka statistik referral. Kupon tersedia (> 0) diberi warna hijau: bisa langsung dipakai.
class _ReferralStat extends StatelessWidget {
  const _ReferralStat({required this.value, required this.label, this.highlight = false});

  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s3, vertical: AppSpace.s3),
        decoration: BoxDecoration(
          color: highlight ? AppColors.successSoft : AppColors.surfaceSunken,
          borderRadius: AppRadius.smAll,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: AppType.headline.copyWith(color: highlight ? AppColors.success : AppColors.ink, height: 1.1)),
          const SizedBox(height: 2),
          Text(label, style: AppType.caption.copyWith(color: highlight ? AppColors.success : AppColors.inkMuted)),
        ]),
      );
}

/// Tagihan paket: halaman bayar Mayar (QRIS), hitung mundur, dan cek status berkala sampai lunas / kedaluwarsa.
/// Hasil `true` = lunas (paket sudah aktif di server).
class QrisPaymentDialog extends ConsumerStatefulWidget {
  const QrisPaymentDialog({super.key, required this.plan, required this.period, required this.invoice});

  final PlanInfo plan;
  final String period;
  final Map<String, dynamic> invoice;

  @override
  ConsumerState<QrisPaymentDialog> createState() => _QrisPaymentDialogState();
}

class _QrisPaymentDialogState extends ConsumerState<QrisPaymentDialog> {
  late Map<String, dynamic> _invoice = widget.invoice;
  Timer? _poll;
  Timer? _tick;
  bool _checking = false;

  String get _status => _invoice['status'] as String;

  DateTime? get _expiresAt =>
      _invoice['expires_at'] == null ? null : DateTime.parse(_invoice['expires_at'] as String).toLocal();

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _status != 'pending') return;
    _checking = true;
    try {
      final res = await ref
          .read(sessionProvider.notifier)
          .authed((api, token) => api.get('/subscription/invoices/${_invoice['id']}', token: token));
      if (!mounted) return;
      setState(() => _invoice = res['data'] as Map<String, dynamic>);
      if (_status != 'pending') _poll?.cancel();
    } on ApiException {
      // Koneksi putus sesaat: coba lagi di putaran berikutnya.
    } finally {
      _checking = false;
    }
  }

  String _remaining() {
    final left = _expiresAt?.difference(DateTime.now());
    if (left == null || left.isNegative) return '0:00';
    return '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppType.body.copyWith(color: AppColors.inkMuted);
    final amount = 'Rp${rupiah(_invoice['amount'] as int)}';
    final expired = _status == 'expired' || (_status == 'pending' && (_expiresAt?.isBefore(DateTime.now()) ?? false));

    final Widget body;
    if (_status == 'paid') {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
        const SizedBox(height: AppSpace.s3),
        Text('Pembayaran $amount diterima', style: AppType.title, textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.s1),
        Text('Paket ${widget.plan.name} (${periodMonths(widget.period)} bulan) sudah aktif.', style: muted, textAlign: TextAlign.center),
      ]);
    } else if (expired || _status == 'failed') {
      body = Text(
        expired ? 'Tagihan sudah kedaluwarsa. Tutup lalu tekan Lanjut ke pembayaran lagi untuk membuat tagihan baru.' : 'Pembayaran gagal. Coba lagi.',
        style: muted,
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Text(amount, style: AppType.headline),
        Text('Paket ${widget.plan.name} · ${periodMonths(widget.period)} bulan', style: muted),
        const SizedBox(height: AppSpace.s4),
        // Halaman bayar Mayar menampilkan QRIS; app ini memeriksa status otomatis.
        FilledButton(
          onPressed: _invoice['pay_url'] == null
              ? null
              : () => launchUrl(Uri.parse(_invoice['pay_url'] as String), mode: LaunchMode.externalApplication),
          child: const Text('Buka halaman pembayaran QRIS'),
        ),
        const SizedBox(height: AppSpace.s3),
        Text('Pindai QRIS di halaman itu dengan aplikasi bank atau e-wallet (GoPay, OVO, DANA, ShopeePay, m-banking), lalu kembali ke sini.',
            style: muted, textAlign: TextAlign.center),
        const SizedBox(height: AppSpace.s2),
        Text('Berlaku ${_remaining()} · menunggu pembayaran…', style: AppType.label.copyWith(color: AppColors.ink)),
      ]);
    }

    return AlertDialog(
      title: Text(_status == 'paid' ? 'Berhasil' : 'Bayar dengan QRIS'),
      content: SizedBox(width: 340, child: SingleChildScrollView(child: body)),
      actions: [
        if (_status == 'pending' && !expired) TextButton(onPressed: _check, child: const Text('Cek pembayaran')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _status == 'paid'),
          child: Text(_status == 'paid' ? 'Selesai' : 'Tutup'),
        ),
      ],
    );
  }
}
