import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/tokens.dart';
import 'core/ui/components.dart';
import 'features/history/history_screen.dart';
import 'features/menu/menu_controller.dart';
import 'features/menu_admin/menu_admin_screen.dart';
import 'features/pos/pos_screen.dart';
import 'features/printing/printer_settings_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/session/session_controller.dart';
import 'features/shift/shift_chip.dart';

/// Kerangka setelah login. Item navigasi mengikuti izin user; server tetap memeriksa ulang.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.session});

  final LoggedIn session;

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
  int _index = 0;

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

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: const Padding(
              padding: EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s6),
              child: BrandMark(size: 48, reversed: true),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s4),
                  child: IconButton(
                    tooltip: 'Keluar',
                    color: AppColors.onInkMuted,
                    onPressed: () => ref.read(sessionProvider.notifier).logout(),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  title: destinations[index].label,
                  userName: user.name,
                  role: user.role,
                  deviceCode: widget.session.device.code,
                  onRefresh: () => ref.read(menuProvider.notifier).refresh(),
                ),
                Expanded(child: destinations[index].builder(context)),
              ],
            ),
          ),
        ],
      ),
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
  });

  final String title;
  final String userName;
  final String role;
  final String deviceCode;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        height: AppSize.topBar,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s5),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          Text(title, style: AppType.titleLg),
          const Spacer(),
          const ShiftChip(),
          const SizedBox(width: AppSpace.s2),
          IconButton(tooltip: 'Muat ulang menu', onPressed: onRefresh, icon: const Icon(Icons.sync_rounded)),
          const SizedBox(width: AppSpace.s2),
          const SizedBox(height: 32, child: VerticalDivider()),
          const SizedBox(width: AppSpace.s3),
          AppAvatar(userName, size: 36),
          const SizedBox(width: AppSpace.s2),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(userName, style: AppType.bodyStrong),
            Text('${role == 'owner' ? 'Owner' : 'Kasir'} · Tablet $deviceCode',
                style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ]),
        ]),
      );
}
