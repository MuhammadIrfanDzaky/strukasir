// M1 — Spike printer (go/no-go).
// Tujuan: membuktikan app Flutter bisa mencetak struk 58mm ke printer iware via
// Bluetooth Classic (SPP), termasuk reconnect setelah layar mati / printer dimatikan.
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'receipt_format.dart';

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Printer Spike',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: const SpikePage(),
      );
}

const _sampleItems = [
  SpikeItem('Americano', 1, 13000, modifiers: ['Hot']),
  SpikeItem('Americano', 1, 15000, modifiers: ['Cold', 'Less sugar']),
  SpikeItem('Kopi Susu Gula Aren Spesial BerryBrew Large', 2, 22000,
      modifiers: ['Extra shot (+5.000)'], note: 'es dipisah ya kak'),
];

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  List<BluetoothInfo> _devices = [];
  String? _mac;
  bool _busy = false;
  final _log = <String>[];

  void _addLog(String msg) {
    final t = TimeOfDay.now().format(context);
    setState(() => _log.insert(0, '[$t] $msg'));
  }

  Future<void> _loadPaired() async {
    // Android 12+ butuh izin runtime BLUETOOTH_CONNECT/SCAN.
    final statuses =
        await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    _addLog('Izin: ${statuses.values.map((s) => s.name).join(', ')}');
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      _addLog('Bluetooth tablet mati — nyalakan dulu.');
      return;
    }
    final list = await PrintBluetoothThermal.pairedBluetooths;
    setState(() => _devices = list);
    _addLog('Perangkat terpasang: ${list.length}');
  }

  Future<bool> _ensureConnected() async {
    if (_mac == null) {
      _addLog('Pilih printer dulu.');
      return false;
    }
    if (await PrintBluetoothThermal.connectionStatus) return true;
    _addLog('Tidak terhubung — mencoba reconnect…');
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (await PrintBluetoothThermal.connect(macPrinterAddress: _mac!)) {
        _addLog('Terhubung (percobaan $attempt).');
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }
    _addLog('GAGAL reconnect setelah 3 percobaan.');
    return false;
  }

  Future<void> _print(String label, List<String> lines) async {
    if (_busy) return;
    setState(() => _busy = true);
    final sw = Stopwatch()..start();
    try {
      if (!await _ensureConnected()) return;
      final gen = Generator(PaperSize.mm58, await CapabilityProfile.load());
      final bytes = <int>[...gen.reset()];
      for (final line in lines) {
        bytes.addAll(gen.text(line));
      }
      bytes
        ..addAll(gen.feed(3))
        ..addAll(gen.cut());
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      _addLog('$label: ${ok ? 'OK' : 'GAGAL'} (${sw.elapsedMilliseconds} ms)');
    } catch (e) {
      _addLog('$label: ERROR $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  String get _now {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BerryBrew — Spike Printer')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: _loadPaired,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('1. Muat printer terpasang (paired)'),
                ),
                RadioGroup<String>(
                  groupValue: _mac,
                  onChanged: (v) async {
                    setState(() => _mac = v);
                    await PrintBluetoothThermal.disconnect;
                    await _ensureConnected();
                  },
                  child: Column(children: [
                    for (final d in _devices)
                      RadioListTile<String>(
                        value: d.macAdress,
                        title: Text(d.name),
                        subtitle: Text(d.macAdress),
                      ),
                  ]),
                ),
                const Divider(),
                const Text('2. Uji cetak'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _print(
                            'Struk lunas',
                            customerReceipt(
                              shopName: 'BerryBrew',
                              orderNo: 'T1-0042',
                              dateTime: _now,
                              cashier: 'Kasir Uji',
                              items: _sampleItems,
                              paid: true,
                              tendered: 100000,
                            )),
                    child: const Text('Struk LUNAS'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _print(
                            'Struk belum bayar',
                            customerReceipt(
                              shopName: 'BerryBrew',
                              orderNo: 'T1-0043',
                              dateTime: _now,
                              cashier: 'Kasir Uji',
                              items: _sampleItems,
                              paid: false,
                            )),
                    child: const Text('Struk BELUM BAYAR'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _print(
                            'Checker',
                            checker(
                                orderNo: 'T1-0042',
                                customer: 'Mas Andi / Meja 3',
                                items: _sampleItems)),
                    child: const Text('Checker barista'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _print('Penggaris 32 kolom', [
                              '12345678901234567890123456789012',
                              divider('='),
                              'Jika baris di atas terpotong/turun,',
                              'lebar printer bukan 32 karakter.',
                            ]),
                    child: const Text('Uji lebar 32 kolom'),
                  ),
                ]),
                const Divider(),
                const Text(
                  '3. Uji ketahanan: matikan layar 1 menit lalu cetak; '
                  'matikan-nyalakan printer lalu cetak; cetak 10x berturut-turut.',
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final l in _log)
                  Text(l, style: const TextStyle(fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
