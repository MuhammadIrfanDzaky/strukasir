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
      );

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
}

final subscriptionProvider = FutureProvider<Subscription>((ref) async {
  final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/subscription', token: token));
  return Subscription.fromJson(res['data'] as Map<String, dynamic>);
});

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

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
    this.discountPercent = 0,
  });

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
            for (final p in plans)
              _PlanCard(
                plan: p,
                period: period,
                selected: p.code == selected,
                current: p.code == current,
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
    this.discountPercent = 0,
    this.onTap,
  });

  final int discountPercent;

  final PlanInfo plan;
  final String period;
  final bool selected;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
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
                children: [
                  Expanded(child: Text(plan.name, style: AppType.title)),
                  if (current) const AppBadge('Paket saat ini'),
                ],
              ),
              const SizedBox(height: AppSpace.s1),
              if (discountPercent > 0 && !plan.free) ...[
                Text(plan.price(period), style: muted.copyWith(decoration: TextDecoration.lineThrough)),
                Text(
                  'Rp${rupiah(plan.discounted(period, discountPercent))}/${periodLabel(period)} · diskon $discountPercent%',
                  style: AppType.bodyStrong.copyWith(color: AppColors.ink),
                ),
              ] else
                Text(plan.price(period), style: AppType.bodyStrong.copyWith(color: AppColors.ink)),
              if (!plan.free && periodMonths(period) > 1)
                Text(
                  'setara Rp${rupiah((plan.discounted(period, discountPercent) / periodMonths(period)).round())}/bulan',
                  style: muted,
                ),
              if (plan.tagline != null) ...[
                const SizedBox(height: AppSpace.s2),
                Text(plan.tagline!, style: AppType.body.copyWith(color: AppColors.inkMuted)),
              ],
              const SizedBox(height: AppSpace.s2),
              Text(plan.limits, style: AppType.label.copyWith(color: AppColors.ink)),
              const SizedBox(height: AppSpace.s2),
              for (final h in plan.highlights) Text('• $h', style: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// CTA di sidebar (tepat di atas tombol Keluar): paket sekarang + ajakan upgrade.
class PlanCta extends ConsumerWidget {
  const PlanCta({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).value;
    if (sub == null) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: Material(
        color: sub.expired ? AppColors.danger : AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => openUpgrade(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: AppSpace.s3),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: sub.expired ? AppColors.onPrimary : AppColors.onAccent),
              textAlign: TextAlign.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sub.plan.name, style: AppType.label.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(sub.shortStatus, style: AppType.caption.copyWith(fontSize: 11), maxLines: 2),
                  const SizedBox(height: AppSpace.s1),
                  Text(sub.top ? 'Lihat paket' : 'Upgrade', style: AppType.bodyStrong.copyWith(decoration: TextDecoration.underline)),
                ],
              ),
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
                        discountPercent: sub.discountPercent,
                        onSelected: (c) => setState(() => _selected = c),
                        onPeriod: (p) => setState(() => _period = p),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      if (isOwner)
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: chosen == null || _busy ? null : () => _request(chosen, sub.discountPercent),
                            child: Text(chosen == null
                                ? 'Pilih salah satu paket'
                                : '${chosen.code == sub.plan.code ? 'Perpanjang' : 'Pilih'} ${chosen.name} · '
                                    '${chosen.priceWith(_period, sub.discountPercent)}'),
                          ),
                        )
                      else
                        Text('Hanya owner yang bisa mengganti paket.', style: AppType.body.copyWith(color: AppColors.inkMuted)),
                      const SizedBox(height: AppSpace.s2),
                      Text(
                        'Harga per usaha (bukan per outlet). Pembayaran lewat transfer / QRIS dikonfirmasi tim Strukasir; '
                        'paket aktif begitu pembayaran diterima. Data tidak hilang saat paket habis.',
                        style: AppType.caption.copyWith(color: AppColors.inkMuted),
                      ),
                      if (sub.referral != null) ...[
                        const SizedBox(height: AppSpace.s6),
                        const AppOverline('AJAK USAHA LAIN'),
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
          const SizedBox(height: AppSpace.s3),
          Text(
            'Diajak ${info.invited}   ·   Sudah berlangganan ${info.paid}   ·   Kupon ${info.rewardPercent}% tersedia ${info.rewardsAvailable}',
            style: AppType.label.copyWith(color: AppColors.ink),
          ),
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
