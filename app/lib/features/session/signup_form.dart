import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/theme/tokens.dart';
import 'session_controller.dart';
import 'setup_screen.dart';

/// Sektor usaha (kode = enum `BusinessSector` di server).
const kSectors = [
  ('coffee_shop', 'Kedai kopi / kafe', Icons.local_cafe_rounded),
  ('restaurant', 'Rumah makan / resto', Icons.restaurant_rounded),
  ('street_food', 'Jajanan / gerobak', Icons.fastfood_rounded),
  ('bakery', 'Roti & kue', Icons.bakery_dining_rounded),
  ('retail', 'Toko / retail', Icons.shopping_bag_rounded),
  ('service', 'Jasa', Icons.handyman_rounded),
  ('other', 'Lainnya', Icons.more_horiz_rounded),
];

/// Cara berjualan (kode = enum `SalesMode` di server).
const kSalesModes = [
  ('takeaway', 'Bawa pulang saja', Icons.shopping_basket_rounded),
  ('dine_in', 'Makan di tempat', Icons.table_restaurant_rounded),
  ('mixed', 'Keduanya', Icons.compare_arrows_rounded),
];

/// Field server yang ada di langkah 1 (usaha); sisanya di langkah 2 (akun owner).
const _businessFields = {'business_name', 'sector', 'sales_mode', 'outlet_count', 'phone', 'address'};

/// PIN mudah ditebak: angka sama semua atau berurutan (sama dengan aturan server).
bool weakPin(String pin) =>
    pin.split('').toSet().length == 1 || '01234567890'.contains(pin) || '09876543210'.contains(pin);

