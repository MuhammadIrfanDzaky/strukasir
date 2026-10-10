import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../customers/messaging.dart';
import '../customers/tier_settings_screen.dart';
import '../inventory/inventory_screen.dart';
import '../loyalty/loyalty_settings_screen.dart';
import '../menu/menu_controller.dart';
import '../outlets/outlets_screen.dart';
import '../printing/printer_service.dart';
import '../printing/printer_settings_screen.dart';
import '../printing/receipt_settings_screen.dart';
import '../printing/stations_screen.dart';
import '../promotions/promotions_screen.dart';
import '../session/session_controller.dart';
import '../staff/staff_screen.dart';
import 'feature_settings_screen.dart';

/// Warna kelompok pengaturan (peran token design system): ikon berwarna di atas latar lembut,
/// supaya tiap kelompok terasa terpisah tanpa menambah warna baru.
enum _Tone {
  brand(AppColors.primary, AppColors.primarySoft),
  device(AppColors.ink, AppColors.surfaceSunken),
  sales(AppColors.warning, AppColors.accentSoft),
  customer(AppColors.success, AppColors.successSoft),
  danger(AppColors.danger, AppColors.dangerSoft);

  const _Tone(this.fg, this.bg);

  final Color fg;
  final Color bg;
}

/// Satu baris pengaturan: judul (apa), keterangan (isi/status), lalu buka halaman atau jalankan aksi.
class _Item {
  const _Item({required this.icon, required this.title, required this.subtitle, required this.onTap, this.badge, this.keywords = ''});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Status singkat di kanan (mis. nama printer belum dipilih).
  final AppBadge? badge;

  /// Kata tambahan untuk pencarian.
  final String keywords;

  bool matches(String q) => '$title $subtitle $keywords'.toLowerCase().contains(q);
}

class _Group {
  const _Group(this.label, this.tone, this.items);

  final String label;
  final _Tone tone;
  final List<_Item> items;
}

