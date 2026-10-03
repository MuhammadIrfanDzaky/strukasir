import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_service.dart';
import 'receipt_format.dart';

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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Printer struk', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Pasangkan (pair) printer dulu di Pengaturan → Bluetooth tablet, lalu pilih di bawah.'),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.print),
          title: Text(saved?.name ?? 'Belum ada printer dipilih'),
          subtitle: saved == null ? null : Text(saved.mac),
          trailing: FilledButton.tonal(
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
          ),
        ),
        const Divider(),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final list = await service.pairedPrinters();
                    setState(() {
                      _devices = list;
                      if (list.isEmpty) _message = 'Belum ada perangkat ter-pair.';
                    });
                  }),
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Tampilkan printer ter-pair'),
        ),
        for (final d in _devices)
          ListTile(
            title: Text(d.name),
            subtitle: Text(d.macAdress),
            trailing: saved?.mac == d.macAdress ? const Icon(Icons.check_circle) : null,
            onTap: _busy ? null : () => _run(() => service.choose(d)),
          ),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!)),
      ],
    );
  }
}