/// Daftar usaha baru, 2 langkah: (1) usaha, (2) akun owner. Berhasil → tablet ini terdaftar
/// dan owner langsung masuk ke Kasir.
class SignupForm extends ConsumerStatefulWidget {
  const SignupForm({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<SignupForm> createState() => _SignupFormState();
}

class _SignupFormState extends ConsumerState<SignupForm> {
  final _businessForm = GlobalKey<FormState>();
  final _ownerForm = GlobalKey<FormState>();

  final _businessName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _server = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();

  int _step = 0;
  String? _sector;
  String? _salesMode;
  int _outlets = 1;
  bool _terms = false;
  bool _showPassword = false;
  bool _busy = false;
  bool _submitted = false; // tampilkan error pilihan (sektor, cara jualan, S&K) setelah dicoba
  String? _error;
  Map<String, String> _serverErrors = {};

  @override
  void dispose() {
    for (final c in [_businessName, _phone, _address, _server, _ownerName, _email, _password, _pin, _pin2]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _serverError(String field) => _serverErrors[field];

  void _next() {
    setState(() => _submitted = true);
    final ok = _businessForm.currentState!.validate();
    if (!ok || _sector == null || _salesMode == null) return;
    setState(() {
      _step = 1;
      _submitted = false;
      _error = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_ownerForm.currentState!.validate() || !_terms) return;
    setState(() {
      _busy = true;
      _error = null;
      _serverErrors = {};
    });
    try {
      await ref.read(sessionProvider.notifier).signup(
            serverUrl: ServerUrlField.needed ? _server.text.trim() : kApiUrl,
            data: SignupData(
              businessName: _businessName.text,
              sector: _sector!,
              salesMode: _salesMode!,
              outletCount: _outlets,
              phone: _phone.text,
              address: _address.text,
              ownerName: _ownerName.text,
              email: _email.text,
              password: _password.text,
              pin: _pin.text,
            ),
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
      setState(() {
        _serverErrors = errors;
        // Kesalahan di data usaha → kembali ke langkah 1 supaya terlihat.
        if (errors.keys.any(_businessFields.contains)) _step = 0;
        _error = errors.isEmpty ? e.message : 'Periksa kembali isian yang ditandai.';
      });
      _businessForm.currentState?.validate();
      _ownerForm.currentState?.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _step == 0 ? _businessStep() : _ownerStep();
  }

  Widget _choiceError(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.s1),
        child: Text(text, style: AppType.caption.copyWith(color: AppColors.danger)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.s2),
        child: Text(text, style: AppType.bodyStrong),
      );

  Widget _businessStep() {
    return Form(
      key: _businessForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeader(
            step: 'Langkah 1 dari 2',
            title: 'Tentang usaha Anda',
            subtitle: 'Dipakai untuk struk dan menyesuaikan aplikasi dengan cara Anda berjualan.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: AppSpace.s5),
          TextFormField(
            controller: _businessName,
            decoration: const InputDecoration(
              labelText: 'Nama usaha',
              helperText: 'Tercetak di bagian atas struk',
              prefixIcon: Icon(Icons.storefront_rounded),
            ),
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
            onChanged: (_) => _serverErrors.remove('business_name'),
          ),
          const SizedBox(height: AppSpace.s3),
          _label('Jenis usaha'),
          Wrap(
            spacing: AppSpace.s2,
            runSpacing: AppSpace.s2,
            children: [
              for (final (code, label, icon) in kSectors)
                ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  showCheckmark: false,
                  selected: _sector == code,
                  onSelected: (_) => setState(() => _sector = code),
                ),
            ],
          ),
          if (_submitted && _sector == null) _choiceError('Pilih jenis usaha'),
          if (_serverError('sector') != null) _choiceError(_serverError('sector')!),
          const SizedBox(height: AppSpace.s4),
          _label('Cara berjualan'),
          Wrap(
            spacing: AppSpace.s2,
            runSpacing: AppSpace.s2,
            children: [
              for (final (code, label, icon) in kSalesModes)
                ChoiceChip(
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  showCheckmark: false,
                  selected: _salesMode == code,
                  onSelected: (_) => setState(() => _salesMode = code),
                ),
            ],
          ),
          if (_submitted && _salesMode == null) _choiceError('Pilih cara berjualan'),
          if (_serverError('sales_mode') != null) _choiceError(_serverError('sales_mode')!),
          const SizedBox(height: AppSpace.s4),
          Row(
            children: [
              Expanded(child: Text('Jumlah outlet / cabang', style: AppType.bodyStrong)),
              IconButton.outlined(
                tooltip: 'Kurangi',
                onPressed: _outlets <= 1 ? null : () => setState(() => _outlets--),
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(width: 48, child: Text('$_outlets', textAlign: TextAlign.center, style: AppType.title)),
              IconButton.outlined(
                tooltip: 'Tambah',
                onPressed: _outlets >= 999 ? null : () => setState(() => _outlets++),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s4),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Alamat (opsional)',
              helperText: 'Tercetak di bawah nama usaha pada struk',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.place_rounded),
            ),
            minLines: 1,
            maxLines: 3,
            maxLength: 300,
            validator: (_) => _serverError('address'),
          ),
          const SizedBox(height: AppSpace.s3),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Nomor HP / WA (opsional)', prefixIcon: Icon(Icons.phone_rounded)),
            keyboardType: TextInputType.phone,
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isNotEmpty && !RegExp(r'^\+?[0-9 \-]{8,20}$').hasMatch(t)) return 'Nomor HP tidak valid';
              return _serverError('phone');
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.s3),
            Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpace.s5),
          FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  Widget _ownerStep() {
    return Form(
      key: _ownerForm,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              step: 'Langkah 2 dari 2',
              title: 'Akun owner',
              subtitle: 'Email & password untuk menambah tablet. PIN untuk masuk kasir sehari-hari.',
              onBack: () => setState(() {
                _step = 0;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpace.s5),
            if (ServerUrlField.needed) ...[ServerUrlField(controller: _server), const SizedBox(height: AppSpace.s3)],
            TextFormField(
              controller: _ownerName,
              decoration: const InputDecoration(labelText: 'Nama Anda', prefixIcon: Icon(Icons.person_rounded)),
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              maxLength: 60,
              validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
            ),
            const SizedBox(height: AppSpace.s3),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (v) {
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')) return 'Email tidak valid';
                return _serverError('email');
              },
              onChanged: (_) => _serverErrors.remove('email'),
            ),
            const SizedBox(height: AppSpace.s3),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'Minimal 8 karakter, ada huruf dan angka',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Sembunyikan' : 'Tampilkan',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                ),
              ),
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) {
                final p = v ?? '';
                if (p.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(p) || !RegExp(r'\d').hasMatch(p)) {
                  return 'Minimal 8 karakter, ada huruf dan angka';
                }
                return _serverError('password');
              },
            ),
            const SizedBox(height: AppSpace.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _pinField(_pin, 'PIN kasir (6 digit)', (v) {
                  if (!RegExp(r'^\d{6}$').hasMatch(v ?? '')) return 'Isi 6 angka';
                  if (weakPin(v!)) return 'Terlalu mudah ditebak';
                  return _serverError('pin');
                })),
                const SizedBox(width: AppSpace.s3),
                Expanded(child: _pinField(_pin2, 'Ulangi PIN', (v) => v == _pin.text ? null : 'PIN tidak sama')),
              ],
            ),
            const SizedBox(height: AppSpace.s3),
            CheckboxListTile(
              value: _terms,
              onChanged: (v) => setState(() => _terms = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Saya menyetujui '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: () => _showTerms(context),
                      child: Text('syarat & kebijakan privasi',
                          style: AppType.body.copyWith(color: AppColors.primary, decoration: TextDecoration.underline)),
                    ),
                  ),
                ]),
                style: AppType.body,
              ),
            ),
            if (_submitted && !_terms) _choiceError('Setujui syarat & kebijakan privasi untuk melanjutkan.'),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.s3),
              Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpace.s5),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Daftar & mulai'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController c, String label, FormFieldValidator<String> validator) => TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label, counterText: '', prefixIcon: const Icon(Icons.pin_rounded)),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        obscureText: true,
        maxLength: 6,
        validator: validator,
      );

  void _showTerms(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Syarat & kebijakan privasi'),
          content: SizedBox(
            width: 480,
            child: Text(
              'Data yang kami simpan: nama usaha, jenis usaha, alamat & nomor HP (bila diisi), nama dan email owner, '
              'serta data transaksi, menu, dan staf yang Anda masukkan. Password & PIN disimpan dalam bentuk '
              'terenkripsi satu arah (tidak bisa dibaca siapa pun).\n\n'
              'Data dipakai hanya untuk menjalankan aplikasi kasir untuk usaha Anda, tidak dijual dan tidak '
              'dibagikan ke pihak lain. Anda dapat meminta salinan atau penghapusan data usaha Anda kapan saja.',
              style: AppType.body,
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
        ),
      );
}
