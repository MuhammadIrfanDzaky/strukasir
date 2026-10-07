import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/tokens.dart';
import 'core/ui/components.dart';
import 'core/ui/responsive.dart';
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
    final destinations = [
      _Destination('Kasir', Icons.point_of_sale_rounded, (_) => const PosScreen()),
      _Destination('Riwayat', Icons.receipt_long_rounded, (_) => const HistoryScreen()),
      if (user.can('reports.view')) _Destination('Laporan', Icons.bar_chart_rounded, (_) => const ReportsScreen()),
      if (user.can('menu.manage'))
        _Destination('Kelola Menu', Icons.restaurant_menu_rounded, (_) => const MenuAdminScreen()),
      _Destination('Printer', Icons.print_rounded, (_) => const PrinterSettingsScreen()),
    ];
    final index = _index.clamp(0, destinations.length - 1);
    final compact = context.isCompact;
    final short = context.isShort;

    final needsVerify = user.email != null && !user.emailVerified;
    void verifyEmail() => showDialog<bool>(context: context, builder: (_) => VerifyEmailDialog(email: user.email!));

    final topBar = _TopBar(
      onVerifyEmail: needsVerify ? verifyEmail : null,
      title: destinations[index].label,
      userName: user.name,
      role: user.role,
      deviceCode: widget.session.device.code,
      onRefresh: () => ref.read(menuProvider.notifier).refresh(),
      onLogout: _logout,
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
              NavigationDestination(icon: Icon(d.icon), label: d.label == 'Kelola Menu' ? 'Menu' : d.label),
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
            minWidth: context.widthClass == WidthClass.expanded && !short ? AppSize.rail : 80,
            labelType: short ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            groupAlignment: short ? 0 : -1,
            leading: short
                ? null
                : const Padding(
                    padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s6),
                    child: BrandMark(size: 48, reversed: true),
                  ),
            trailing: short
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
    required this.onRefresh,
    required this.onLogout,
    this.onVerifyEmail,
  });

  /// Null = email sudah terverifikasi / bukan owner.
  final VoidCallback? onVerifyEmail;

  final String title;
  final String userName;
  final String role;
  final String deviceCode;
  final VoidCallback onRefresh;
  final VoidCallback onLogout;

  String get _roleLine => '${role == 'owner' ? 'Owner' : 'Kasir'} · Tablet $deviceCode';

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
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName, style: AppType.bodyStrong),
                        Text(_roleLine, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                      ],
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
