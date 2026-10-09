import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/tokens.dart';
import 'core/ui/components.dart';
import 'core/ui/responsive.dart';
import 'features/customers/customers_screen.dart';
import 'features/history/history_screen.dart';
import 'features/menu/menu_controller.dart';
import 'features/menu_admin/menu_admin_screen.dart';
import 'features/pos/pos_screen.dart';
import 'features/printing/printer_settings_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/session/account_dialogs.dart';
import 'features/session/session_controller.dart';
import 'features/shift/shift_chip.dart';

/// Kerangka setelah login. Item navigasi mengikuti izin user; server tetap memeriksa ulang.
///
/// HP portrait → bar navigasi bawah; layar ≥600 dp → rail kiri (ringkas di layar pendek).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.session, this.initialIndex = 0});

  final LoggedIn session;

  /// Tab awal (untuk uji tampilan).
  final int initialIndex;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _Destination {
  const _Destination(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index = widget.initialIndex;

  /// "Nanti" pada pengingat verifikasi email: sembunyikan sampai login berikutnya.
  bool _hideVerify = false;

  void _logout() => ref.read(sessionProvider.notifier).logout();

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user;
    final customersOn = ref.watch(menuProvider).value?.menu.customersOn ?? false;
    final compact = context.isCompact;
    final all = [
      _Destination('Kasir', Icons.point_of_sale_rounded, (_) => const PosScreen()),
      _Destination('Riwayat', Icons.receipt_long_rounded, (_) => const HistoryScreen()),
      if (user.can('reports.view')) _Destination('Dashboard', Icons.insights_rounded, (_) => const ReportsScreen()),
      if (user.can('menu.manage'))
        _Destination('Kelola Menu', Icons.restaurant_menu_rounded, (_) => const MenuAdminScreen()),
      if (customersOn && user.can('customers.manage'))
        _Destination('Pelanggan', Icons.groups_rounded, (_) => const CustomersScreen()),
      // Printer untuk semua; Fitur & Struk hanya owner (lihat PrinterSettingsScreen).
      _Destination('Pengaturan', Icons.settings_rounded, (_) => const PrinterSettingsScreen()),
    ];
    // Bar bawah HP maksimal 5 tab (lebih dari itu labelnya terpotong): Pengaturan pindah ke menu akun.
    final settingsInMenu = compact && all.length > 5;
    final destinations = settingsInMenu ? all.where((d) => d.label != 'Pengaturan').toList() : all;
    final index = _index.clamp(0, destinations.length - 1);
    final short = context.isShort;
    // Rail tanpa logo/label/tombol keluar bila tinggi tersisa tidak cukup untuk semua item
    // (HP landscape, atau tablet saat keyboard muncul). Keluar tetap lewat menu akun.
    final railHeight = MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom;
    final tightRail = short || railHeight < 120 + destinations.length * 76;

    final needsVerify = user.email != null && !user.emailVerified;
    void verifyEmail() => showDialog<bool>(context: context, builder: (_) => VerifyEmailDialog(email: user.email!));

    final topBar = _TopBar(
      onVerifyEmail: needsVerify ? verifyEmail : null,
      title: destinations[index].label,
      userName: user.name,
      role: user.role,
      deviceCode: widget.session.device.code,
      outlet: (ref.watch(menuProvider).value?.menu.multiOutlet ?? false) ? ref.watch(menuProvider).value?.menu.outlet?.name : null,
      onRefresh: () => ref.read(menuProvider.notifier).refresh(),
      onLogout: _logout,
      onSettings: settingsInMenu
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: AppColors.surfaceApp,
                  appBar: AppBar(title: const Text('Pengaturan')),
                  body: const PrinterSettingsScreen(),
                ),
              ))
          : null,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topBar,
        // Layar pendek (HP landscape): tanpa banner; tetap bisa lewat menu akun.
        if (needsVerify && !_hideVerify && !short)
          _VerifyEmailBanner(
            email: user.email!,
            onVerify: verifyEmail,
            onLater: () => setState(() => _hideVerify = true),
          ),
        Expanded(child: destinations[index].builder(context)),
      ],
    );

    if (compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1,
          child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.icon), label: switch (d.label) {
                'Kelola Menu' => 'Menu',
                'Pengaturan' => 'Setelan',
                'Dashboard' => 'Laporan',
                'Pelanggan' => 'Member',
                _ => d.label,
              }),
          ],
        ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            // Layar pendek (HP landscape): tanpa logo & label agar semua item muat; keluar lewat menu profil.
            // Lebar tetap saat keyboard muncul (lebar berubah = panel keranjang disusun ulang).
            minWidth: context.widthClass == WidthClass.expanded && !short ? AppSize.rail : 80,
            labelType: tightRail ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            groupAlignment: tightRail ? 0 : -1,
            leading: tightRail
                ? null
                : const Padding(
                    padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s6),
                    child: BrandMark(size: 48, reversed: true),
                  ),
            trailing: tightRail
                ? null
                : Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.s4),
                        child: IconButton(
                          tooltip: 'Keluar',
                          color: AppColors.onInkMuted,
                          onPressed: _logout,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                      ),
                    ),
                  ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label, textAlign: TextAlign.center),
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
                ),
            ],
          ),
          Expanded(child: SafeArea(left: false, child: body)),
        ],
      ),
    );
  }
}

