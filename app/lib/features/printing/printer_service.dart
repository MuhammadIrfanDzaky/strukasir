import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrintException implements Exception {
  PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SavedPrinter {
  const SavedPrinter(this.mac, this.name);

  final String mac;
  final String name;
}

final printerProvider = AsyncNotifierProvider<PrinterService, SavedPrinter?>(PrinterService.new);

/// Printer thermal Bluetooth Classic (SPP) — terbukti di spike M1. Mencetak dari data lokal di
/// tablet; tidak ada panggilan server di jalur cetak. Kegagalan cetak tidak membatalkan transaksi.
class PrinterService extends AsyncNotifier<SavedPrinter?> {
  static const _storage = FlutterSecureStorage();
  static const _macKey = 'printer_mac';
  static const _nameKey = 'printer_name';

  @override
  Future<SavedPrinter?> build() async {
    final mac = await _storage.read(key: _macKey);
    return mac == null ? null : SavedPrinter(mac, await _storage.read(key: _nameKey) ?? mac);
  }

  Future<List<BluetoothInfo>> pairedPrinters() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw PrintException('Bluetooth tablet mati. Nyalakan Bluetooth dulu.');
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> choose(BluetoothInfo device) async {
    await PrintBluetoothThermal.disconnect;
    await _storage.write(key: _macKey, value: device.macAdress);
    await _storage.write(key: _nameKey, value: device.name);
    state = AsyncData(SavedPrinter(device.macAdress, device.name));
  }

  /// Cetak baris teks (sudah diformat 32 kolom). Menyambung ulang otomatis bila terputus.
  Future<void> printLines(List<String> lines, {int copies = 1}) async {
    final printer = state.value;
    if (printer == null) throw PrintException('Printer belum dipilih. Buka menu Printer.');

    await _ensureConnected(printer.mac);

    final gen = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final bytes = <int>[...gen.reset()];
    for (var c = 0; c < copies; c++) {
      for (final line in lines) {
        bytes.addAll(gen.text(line));
      }
      bytes
        ..addAll(gen.feed(3))
        ..addAll(gen.cut());
    }

    if (!await PrintBluetoothThermal.writeBytes(bytes)) {
      throw PrintException('Gagal mengirim ke printer. Coba cetak ulang.');
    }
  }

  Future<void> _ensureConnected(String mac) async {
    if (await PrintBluetoothThermal.connectionStatus) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (await PrintBluetoothThermal.connect(macPrinterAddress: mac)) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    throw PrintException('Printer tidak terhubung. Pastikan printer menyala & dekat tablet.');
  }
}
