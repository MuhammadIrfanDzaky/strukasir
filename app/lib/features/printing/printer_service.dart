import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'receipt_format.dart';

export 'receipt_format.dart' show PrintLine;

/// Logo struk (PNG base64 dari server) → gambar siap cetak, maks. 384 titik (lebar kertas 58 mm).
/// Null bila tidak ada logo atau datanya rusak.
img.Image? decodeLogo(String? base64) {
  if (base64 == null || base64.isEmpty) return null;
  try {
    final image = img.decodePng(base64Decode(base64));
    if (image == null) return null;
    return image.width > 384 ? img.copyResize(image, width: 384) : image;
  } catch (_) {
    return null;
  }
}

/// Logo → perintah raster ESC/POS (GS v 0), dipotong per 64 baris titik supaya buffer printer murah
/// tidak meluap. Titik hitam = piksel gelap & tidak transparan. Dibuat sendiri karena
/// `Generator.imageRaster` (esc_pos_utils_plus 2.0.4) salah membaca PNG 1-kanal dan lebar yang
/// bukan kelipatan 8 → logo tercetak hitam penuh.
List<int> rasterImage(img.Image image) {
  final widthBytes = (image.width + 7) ~/ 8;
  final out = <int>[];
  for (var top = 0; top < image.height; top += 64) {
    final rows = (image.height - top).clamp(0, 64);
    out.addAll([0x1D, 0x76, 0x30, 0x00, widthBytes & 0xFF, widthBytes >> 8, rows & 0xFF, rows >> 8]);
    for (var y = top; y < top + rows; y++) {
      for (var xb = 0; xb < widthBytes; xb++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xb * 8 + bit;
          if (x >= image.width) continue;
          final p = image.getPixel(x, y);
          final opaque = p.a > p.maxChannelValue / 2; // gambar tanpa alfa: a = maks
          // Abu-abu (1–2 kanal): g/b terbaca 0 → `luminance` salah (putih jadi 0.299); pakai r.
          final light = image.numChannels <= 2 ? p.rNormalized : p.luminanceNormalized;
          if (opaque && light < 0.5) byte |= 0x80 >> bit;
        }
        out.add(byte);
      }
    }
  }
  return out;
}

/// Sisa kertas setelah baris terakhir sampai gerigi sobek (mm), ketetapan untuk semua struk.
/// Gerigi printer 58 mm ±12 mm dari kepala cetak, jadi margin atas struk berikutnya juga ±12 mm.
/// 8 titik = 1 mm.
const int kTailMm = 12;
List<int> feedMm(int mm) => [0x1B, 0x4A, (mm * 8).clamp(0, 255)]; // ESC J n

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

  /// Cetak baris teks biasa (sudah diformat 32 kolom).
  Future<void> printLines(List<String> lines, {int copies = 1}) =>
      printDocument([for (final l in lines) PrintLine(l)], copies: copies);

  /// Cetak dokumen: logo kedai (PNG base64, opsional) di atas, lalu baris teks (sebagian tebal).
  /// Menyambung ulang otomatis bila terputus. Logo rusak dilewati; struk tetap tercetak.
  Future<void> printDocument(List<PrintLine> lines, {String? logoBase64, int copies = 1}) async {
    final printer = state.value;
    if (printer == null) throw PrintException('Printer belum dipilih. Buka menu Printer.');

    await _ensureConnected(printer.mac);

    final gen = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final logo = decodeLogo(logoBase64);
    final bytes = <int>[...gen.reset()];
    for (var c = 0; c < copies; c++) {
      if (logo != null) {
        bytes
          ..addAll(gen.setStyles(const PosStyles(align: PosAlign.center)))
          ..addAll(rasterImage(logo));
      }
      for (final line in lines) {
        bytes.addAll(gen.text(line.text, styles: PosStyles(bold: line.bold)));
      }
      // Dorong kertas secukupnya sampai baris terakhir lewat gerigi sobek (tanpa baris kosong ekstra).
      bytes.addAll(feedMm(kTailMm));
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
