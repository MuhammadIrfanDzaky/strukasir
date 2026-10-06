import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import '../session/session_controller.dart';
import 'receipt_format.dart';
import 'receipt_logo.dart';
import 'receipt_preview.dart';

/// Owner mengatur identitas struk kedainya: logo, nama, alamat, dan pesan penutup.
/// Pratinjau di layar memakai format yang sama persis dengan hasil cetak.
class ReceiptSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptSettingsScreen({super.key, required this.current});

  final ReceiptSettings current;

  @override
  ConsumerState<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends ConsumerState<ReceiptSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.current.name);
  late final _header = TextEditingController(text: widget.current.header ?? '');
  late final _footer = TextEditingController(text: widget.current.footer ?? '');

  /// Logo terpasang (base64); null = tanpa logo.
  late String? _logo = widget.current.logoBase64;

  /// Gambar asli pilihan owner, disimpan agar bisa diproses ulang (balik warna / ketebalan).
  Uint8List? _source;
  bool? _invert;
  /// Batas hitam-putih; null = otomatis (diisi nilai hasil otomatis setelah diproses).
  double? _threshold;
  bool _processing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _header, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000);
    if (file == null) return;
    _source = await file.readAsBytes();
    _invert = null; // otomatis untuk gambar baru
    _threshold = null;
    await _process();
  }

  Future<void> _process() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    final result = await compute(processLogo, (source, LogoOptions(invert: _invert, threshold: _threshold?.round())));
    if (!mounted) return;
    setState(() {
      _processing = false;
      if (result == null) {
        _error = 'File tidak bisa dibaca sebagai gambar. Pilih PNG atau JPG.';
      } else if (result.png.length > 64 * 1024) {
        _error = 'Logo terlalu rumit untuk struk (> 64 KB). Pilih gambar yang lebih sederhana.';
      } else {
        _logo = base64Encode(result.png);
        _invert = result.inverted;
        _threshold = result.threshold.toDouble();
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).authed(
            (api, token) => api.put('/settings/receipt', token: token, data: {
              'name': _name.text.trim(),
              'header': _header.text.trim(),
              'footer': _footer.text.trim(),
              if (_logo == null) 'remove_logo': true else if (_logo != widget.current.logoBase64) 'logo': _logo,
            }),
          );
      // Tablet mengambil identitas struk dari menu → muat ulang agar langsung dipakai & di-cache.
      await ref.read(menuProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengaturan struk disimpan.')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Contoh order untuk pratinjau, bentuknya sama dengan OrderResource dari server.
  Map<String, dynamic> get _sample => {
        'number': 'T1-0001',
        'status': 'paid',
        'cashier': (ref.read(sessionProvider).value as LoggedIn?)?.user.name ?? 'Kasir',
        'customer_label': 'Wahyu',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'paid_at': DateTime.now().toUtc().toIso8601String(),
        'items': [
          {
            'name': 'Sanger', 'unit_price': 16000, 'modifiers_total': 2000, 'qty': 1, 'note': null,
            'discount_total': 0, 'modifiers': [{'name': 'Cold', 'price_delta': 2000}],
          },
        ],
        'subtotal': 18000, 'discount_total': 0, 'service_total': 0, 'tax_total': 0, 'rounding': 0,
        'grand_total': 18000, 'change_total': 2000,
        'payments': [{'method': 'cash', 'amount': 18000, 'tendered': 20000}],
        'receipt': {'name': _name.text, 'header': _header.text, 'footer': _footer.text},
      };

  @override
  Widget build(BuildContext context) {
    final wide = context.widthClass == WidthClass.expanded;

    final logoCard = AppSectionCard(
      title: 'Logo',
      children: [
        Text(
          'Pilih gambar logo kedai. Logo otomatis diubah jadi hitam-putih selebar kertas 58 mm.',
          style: AppType.body.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpace.s3),
        Container(
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.line),
          ),
          child: _processing
              ? const CircularProgressIndicator()
              : _logo == null
                  ? Text('Belum ada logo', style: AppType.body.copyWith(color: AppColors.inkMuted))
                  : Padding(
                      padding: const EdgeInsets.all(AppSpace.s2),
                      child: Image.memory(base64Decode(_logo!), fit: BoxFit.contain, gaplessPlayback: true),
                    ),
        ),
        const SizedBox(height: AppSpace.s3),
        Wrap(
          spacing: AppSpace.s2,
          runSpacing: AppSpace.s2,
          children: [
            FilledButton.tonalIcon(
              onPressed: _processing || _saving ? null : _pickLogo,
              icon: const Icon(Icons.image_rounded),
              label: Text(_logo == null ? 'Pilih logo' : 'Ganti logo'),
            ),
            if (_source != null)
              OutlinedButton.icon(
                onPressed: _processing
                    ? null
                    : () {
                        _invert = !(_invert ?? false);
                        _threshold = null; // hitung ulang batas otomatis untuk warna yang dibalik
                        _process();
                      },
                icon: const Icon(Icons.invert_colors_rounded),
                label: const Text('Balik warna'),
              ),
            if (_logo != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _processing || _saving
                    ? null
                    : () => setState(() {
                          _logo = null;
                          _source = null;
                        }),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Hapus logo'),
              ),
          ],
        ),
        if (_source != null && _threshold != null) ...[
          const SizedBox(height: AppSpace.s3),
          Text('Ketebalan', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          Slider(
            value: _threshold!.clamp(40, 220),
            min: 40,
            max: 220,
            divisions: 18,
            label: _threshold! < 110 ? 'Tipis' : (_threshold! > 150 ? 'Tebal' : 'Sedang'),
            onChanged: _processing ? null : (v) => setState(() => _threshold = v),
            onChangeEnd: (_) => _process(),
          ),
        ],
      ],
    );

    final textCard = AppSectionCard(
      title: 'Teks struk',
      children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.characters,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Nama kedai', hintText: 'mis. BERRYBREW KOPI'),
          validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpace.s2),
        TextFormField(
          controller: _header,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Alamat / keterangan (di bawah nama)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpace.s2),
        TextFormField(
          controller: _footer,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Pesan penutup (di akhir struk)'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );

    final preview = AppSectionCard(
      title: 'Pratinjau',
      children: [ReceiptPreview(lines: customerReceipt(_sample), logoBase64: _logo)],
    );

    final form = Form(
      key: _form,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [logoCard, const SizedBox(height: AppSpace.s3), textCard])),
                const SizedBox(width: AppSpace.s4),
                SizedBox(width: 340, child: preview),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [logoCard, const SizedBox(height: AppSpace.s3), textCard, const SizedBox(height: AppSpace.s3), preview],
            ),
    );

    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Pengaturan struk')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(context.isCompact ? AppSpace.s3 : AppSpace.s5),
          children: [
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: form)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s3),
                child: Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s3),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
            onPressed: _saving || _processing ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Simpan'),
          ),
        ),
      ),
    );
  }
}
