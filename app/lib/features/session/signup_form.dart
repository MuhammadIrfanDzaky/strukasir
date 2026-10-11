import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/theme/tokens.dart';
import 'session_controller.dart';
import 'setup_screen.dart';
import 'signup_options.dart';

/// Ikon cara berjualan (kode = enum `SalesMode` di server; label dari server).
const _salesModeIcons = {
  'takeaway': Icons.shopping_basket_rounded,
  'dine_in': Icons.table_restaurant_rounded,
  'mixed': Icons.compare_arrows_rounded,
};

/// Field server yang ada di langkah 1 (usaha); sisanya di langkah 2 (akun owner).
const _businessFields = {
  'business_name', 'sector', 'sector_other', 'sales_mode', 'province_code', 'regency_code', 'outlet_count', 'phone',
  'address',
};

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
  final _sectorOther = TextEditingController();
  final _server = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _emailCode = TextEditingController();

  /// Pesan setelah kode dikirim, mis. "Kode dikirim ke ...".
  String? _codeInfo;

  int _step = 0;
  String? _sector;
  String? _salesMode;
  String? _province;
  String? _regency;

  /// Pilihan jenis usaha & wilayah dari server (dimuat saat pertama dibutuhkan).
  SignupOptions? _options;
  bool _loadingOptions = false;
  int _outlets = 1;
  bool _terms = false;
  bool _showPassword = false;
  bool _busy = false;
  bool _submitted = false; // tampilkan error pilihan (sektor, cara jualan, S&K) setelah dicoba
  String? _error;
  Map<String, String> _serverErrors = {};

  @override
  void dispose() {
    for (final c in [_businessName, _phone, _address, _sectorOther, _server, _ownerName, _email, _password, _pin, _pin2, _emailCode]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _serverError(String field) => _serverErrors[field];

  String get _serverUrl => ServerUrlField.needed ? _server.text.trim() : kApiUrl;

  SectorOption? get _sectorOption => _options?.sector(_sector);
  bool get _asksSalesMode => _sectorOption?.asksSalesMode ?? false;

  @override
  void initState() {
    super.initState();
    // Build produksi: alamat server sudah tertanam, jadi pilihan langsung dimuat.
    if (!ServerUrlField.needed) _ensureOptions();
  }

  /// Muat pilihan sekali. Build development butuh alamat server diisi dulu.
  Future<SignupOptions?> _ensureOptions() async {
    if (_options != null) return _options;
    if (Uri.tryParse(_serverUrl)?.host.isEmpty ?? true) {
      setState(() => _error = 'Isi alamat server dulu.');
      return null;
    }
    setState(() {
      _loadingOptions = true;
      _error = null;
    });
    try {
      final options = await ref.read(signupOptionsLoaderProvider)(_serverUrl);
      if (mounted) setState(() => _options = options);
      return options;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return null;
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _pickSector() async {
    final options = await _ensureOptions();
    if (options == null || !mounted) return;
    final code = await showOptionPicker<String>(
      context,
      title: 'Jenis usaha',
      searchHint: 'Cari jenis usaha, mis. laundry',
      selected: _sector,
      items: [for (final s in options.sectors) PickerItem(s.code, s.label, group: s.group)],
    );
    if (code != null) setState(() => _sector = code);
  }

  Future<void> _pickProvince() async {
    final options = await _ensureOptions();
    if (options == null || !mounted) return;
    final code = await showOptionPicker<String>(
      context,
      title: 'Provinsi',
      searchHint: 'Cari provinsi',
      selected: _province,
      items: [for (final p in options.provinces) PickerItem(p.code, p.name)],
    );
    if (code != null && code != _province) {
      setState(() {
        _province = code;
        _regency = null; // kota/kabupaten harus dipilih ulang
      });
    }
  }

  Future<void> _pickRegency() async {
    final province = _options?.province(_province);
    if (province == null) return;
    final regencies = [...province.children]..sort((a, b) => a.name.compareTo(b.name));
    final code = await showOptionPicker<String>(
      context,
      title: 'Kota / kabupaten',
      searchHint: 'Cari kota atau kabupaten',
      selected: _regency,
      items: [for (final r in regencies) PickerItem(r.code, r.name)],
    );
    if (code != null) setState(() => _regency = code);
  }

  void _next() {
    setState(() => _submitted = true);
    final ok = _businessForm.currentState!.validate();
    if (!ok || _sector == null || (_asksSalesMode && _salesMode == null) || _province == null || _regency == null) {
      return;
    }
    setState(() {
      _step = 1;
      _submitted = false;
      _error = null;
    });
  }

  /// Langkah 2 → 3: kirim kode verifikasi ke email (akun belum dibuat).
  Future<void> _sendCode({bool resend = false}) async {
    if (!resend) {
      setState(() => _submitted = true);
      if (!_ownerForm.currentState!.validate() || !_terms) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _serverErrors = {};
    });
    try {
      final message = await ref
          .read(sessionProvider.notifier)
          .sendSignupCode(serverUrl: _serverUrl, email: _email.text, ownerName: _ownerName.text);
      setState(() {
        _codeInfo = message;
        _step = 2;
        _submitted = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _serverErrors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
        if (_serverErrors.containsKey('email')) _step = 1;
        // Kode baru saja dikirim (jeda 1 menit): tetap lanjut ke isian kode.
        if (e.status == 429 && _step == 1 && !resend) {
          _step = 2;
          _codeInfo = 'Kode sudah dikirim ke ${_email.text.trim()}. Periksa juga folder spam.';
        } else if (_serverErrors.isEmpty) {
          _error = e.message;
        }
      });
      _ownerForm.currentState?.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_emailCode.text.trim().length != 6) {
      setState(() => _serverErrors = {'email_code': 'Isi 6 angka dari email'});
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _serverErrors = {};
    });
    try {
      await ref.read(sessionProvider.notifier).signup(
            serverUrl: _serverUrl,
            data: SignupData(
              businessName: _businessName.text,
              sector: _sector!,
              sectorOther: _sector == 'other' ? _sectorOther.text : null,
              salesMode: _asksSalesMode ? _salesMode : null,
              provinceCode: _province!,
              regencyCode: _regency!,
              outletCount: _outlets,
              phone: _phone.text,
              address: _address.text,
              ownerName: _ownerName.text,
              email: _email.text,
              password: _password.text,
              pin: _pin.text,
              emailCode: _emailCode.text,
            ),
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      final errors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
      setState(() {
        _serverErrors = errors;
        // Kembali ke langkah tempat kesalahan berada supaya terlihat.
        if (errors.keys.any(_businessFields.contains)) {
          _step = 0;
        } else if (errors.keys.any((f) => f != 'email_code')) {
          _step = 1;
        }
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
    return switch (_step) {
      0 => _businessStep(),
      1 => _ownerStep(),
      _ => _verifyStep(),
    };
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
            step: 'Langkah 1 dari 3',
            title: 'Tentang usaha Anda',
            subtitle: 'Dipakai untuk struk dan menyesuaikan aplikasi dengan cara Anda berjualan.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: AppSpace.s5),
          if (ServerUrlField.needed) ...[ServerUrlField(controller: _server), const SizedBox(height: AppSpace.s3)],
          TextFormField(
            controller: _businessName,
            decoration: const InputDecoration(labelText: 'Nama usaha', helperText: 'Tercetak di bagian atas struk', ),
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
            onChanged: (_) => _serverErrors.remove('business_name'),
          ),
          const SizedBox(height: AppSpace.s3),
          PickerField(
            label: 'Jenis usaha',
            icon: Icons.category_rounded,
            value: _sectorOption?.label,
            loading: _loadingOptions,
            onTap: _pickSector,
            errorText: _serverError('sector') ?? (_submitted && _sector == null ? 'Pilih jenis usaha' : null),
          ),
          if (_sector == 'other') ...[
            const SizedBox(height: AppSpace.s3),
            TextFormField(
              controller: _sectorOther,
              decoration: const InputDecoration(labelText: 'Sebutkan bidang usaha', hintText: 'mis. Rental PS, Toko mainan', ),
              maxLength: 60,
              validator: (v) => (v?.trim().isNotEmpty ?? false) ? _serverError('sector_other') : 'Wajib diisi',
            ),
          ],
          if (_asksSalesMode) ...[
            const SizedBox(height: AppSpace.s4),
            _label('Cara berjualan'),
            Wrap(
              spacing: AppSpace.s2,
              runSpacing: AppSpace.s2,
              children: [
                for (final (code, label) in _options!.salesModes)
                  ChoiceChip(
                    avatar: Icon(_salesModeIcons[code] ?? Icons.storefront_rounded, size: 18),
                    label: Text(label),
                    showCheckmark: false,
                    selected: _salesMode == code,
                    onSelected: (_) => setState(() => _salesMode = code),
                  ),
              ],
            ),
            if (_submitted && _salesMode == null) _choiceError('Pilih cara berjualan'),
            if (_serverError('sales_mode') != null) _choiceError(_serverError('sales_mode')!),
          ],
          if (_sector != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s2),
              child: Text(
                'Fitur & kategori awal disiapkan sesuai pilihan ini. Bisa diubah kapan saja di Pengaturan → Fitur.',
                style: AppType.caption.copyWith(color: AppColors.inkMuted),
              ),
            ),
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
          PickerField(
            label: 'Provinsi',
            icon: Icons.map_rounded,
            value: _options?.province(_province)?.name,
            loading: _loadingOptions,
            onTap: _pickProvince,
            errorText: _serverError('province_code') ?? (_submitted && _province == null ? 'Pilih provinsi' : null),
          ),
          const SizedBox(height: AppSpace.s3),
          PickerField(
            label: 'Kota / kabupaten',
            icon: Icons.location_city_rounded,
            value: _options?.province(_province)?.children.where((r) => r.code == _regency).firstOrNull?.name,
            enabled: _province != null,
            onTap: _pickRegency,
            errorText: _serverError('regency_code') ??
                (_submitted && _province != null && _regency == null ? 'Pilih kota / kabupaten' : null),
          ),
          const SizedBox(height: AppSpace.s3),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Detail alamat (opsional)', hintText: 'Jalan, nomor, kelurahan', helperText: 'Tercetak di bawah nama usaha pada struk', helperMaxLines: 2, ),
            minLines: 1,
            maxLines: 3,
            maxLength: 300,
            validator: (_) => _serverError('address'),
          ),
          const SizedBox(height: AppSpace.s3),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Nomor HP / WA (opsional)', ),
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
              step: 'Langkah 2 dari 3',
              title: 'Akun owner',
              subtitle: 'Email & password untuk menambah tablet. PIN untuk masuk kasir sehari-hari.',
              onBack: () => setState(() {
                _step = 0;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpace.s5),
            TextFormField(
              controller: _ownerName,
              decoration: const InputDecoration(labelText: 'Nama Anda', ),
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              maxLength: 60,
              validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
            ),
            const SizedBox(height: AppSpace.s3),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email', ),
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
              decoration: InputDecoration(labelText: 'Password', helperText: 'Minimal 8 karakter, ada huruf dan angka', suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Sembunyikan' : 'Tampilkan',
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                ), ),
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
              onPressed: _busy ? null : _sendCode,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Kirim kode verifikasi'),
            ),
          ],
        ),
      ),
    );
  }

  /// Langkah 3: kode dari email → usaha dibuat & langsung masuk ke Kasir.
  Widget _verifyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormHeader(
          step: 'Langkah 3 dari 3',
          title: 'Verifikasi email',
          subtitle: _codeInfo ?? 'Masukkan kode 6 digit yang kami kirim ke ${_email.text.trim()}.',
          onBack: () => setState(() {
            _step = 1;
            _error = null;
          }),
        ),
        const SizedBox(height: AppSpace.s5),
        TextField(
          controller: _emailCode,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Kode 6 digit dari email', counterText: '', errorText: _serverErrors['email_code'], ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          onChanged: (_) {
            if (_serverErrors.containsKey('email_code')) setState(() => _serverErrors.remove('email_code'));
          },
        ),
        const SizedBox(height: AppSpace.s2),
        Wrap(
          spacing: AppSpace.s2,
          children: [
            TextButton(onPressed: _busy ? null : () => _sendCode(resend: true), child: const Text('Kirim ulang kode'), ),
            TextButton(onPressed: _busy ? null : () => setState(() => _step = 1), child: const Text('Ubah email'), ),
          ],
        ),
        Text(
          'Tidak ada di kotak masuk? Periksa folder spam / promosi. Kode berlaku 15 menit.',
          style: AppType.caption.copyWith(color: AppColors.inkMuted),
        ),
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
    );
  }

  Widget _pinField(TextEditingController c, String label, FormFieldValidator<String> validator) => TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label, counterText: '', ),
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
