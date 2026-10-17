import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../../core/ui/toast.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';
import 'receipt_logo.dart';

/// Pengaturan → Pembayaran QRIS (owner): unggah QRIS statis kedai untuk ditunjukkan ke pembeli saat
/// bayar dan (opsional) dicetak di bill belum dibayar. Dana tetap masuk ke rekening merchant QRIS owner.
class QrisSettingsScreen extends ConsumerStatefulWidget {
  const QrisSettingsScreen({super.key});

  @override
  ConsumerState<QrisSettingsScreen> createState() => _QrisSettingsScreenState();
}

class _QrisSettingsScreenState extends ConsumerState<QrisSettingsScreen> {
  late final _menu = ref.read(menuProvider).value?.menu;
  late String? _image = _menu?.qrisImage;
  late bool _onBill = _menu?.qrisImage == null ? true : _menu!.qrisOnBill;
  bool _processing = false;
  bool _saving = false;
  String? _error;

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _processing = true;
      _error = null;
    });
    final result = await compute(processQris, bytes);
    if (!mounted) return;
    setState(() {
      _processing = false;
      if (result == null) {
        _error = 'Gambar tidak bisa dipakai. Pilih foto/screenshot QRIS yang jelas (PNG atau JPG).';
      } else if (result.png.length > 96 * 1024) {
        _error = 'Gambar terlalu rumit (> 96 KB). Potong gambar supaya hanya kotak QR-nya, lalu pilih lagi.';
      } else {
        _image = base64Encode(result.png);
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).authed((api, token) => api.put('/settings/qris', token: token, data: {
            if (_image == null) 'remove_image': true else if (_image != _menu?.qrisImage) 'image': _image,
            'print_on_bill': _onBill,
          }));
      await ref.read(menuProvider.notifier).refresh();
      if (!mounted) return;
      AppToast.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan QRIS disimpan.')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    final busy = _processing || _saving;
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Pembayaran QRIS')),
      body: ListView(padding: EdgeInsets.fromLTRB(pad, pad, pad, 96), children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Unggah QRIS statis usaha Anda (dari bank / e-wallet). Saat kasir memilih QRIS, kode ini tampil besar '
                'di tablet beserta nominalnya untuk dipindai pembeli. Uang tetap masuk langsung ke rekening merchant Anda.',
                style: AppType.body.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: AppSpace.s4),
              AppSectionCard(title: 'Kode QRIS', children: [
                if (_image != null)
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(AppSpace.s3),
                      child: Image.memory(base64Decode(_image!),
                          width: 240, height: 240, fit: BoxFit.contain, filterQuality: FilterQuality.none, gaplessPlayback: true),
                    ),
                  )
                else
                  Text('Belum ada QRIS. Kasir tetap bisa memilih QRIS dengan kode yang ditempel di meja kasir.',
                      style: AppType.body.copyWith(color: AppColors.inkMuted)),
                const SizedBox(height: AppSpace.s2),
                Text('Tips: potong gambar hanya bagian kotak QR supaya tetap tajam saat dicetak.',
                    style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                const SizedBox(height: AppSpace.s3),
                Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
                  FilledButton.tonal(
                    onPressed: busy ? null : _pick,
                    child: Text(_processing ? 'Memproses…' : (_image == null ? 'Pilih gambar QRIS' : 'Ganti gambar')),
                  ),
                  if (_image != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger, backgroundColor: AppColors.dangerSoft),
                      onPressed: busy ? null : () => setState(() => _image = null),
                      child: const Text('Hapus QRIS'),
                    ),
                ]),
              ]),
              const SizedBox(height: AppSpace.s4),
              AppSectionCard(title: 'Bill belum dibayar', children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _onBill,
                  onChanged: busy ? null : (v) => setState(() => _onBill = v),
                  title: Text('Cetak QRIS di bill', style: AppType.bodyStrong),
                  subtitle: Text('Bill open bill yang dicetak memuat QRIS & total, jadi pelanggan bisa bayar dari meja.',
                      style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                ),
              ]),
              if (_error != null) ...[
                const SizedBox(height: AppSpace.s3),
                Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
              ],
              const SizedBox(height: AppSpace.s4),
              FilledButton(
                onPressed: busy ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
                child: _saving
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Simpan'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
