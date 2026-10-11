import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import 'printer_service.dart';
import 'receipt_format.dart';

/// Pengaturan → Printer struk: pilih printer Bluetooth yang sudah di-pair & tes cetak.
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

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(printerProvider).value;
    final service = ref.read(printerProvider.notifier);

    final compact = context.isCompact;
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

    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Printer struk')),
      body: ListView(
        padding: EdgeInsets.all(compact ? AppSpace.s3 : AppSpace.s5),
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionCard(
                    title: 'Printer struk',
                    children: [
                      Text(
                        'Pasangkan (pair) printer dulu di Pengaturan → Bluetooth tablet, lalu pilih di bawah.',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s4),
                      Container(
                        padding: const EdgeInsets.all(AppSpace.s3),
                        decoration: BoxDecoration(color: AppColors.surfaceApp, borderRadius: AppRadius.mdAll),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(saved?.name ?? 'Belum ada printer dipilih', style: AppType.bodyStrong),
                                      if (saved != null) Text(saved.mac, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                                    ],
                                  ),
                                ),
                                if (!compact) testButton,
                              ],
                            ),
                            if (compact) ...[const SizedBox(height: AppSpace.s3), testButton],
                          ],
                        ),
                      ),
                    ],
                  ),
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
                          title: Text(d.name),
                          subtitle: Text(d.macAdress),
                          trailing: saved?.mac == d.macAdress ? const AppBadge('Dipakai', tone: AppTone.success, ) : null,
                          onTap: _busy ? null : () => _run(() => service.choose(d)),
                        ),
                    ],
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpace.s4),
                      child: LinearProgressIndicator(),
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.s4),
                      child: Text(_message!, style: AppType.body),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