class _VerifyEmailBanner extends StatelessWidget {
  const _VerifyEmailBanner({required this.email, required this.onVerify, required this.onLater});

  final String email;
  final VoidCallback onVerify;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final message = Text(
      'Verifikasi email $email agar bisa reset password bila lupa.',
      style: AppType.body,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final buttons = [
      TextButton(onPressed: onLater, child: const Text('Nanti')),
      FilledButton.tonal(onPressed: onVerify, child: const Text('Verifikasi')),
    ];
    const icon = Icon(Icons.mark_email_unread_rounded, color: AppColors.warning);

    return Container(
      color: AppColors.warningSoft,
      padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s2, AppSpace.s2, AppSpace.s2),
      // Layar sempit: pesan di atas, tombol di bawah (satu baris terlalu sesak).
      child: context.isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [icon, const SizedBox(width: AppSpace.s3), Expanded(child: message)]),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
              ],
            )
          : Row(children: [icon, const SizedBox(width: AppSpace.s3), Expanded(child: message), ...buttons]),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.userName,
    required this.role,
    required this.deviceCode,
    this.outlet,
    required this.onRefresh,
    required this.onLogout,
    this.onVerifyEmail,
    this.onSettings,
  });

  /// HP dengan banyak tab: Pengaturan dibuka dari menu akun.
  final VoidCallback? onSettings;

  /// Null = email sudah terverifikasi / bukan owner.
  final VoidCallback? onVerifyEmail;

  final String title;
  final String userName;
  final String role;
  final String deviceCode;

  /// Nama outlet tablet ini (hanya bila usaha punya lebih dari satu outlet).
  final String? outlet;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  String get _roleLine => '${role == 'owner' ? 'Owner' : 'Kasir'} · Tablet $deviceCode${outlet == null ? '' : ' · $outlet'}';

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final wide = context.widthClass == WidthClass.expanded && !context.isShort;

    return Container(
      height: context.isShort || compact ? 56 : AppSize.topBar,
      padding: EdgeInsets.only(left: compact ? AppSpace.s4 : AppSpace.s5, right: AppSpace.s2),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: compact ? AppType.title : AppType.titleLg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ShiftChip(compact: !wide),
          if (wide) IconButton(tooltip: 'Muat ulang menu', onPressed: onRefresh, icon: const Icon(Icons.sync_rounded)),
          const SizedBox(width: AppSpace.s1),
          PopupMenuButton<String>(
            tooltip: 'Akun',
            position: PopupMenuPosition.under,
            onSelected: (v) => switch (v) {
              'refresh' => onRefresh(),
              'verify' => onVerifyEmail?.call(),
              'settings' => onSettings?.call(),
              _ => onLogout(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(userName, style: AppType.bodyStrong.copyWith(color: AppColors.ink)),
                    Text(_roleLine, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (onVerifyEmail != null)
                const PopupMenuItem(
                  value: 'verify',
                  child: ListTile(leading: Icon(Icons.mark_email_unread_rounded), title: Text('Verifikasi email')),
                ),
              if (onSettings != null)
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(leading: Icon(Icons.settings_rounded), title: Text('Pengaturan')),
                ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(leading: Icon(Icons.sync_rounded), title: Text('Muat ulang menu')),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Keluar')),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: AppSpace.s1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(userName, size: compact ? 32 : 36),
                  if (wide) ...[
                    const SizedBox(width: AppSpace.s2),
                    // Nama outlet bisa panjang: batasi lebar, potong dengan "…".
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(userName, style: AppType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(_roleLine, style: AppType.caption.copyWith(color: AppColors.inkMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