/// Pusat pengaturan: kartu akun, pencarian, lalu kelompok (Usaha, Perangkat, Penjualan, Pelanggan).
/// Setiap baris membuka halaman sendiri; hanya baris yang boleh & fiturnya aktif yang tampil.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// Konfirmasi dulu: setelah keluar, tablet butuh email & password owner untuk dipakai lagi.
  Future<void> _unregister(DeviceInfo device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluarkan tablet?'),
        content: Text(
          '${device.name} (${device.code}) akan dikeluarkan dari ${device.tenantName}. Semua kasir di tablet ini '
          'ikut keluar.\n\nData transaksi tetap tersimpan di server. Untuk memakai tablet ini lagi, '
          'daftarkan ulang dengan email & password owner.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(sessionProvider.notifier).unregisterDevice();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
    }
  }

  List<_Group> _groups() {
    final session = ref.watch(sessionProvider).value as LoggedIn?;
    final user = session?.user;
    final device = session?.device;
    final menu = ref.watch(menuProvider).value?.menu;
    final printer = ref.watch(printerProvider).value;
    bool can(String p) => user?.can(p) ?? false;
    bool on(String f) => menu?.feature(f) ?? false;
    final owner = can('settings.manage');

    return [
      if (owner)
        _Group('Usaha', _Tone.brand, [
          _Item(
            icon: Icons.toggle_on_rounded,
            title: 'Fitur',
            subtitle: 'Open bill, varian, diskon, pajak & service, laporan',
            keywords: 'modul paket aktifkan',
            onTap: () => _open(const FeatureSettingsScreen()),
          ),
          _Item(
            icon: Icons.storefront_rounded,
            title: 'Outlet',
            subtitle: menu?.outlet == null ? 'Cabang & tablet per outlet' : 'Tablet ini di ${menu!.outlet!.name}',
            keywords: 'cabang toko tablet pindah',
            onTap: () => _open(const OutletsScreen()),
          ),
          _Item(
            icon: Icons.badge_rounded,
            title: 'Pegawai',
            subtitle: 'Tambah kasir, ganti PIN, nonaktifkan',
            keywords: 'kasir staf karyawan pin akses user',
            onTap: () => _open(const StaffScreen()),
          ),
          _Item(
            icon: Icons.receipt_long_rounded,
            title: 'Struk & logo',
            subtitle: 'Nama usaha, alamat, pesan penutup',
            keywords: 'header footer cetak',
            onTap: () {
              final receipt = menu?.receipt;
              if (receipt != null) _open(ReceiptSettingsScreen(current: receipt));
            },
          ),
        ]),
      _Group('Perangkat', _Tone.device, [
        _Item(
          icon: Icons.print_rounded,
          title: 'Printer struk',
          subtitle: printer == null ? 'Pilih printer Bluetooth' : printer.name,
          badge: printer == null ? const AppBadge('Belum dipilih', tone: AppTone.warning) : null,
          keywords: 'bluetooth tes cetak',
          onTap: () => _open(const PrinterSettingsScreen()),
        ),
        _Item(
          icon: Icons.local_cafe_rounded,
          title: 'Tiket bar / dapur',
          subtitle: 'Cetak pesanan per stasiun, tanpa harga',
          keywords: 'checker kitchen printer',
          onTap: () => _open(const StationsScreen()),
        ),
      ]),
      if (owner && (on('promotions') || (on('inventory') && can('inventory.manage'))))
        _Group('Penjualan & produk', _Tone.sales, [
          if (on('promotions'))
            _Item(
              icon: Icons.local_offer_rounded,
              title: 'Promo & voucher',
              subtitle: 'Happy hour, beli X gratis Y, kode voucher',
              keywords: 'diskon',
              onTap: () => _open(const PromotionsScreen()),
            ),
          if (on('inventory') && can('inventory.manage'))
            _Item(
              icon: Icons.inventory_2_rounded,
              title: 'Stok & resep',
              subtitle: 'Bahan baku, pembelian, opname, HPP',
              keywords: 'inventory gudang supplier',
              onTap: () => _open(const InventoryScreen()),
            ),
        ]),
      if (owner && (on('loyalty') || on('member_tiers') || on('customer_messaging')))
        _Group('Pelanggan', _Tone.customer, [
          if (on('loyalty'))
            _Item(
              icon: Icons.loyalty_rounded,
              title: 'Program loyalitas',
              subtitle: 'Stempel / poin & hadiah',
              keywords: 'member reward',
              onTap: () => _open(const LoyaltySettingsScreen()),
            ),
          if (on('member_tiers'))
            _Item(
              icon: Icons.workspace_premium_rounded,
              title: 'Tingkat member',
              subtitle: 'Silver, Gold: diskon & pengali stempel',
              keywords: 'tier level',
              onTap: () => _open(const TierSettingsScreen()),
            ),
          if (on('customer_messaging'))
            _Item(
              icon: Icons.chat_rounded,
              title: 'Pesan WhatsApp',
              subtitle: 'Struk digital, ulang tahun, pengingat kasbon',
              keywords: 'wa template',
              onTap: () => _open(const MessageTemplatesScreen()),
            ),
        ]),
      if (owner && device != null)
        _Group('Tablet ini', _Tone.danger, [
          _Item(
            icon: Icons.logout_rounded,
            title: 'Keluarkan tablet dari usaha',
            subtitle: '${device.name} (${device.code}) · butuh akun owner untuk daftar lagi',
            keywords: 'cabut perangkat',
            onTap: () => _unregister(device),
          ),
        ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final q = _query.trim().toLowerCase();
    final groups = [
      for (final g in _groups())
        if (g.items.where((i) => q.isEmpty || i.matches(q)).toList() case final items when items.isNotEmpty) _Group(g.label, g.tone, items),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(compact ? AppSpace.s3 : AppSpace.s5, compact ? AppSpace.s3 : AppSpace.s5, compact ? AppSpace.s3 : AppSpace.s5, 96),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AccountCard(),
                const SizedBox(height: AppSpace.s4),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Cari pengaturan…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Hapus pencarian',
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpace.s6),
                    child: AppEmptyState(icon: Icons.search_off_rounded, title: 'Pengaturan tidak ditemukan'),
                  ),
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.s1, AppSpace.s6, AppSpace.s1, AppSpace.s2),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 14,
                          decoration: BoxDecoration(color: g.tone.fg, borderRadius: AppRadius.mdAll),
                        ),
                        const SizedBox(width: AppSpace.s2),
                        AppOverline(g.label, color: g.tone == _Tone.danger ? AppColors.danger : AppColors.inkMuted),
                      ],
                    ),
                  ),
                  _GroupCard(group: g),
                ],
                const SizedBox(height: AppSpace.s6),
                const _VersionFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Kartu akun di atas: siapa yang masuk, usaha, outlet & tablet.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value as LoggedIn?;
    final menu = ref.watch(menuProvider).value?.menu;
    final user = session?.user;
    final device = session?.device;
    final name = user?.name ?? '-';
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final place = [
      if ((device?.tenantName ?? '').isNotEmpty) device!.tenantName,
      if (menu?.multiOutlet ?? false) ?menu?.outlet?.name,
      if (device != null) 'Tablet ${device.code}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: AppRadius.lgAll),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadius.mdAll),
            child: Text(initials, style: AppType.title.copyWith(color: AppColors.onAccent)),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppOverline(user?.role == 'owner' ? 'Owner' : 'Kasir', color: AppColors.onInkMuted),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.titleLg.copyWith(color: AppColors.onInk),
                ),
                if (place.isNotEmpty)
                  Text(
                    place,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: AppColors.onInkMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final _Group group;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.lgAll,
      border: Border.all(color: AppColors.line),
      boxShadow: AppShadow.raised,
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, item) in group.items.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: 72, color: AppColors.line),
          _Row(item: item, tone: group.tone),
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.tone});

  final _Item item;
  final _Tone tone;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: item.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s3),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: tone.bg, borderRadius: AppRadius.mdAll),
                child: Icon(item.icon, size: 22, color: tone.fg),
              ),
              const SizedBox(width: AppSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: AppType.title.copyWith(color: tone == _Tone.danger ? AppColors.danger : AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              if (item.badge != null) ...[const SizedBox(width: AppSpace.s2), item.badge!],
              const SizedBox(width: AppSpace.s1),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkDisabled),
            ],
          ),
        ),
      ),
    ),
  );
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snap) => Text(
      'STRUKASIR${snap.data == null ? '' : ' · v${snap.data!.version}'}',
      textAlign: TextAlign.center,
      style: AppType.overline.copyWith(color: AppColors.inkDisabled),
    ),
  );
}
