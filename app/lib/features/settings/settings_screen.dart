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
import '../subscription/locked_feature.dart';
import '../session/session_controller.dart';
import '../staff/staff_screen.dart';
import 'feature_settings_screen.dart';
import '../../core/ui/toast.dart';

/// Satu baris pengaturan: judul (apa), keterangan (isi/status), lalu buka halaman atau jalankan aksi.
class _Item {
  const _Item({required this.title, required this.subtitle, required this.onTap, this.badge, this.keywords = ''});

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Status singkat di kanan (mis. nama printer belum dipilih, paket pembuka fitur terkunci).
  final Widget? badge;

  /// Kata tambahan untuk pencarian.
  final String keywords;

  bool matches(String q) => '$title $subtitle $keywords'.toLowerCase().contains(q);
}

class _Group {
  const _Group(this.label, this.items, {this.danger = false});

  final String label;
  final List<_Item> items;

  /// Aksi berisiko (keluarkan tablet): judul baris merah, tanpa warna lain.
  final bool danger;
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
    final messenger = AppToast.of(context);
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
    // Fitur di luar paket tetap tampil (terkunci) untuk owner: ketuk → penjelasan & ajakan upgrade.
    LockedFeature? lockedOf(String f) => owner ? menu?.locked(f) : null;
    bool shown(String f) => on(f) || lockedOf(f) != null;
    _Item gated(String feature, _Item item) {
      final l = lockedOf(feature);
      return l == null || on(feature)
          ? item
          : _Item(
              title: item.title,
              subtitle: item.subtitle,
              keywords: '${item.keywords} upgrade paket',
              badge: LockedBadge(l),
              onTap: () => showLockedFeature(context, l),
            );
    }

    return [
      if (owner)
        _Group('Usaha', [
          _Item(
            title: 'Fitur',
            subtitle: 'Open bill, varian, diskon, pajak & service, laporan',
            keywords: 'modul paket aktifkan',
            onTap: () => _open(const FeatureSettingsScreen()),
          ),
          _Item(
            title: 'Outlet',
            subtitle: lockedOf('multi_outlet') != null
                ? 'Tambah cabang mulai paket ${lockedOf('multi_outlet')!.planName}'
                : menu?.outlet == null ? 'Cabang & tablet per outlet' : 'Tablet ini di ${menu!.outlet!.name}',
            badge: lockedOf('multi_outlet') == null ? null : LockedBadge(lockedOf('multi_outlet')!),
            keywords: 'cabang toko tablet pindah',
            onTap: () => _open(const OutletsScreen()),
          ),
          _Item(
            title: 'Pegawai',
            subtitle: 'Tambah kasir, ganti PIN, nonaktifkan',
            keywords: 'kasir staf karyawan pin akses user',
            onTap: () => _open(const StaffScreen()),
          ),
          _Item(
            title: 'Struk & logo',
            subtitle: 'Nama usaha, alamat, pesan penutup',
            keywords: 'header footer cetak',
            onTap: () {
              final receipt = menu?.receipt;
              if (receipt != null) _open(ReceiptSettingsScreen(current: receipt));
            },
          ),
        ]),
      _Group('Perangkat', [
        _Item(
          title: 'Printer struk',
          subtitle: printer == null ? 'Pilih printer Bluetooth' : printer.name,
          badge: printer == null ? const AppBadge('Belum dipilih', tone: AppTone.warning) : null,
          keywords: 'bluetooth tes cetak',
          onTap: () => _open(const PrinterSettingsScreen()),
        ),
        _Item(
          title: 'Tiket bar / dapur',
          subtitle: 'Cetak pesanan per stasiun, tanpa harga',
          keywords: 'checker kitchen printer',
          onTap: () => _open(const StationsScreen()),
        ),
      ]),
      if (owner && (shown('promotions') || (shown('inventory') && (can('inventory.manage') || lockedOf('inventory') != null))))
        _Group('Penjualan & produk', [
          if (shown('promotions'))
            gated('promotions', _Item(
              title: 'Promo & voucher',
              subtitle: 'Happy hour, bundling, harga spesial, kode voucher',
              keywords: 'diskon paket',
              onTap: () => _open(const PromotionsScreen()),
            )),
          if (shown('inventory') && (can('inventory.manage') || lockedOf('inventory') != null))
            gated('inventory', _Item(
              title: 'Stok & resep',
              subtitle: 'Bahan baku, pembelian, opname, HPP',
              keywords: 'inventory gudang supplier',
              onTap: () => _open(const InventoryScreen()),
            )),
        ]),
      if (owner && (shown('loyalty') || shown('member_tiers') || shown('customer_messaging')))
        _Group('Pelanggan', [
          if (shown('loyalty'))
            gated('loyalty', _Item(
              title: 'Program loyalitas',
              subtitle: 'Stempel / poin & hadiah',
              keywords: 'member reward',
              onTap: () => _open(const LoyaltySettingsScreen()),
            )),
          if (shown('member_tiers'))
            gated('member_tiers', _Item(
              title: 'Tingkat member',
              subtitle: 'Silver, Gold: diskon & pengali stempel',
              keywords: 'tier level',
              onTap: () => _open(const TierSettingsScreen()),
            )),
          if (shown('customer_messaging'))
            gated('customer_messaging', _Item(
              title: 'Pesan WhatsApp',
              subtitle: 'Struk digital, ulang tahun, pengingat kasbon',
              keywords: 'wa template',
              onTap: () => _open(const MessageTemplatesScreen()),
            )),
          if (lockedOf('customer_credit') != null)
            gated('customer_credit', const _Item(
              title: 'Kasbon pelanggan',
              subtitle: 'Bayar nanti dengan batas, pelunasan di kasir, laporan piutang',
              keywords: 'piutang hutang',
              onTap: _noop,
            )),
        ]),
      if (owner && device != null)
        _Group('Tablet ini', danger: true, [
          _Item(
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
        if (g.items.where((i) => q.isEmpty || i.matches(q)).toList() case final items when items.isNotEmpty) _Group(g.label, items, danger: g.danger),
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
                  Padding(padding: const EdgeInsets.fromLTRB(AppSpace.s1, AppSpace.s6, AppSpace.s1, AppSpace.s2), child: AppOverline(g.label)),
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
    final place = [
      if ((device?.tenantName ?? '').isNotEmpty) device!.tenantName,
      if (menu?.multiOutlet ?? false) ?menu?.outlet?.name,
      if (device != null) 'Tablet ${device.code}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          AppAvatar(name, size: 48),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppOverline(user?.role == 'owner' ? 'Owner' : 'Kasir'),
                const SizedBox(height: 2),
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.titleLg),
                if (place.isNotEmpty)
                  Text(
                    place,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: AppColors.inkMuted),
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
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (i, item) in group.items.indexed) ...[
          if (i > 0) const Divider(height: 1, indent: AppSpace.s4, color: AppColors.line),
          _Row(item: item, danger: group.danger),
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.item, this.danger = false});

  final _Item item;
  final bool danger;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: item.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: AppType.bodyStrong.copyWith(color: danger ? AppColors.danger : AppColors.ink)),
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

void _noop() {}
