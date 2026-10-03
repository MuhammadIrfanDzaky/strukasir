import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      _Destination('Kasir', Icons.point_of_sale, (_) => const PosScreen()),
      _Destination('Riwayat', Icons.receipt_long, (_) => const HistoryScreen()),
      if (user.can('reports.view')) _Destination('Laporan', Icons.bar_chart, (_) => const ReportsScreen()),
      if (user.can('menu.manage')) _Destination('Kelola Menu', Icons.restaurant_menu, (_) => const MenuAdminScreen()),
      _Destination('Printer', Icons.print, (_) => const PrinterSettingsScreen()),
    ];
    final index = _index.clamp(0, destinations.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(destinations[index].label),
        actions: [
          const ShiftChip(),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Muat ulang menu',
            onPressed: () => ref.read(menuProvider.notifier).refresh(),
            icon: const Icon(Icons.sync),
          ),
          Center(child: Text('${user.name} · Tablet ${widget.session.device.code}')),
          IconButton(
            tooltip: 'Keluar',
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          if (destinations.length > 1) ...[
            NavigationRail(
              selectedIndex: index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: destinations[index].builder(context)),
        ],
      ),
    );
  }
}
