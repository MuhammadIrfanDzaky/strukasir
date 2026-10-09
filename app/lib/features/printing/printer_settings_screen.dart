import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import 'printer_service.dart';
import '../customers/messaging.dart';
import '../customers/tier_settings_screen.dart';
import '../loyalty/loyalty_settings_screen.dart';
import '../inventory/inventory_screen.dart';
import '../promotions/promotions_screen.dart';
import '../menu/menu_controller.dart';
import '../settings/feature_settings_screen.dart';
import '../session/session_controller.dart';
import 'receipt_format.dart';
import 'receipt_settings_screen.dart';
import 'stations_screen.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  List<BluetoothInfo> _devices = [];
  String? _message;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on PrintException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
    if (ok == true) await _run(() => ref.read(sessionProvider.notifier).unregisterDevice());
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(printerProvider).value;
    final service = ref.read(printerProvider.notifier);

    final compact = context.isCompact;
    final user = (ref.watch(sessionProvider).value as LoggedIn?)?.user;
    final canEditReceipt = user?.can('settings.manage') ?? false;
    final receipt = ref.watch(menuProvider).value?.menu.receipt;
    final loyaltyOn = ref.watch(menuProvider).value?.menu.feature('loyalty') ?? false;
    final tiersOn = ref.watch(menuProvider).value?.menu.feature('member_tiers') ?? false;
    final messagingOn = ref.watch(menuProvider).value?.menu.feature('customer_messaging') ?? false;
    final promotionsOn = ref.watch(menuProvider).value?.menu.feature('promotions') ?? false;
    final inventoryOn = (ref.watch(menuProvider).value?.menu.feature('inventory') ?? false) && (user?.can('inventory.manage') ?? false);
    final device = (ref.watch(sessionProvider).value as LoggedIn?)?.device;
    final testButton = OutlinedButton(
      onPressed: saved == null || _busy
          ? null
          : () => _run(() async {
                await service.printLines([
                  center('TES PRINTER'),
                  divider('='),
                  '12345678901234567890123456789012',
                  ...leftRight('Americano Cold', 'Rp 15.000'),
                  divider(),
                  center('Printer siap dipakai'),
                ]);
                setState(() => _message = 'Tes cetak terkirim.');
              }),
      child: const Text('Tes cetak'),
    );

    return ListView(
      padding: EdgeInsets.all(compact ? AppSpace.s3 : AppSpace.s5),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppSectionCard(
                title: 'Printer struk',
                children: [
                  Text('Pasangkan (pair) printer dulu di Pengaturan → Bluetooth tablet, lalu pilih di bawah.',
                      style: AppType.body.copyWith(color: AppColors.inkMuted)),
                  const SizedBox(height: AppSpace.s4),
                  Container(
                    padding: const EdgeInsets.all(AppSpace.s3),
                    decoration: BoxDecoration(color: AppColors.surfaceApp, borderRadius: AppRadius.mdAll),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: saved == null ? AppColors.surfaceSunken : AppColors.primarySoft,
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: Icon(Icons.print_rounded, color: saved == null ? AppColors.inkMuted : AppColors.primary),
                      ),
                      const SizedBox(width: AppSpace.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(saved?.name ?? 'Belum ada printer dipilih', style: AppType.bodyStrong),
                          if (saved != null)
                            Text(saved.mac, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                        ]),
                      ),
                      if (!compact) testButton,
                    ]),
                    if (compact) ...[const SizedBox(height: AppSpace.s3), testButton],
                  ]),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s4),
              AppSectionCard(
                title: 'Tiket bar / dapur',
                children: [
                  Text(
                    'Cetak tiket pesanan (tanpa harga) untuk barista / dapur saat order disimpan atau dibayar.',
                    style: AppType.body.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.s3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StationsScreen())),
                      icon: const Icon(Icons.local_cafe_rounded),
                      label: const Text('Atur tiket bar / dapur'),
                    ),
                  ),
                ],
              ),
              if (canEditReceipt) ...[
                const SizedBox(height: AppSpace.s4),
                AppSectionCard(
                  title: 'Fitur',
                  children: [
                    Text(
                      'Nyalakan/matikan modul sesuai cara berjualan: nama pelanggan/meja, Open Bill, varian, '
                      'diskon, pajak & service, bayar dengan beberapa metode.',
                      style: AppType.body.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.s3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const FeatureSettingsScreen(),
                        )),
                        icon: const Icon(Icons.toggle_on_rounded),
                        label: const Text('Atur fitur'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s4),
                AppSectionCard(
                  title: 'Struk',
                  children: [
                    Text(
                      'Logo, nama kedai, alamat, dan pesan penutup yang tercetak di setiap struk.',
                      style: AppType.body.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.s3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: receipt == null
                            ? null
                            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => ReceiptSettingsScreen(current: receipt),
                                )),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Atur struk & logo'),
                      ),
                    ),
                  ],
                ),
                if (inventoryOn) ...[
                  const SizedBox(height: AppSpace.s4),
                  AppSectionCard(
                    title: 'Stok & resep',
                    children: [
                      Text(
                        'Stok bahan baku terpotong otomatis dari resep setiap order lunas. Catat pembelian, bahan terbuang, '
                        'dan stok opname; HPP produk dihitung dari resep.',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const InventoryScreen())),
                          icon: const Icon(Icons.inventory_2_rounded),
                          label: const Text('Atur stok & resep'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (promotionsOn) ...[
                  const SizedBox(height: AppSpace.s4),
                  AppSectionCard(
                    title: 'Promo & voucher',
                    children: [
                      Text(
                        'Promo otomatis terjadwal (happy hour, beli X gratis Y) dan voucher kode.',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PromotionsScreen())),
                          icon: const Icon(Icons.local_offer_rounded),
                          label: const Text('Atur promo & voucher'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (loyaltyOn) ...[
                  const SizedBox(height: AppSpace.s4),
                  AppSectionCard(
                    title: 'Program loyalitas',
                    children: [
                      Text(
                        'Stempel / poin untuk member dan hadiah yang bisa ditukar, mis. "beli 10 gratis 1".',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const LoyaltySettingsScreen(),
                          )),
                          icon: const Icon(Icons.loyalty_rounded),
                          label: const Text('Atur program loyalitas'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (tiersOn) ...[
                  const SizedBox(height: AppSpace.s4),
                  AppSectionCard(
                    title: 'Tingkat member',
                    children: [
                      Text(
                        'Silver, Gold, dst.: naik otomatis dari belanja, dengan diskon & pengali stempel/poin.',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const TierSettingsScreen(),
                          )),
                          icon: const Icon(Icons.workspace_premium_rounded),
                          label: const Text('Atur tingkat member'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (messagingOn) ...[
                  const SizedBox(height: AppSpace.s4),
                  AppSectionCard(
                    title: 'Pesan WhatsApp',
                    children: [
                      Text(
                        'Teks struk digital, ucapan ulang tahun, sapaan pelanggan lama, dan pengingat kasbon.',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const MessageTemplatesScreen(),
                          )),
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('Atur pesan WhatsApp'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: AppSpace.s4),
              AppSectionCard(
                title: 'Printer ter-pair',
                trailing: (compact ? FilledButton.tonalIcon : FilledButton.icon)(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final list = await service.pairedPrinters();
                            setState(() {
                              _devices = list;
                              if (list.isEmpty) _message = 'Belum ada perangkat ter-pair.';
                            });
                          }),
                  icon: const Icon(Icons.bluetooth_searching_rounded),
                  label: const Text('Tampilkan'),
                ),
                empty: 'Ketuk "Tampilkan" untuk melihat printer yang sudah di-pair.',
                children: [
                  for (final d in _devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bluetooth_rounded),
                      title: Text(d.name),
                      subtitle: Text(d.macAdress),
                      trailing: saved?.mac == d.macAdress
                          ? const AppBadge('Dipakai', tone: AppTone.success, icon: Icons.check_rounded)
                          : null,
                      onTap: _busy ? null : () => _run(() => service.choose(d)),
                    ),
                ],
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: AppSpace.s4), child: LinearProgressIndicator()),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s4),
                  child: Text(_message!, style: AppType.body),
                ),
              if (canEditReceipt && device != null) ...[
                const SizedBox(height: AppSpace.s4),
                AppSectionCard(
                  title: 'Tablet ini',
                  children: [
                    Text(
                      '${device.name} (${device.code}) · ${device.tenantName}. Keluarkan bila tablet ini akan dipakai '
                      'usaha lain atau tidak dipakai lagi.',
                      style: AppType.body.copyWith(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.s3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: _busy ? null : () => _unregister(device),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Keluarkan tablet dari usaha'),
                      ),
                    ),
                  ],
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}
