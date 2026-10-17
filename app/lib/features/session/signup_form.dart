import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../core/theme/tokens.dart';
import '../legal/legal_screen.dart';
import '../subscription/subscription.dart';
import 'session_controller.dart';
import 'setup_screen.dart';
import 'signup_options.dart';

/// Field server yang ada di langkah 1 (usaha); sisanya di langkah 2 (akun owner).
const _businessFields = {
  'business_name', 'sector', 'sector_other', 'sales_mode', 'province_code', 'regency_code', 'phone',
  'address',
};

/// PIN mudah ditebak: angka sama semua atau berurutan (sama dengan aturan server).
bool weakPin(String pin) =>
    pin.split('').toSet().length == 1 || '01234567890'.contains(pin) || '09876543210'.contains(pin);

/// Daftar usaha baru: (1) usaha, (2) paket, (3) akun owner, (4) kode email. Berhasil → tablet ini terdaftar
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
  final _server = TextEditingController(text: ServerUrlField.devDefault);
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  final _emailCode = TextEditingController();

  /// Kode referral dari usaha pengajak (opsional).
  final _referral = TextEditingController();

  /// Pesan setelah kode dikirim, mis. "Kode dikirim ke ...".
  String? _codeInfo;

  int _step = 0;

  /// Paket pilihan: Gratis = coba 7 hari; berbayar = menunggu pembayaran.
  String _plan = 'gratis';
  String _period = 'month';
  String? _sector;
  String? _province;
  String? _regency;

  /// Pilihan jenis usaha & wilayah dari server (dimuat saat pertama dibutuhkan).
  SignupOptions? _options;
  bool _loadingOptions = false;
  bool _terms = false;
  bool _showPassword = false;
  bool _busy = false;
  bool _submitted = false; // tampilkan error pilihan (sektor, cara jualan, S&K) setelah dicoba
  String? _error;
  Map<String, String> _serverErrors = {};

  @override
  void dispose() {
    for (final c in [_businessName, _phone, _address, _sectorOther, _server, _ownerName, _email, _password, _pin, _pin2, _emailCode, _referral]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _serverError(String field) => _serverErrors[field];

  String get _serverUrl => ServerUrlField.needed ? _server.text.trim() : kApiUrl;

  SectorOption? get _sectorOption => _options?.sector(_sector);

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
    if (!ok || _sector == null || _province == null || _regency == null) {
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
        _step = 3;
        _submitted = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _serverErrors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
        if (_serverErrors.containsKey('email')) _step = 2;
        // Kode baru saja dikirim (jeda 1 menit): tetap lanjut ke isian kode.
        if (e.status == 429 && _step == 2 && !resend) {
          _step = 3;
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
              provinceCode: _province!,
              regencyCode: _regency!,
              phone: _phone.text,
              address: _address.text,
              ownerName: _ownerName.text,
              email: _email.text,
              password: _password.text,
              pin: _pin.text,
              emailCode: _emailCode.text,
              plan: _plan,
              period: _period,
              referralCode: _referral.text,
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
        } else if (errors.containsKey('plan') || errors.containsKey('period') || errors.containsKey('referral_code')) {
          _step = 1;
        } else if (errors.keys.any((f) => f != 'email_code')) {
          _step = 2;
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
      1 => _planStep(),
      2 => _ownerStep(),
      _ => _verifyStep(),
    };
  }

  Widget _choiceError(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.s1),
        child: Text(text, style: AppType.caption.copyWith(color: AppColors.danger)),
      );

  Widget _businessStep() {
    final nameField = TextFormField(
      controller: _businessName,
      decoration: const InputDecoration(labelText: 'Nama usaha', helperText: 'Tercetak di bagian atas struk', ),
      textCapitalization: TextCapitalization.words,
      maxLength: 80,
      validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
      onChanged: (_) => _serverErrors.remove('business_name'),
    );
    final sectorField = PickerField(
      label: 'Jenis usaha',
      icon: Icons.category_rounded,
      value: _sectorOption?.label,
      loading: _loadingOptions,
      onTap: _pickSector,
      errorText: _serverError('sector') ?? (_submitted && _sector == null ? 'Pilih jenis usaha' : null),
    );
    final otherField = TextFormField(
      controller: _sectorOther,
      decoration: const InputDecoration(labelText: 'Sebutkan bidang usaha', hintText: 'mis. Rental PS, Toko mainan', ),
      maxLength: 60,
      validator: (v) => (v?.trim().isNotEmpty ?? false) ? _serverError('sector_other') : 'Wajib diisi',
    );
    final provinceField = PickerField(
      label: 'Provinsi',
      icon: Icons.map_rounded,
      value: _options?.province(_province)?.name,
      loading: _loadingOptions,
      onTap: _pickProvince,
      errorText: _serverError('province_code') ?? (_submitted && _province == null ? 'Pilih provinsi' : null),
    );
    final regencyField = PickerField(
      label: 'Kota / kabupaten',
      icon: Icons.location_city_rounded,
      value: _options?.province(_province)?.children.where((r) => r.code == _regency).firstOrNull?.name,
      enabled: _province != null,
      onTap: _pickRegency,
      errorText: _serverError('regency_code') ??
          (_submitted && _province != null && _regency == null ? 'Pilih kota / kabupaten' : null),
    );
    final addressField = TextFormField(
      controller: _address,
      decoration: const InputDecoration(labelText: 'Detail alamat (opsional)', hintText: 'Jalan, nomor, kelurahan', helperText: 'Tercetak di bawah nama usaha pada struk', helperMaxLines: 2, ),
      minLines: 1,
      maxLines: 3,
      maxLength: 300,
      validator: (_) => _serverError('address'),
    );
    final phoneField = TextFormField(
      controller: _phone,
      decoration: const InputDecoration(labelText: 'Nomor HP / WA (opsional)', ),
      keyboardType: TextInputType.phone,
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isNotEmpty && !RegExp(r'^\+?[0-9 \-]{8,20}$').hasMatch(t)) return 'Nomor HP tidak valid';
        return _serverError('phone');
      },
    );

    return Form(
      key: _businessForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeader(
            step: 'Langkah 1 dari 4',
            title: 'Tentang usaha Anda',
            subtitle: 'Dipakai untuk struk dan menyesuaikan aplikasi dengan cara Anda berjualan.',
            onBack: widget.onBack,
          ),
          const SizedBox(height: AppSpace.s5),
          if (ServerUrlField.needed) ...[ServerUrlField(controller: _server), const SizedBox(height: AppSpace.s5)],
          FormSection(
            title: 'Identitas usaha',
            // Takeaway / Dine-in tidak ditanya lagi: aktif otomatis untuk usaha makan & minum, diatur di Pengaturan → Fitur.
            caption: 'Fitur & kategori awal disiapkan sesuai jenis usaha. Bisa diubah kapan saja di Pengaturan → Fitur.',
            children: [
              FieldGrid(children: [nameField, sectorField, if (_sector == 'other') otherField]),
            ],
          ),
          const FormSectionDivider(),
          FormSection(
            title: 'Lokasi & kontak',
            caption: 'Alamat tercetak di struk. Nomor HP untuk laporan & bantuan.',
            children: [
              FieldGrid(children: [provinceField, regencyField, addressField, phoneField]),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.s3),
            Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpace.s5),
          FormActions(child: FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
            child: const Text('Lanjut'),
          )),
        ],
      ),
    );
  }

  /// Langkah 2: Gratis (coba 7 hari) atau langsung paket berbayar.
  Widget _planStep() {
    final plans = _options?.plans ?? const <PlanInfo>[];
    final chosen = plans.where((p) => p.code == _plan).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormHeader(
          step: 'Langkah 2 dari 4',
          title: 'Pilih paket',
          subtitle: 'Mulai gratis 7 hari, atau langsung pilih paket berbayar. Paket bisa diganti kapan saja.',
          onBack: () => setState(() {
            _step = 0;
            _error = null;
          }),
        ),
        const SizedBox(height: AppSpace.s5),
        PlanPicker(
          plans: plans,
          selected: _plan,
          period: _period,
          onSelected: (c) => setState(() => _plan = c),
          onPeriod: (p) => setState(() => _period = p),
        ),
        if (_serverError('plan') != null) _choiceError(_serverError('plan')!),
        const SizedBox(height: AppSpace.s4),
        FormActions(
          leading: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _referral,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: 'Kode referral (opsional)',
                  helperText: 'Diajak usaha lain? Coba gratis 14 hari & diskon 25% untuk pembayaran paket pertama.',
                  helperMaxLines: 2,
                  counterText: '',
                  errorText: _serverError('referral_code'),
                ),
                onChanged: (_) => setState(() => _serverErrors.remove('referral_code')),
              ),
              const SizedBox(height: AppSpace.s2),
              Text(
                chosen == null || chosen.free
                    ? 'Tanpa kartu kredit. Setelah masa coba, pilih paket berbayar untuk lanjut berjualan; data tetap tersimpan.'
                    : 'Paket ${chosen.name} langsung bisa dipakai. Bayar dengan QRIS dari menu Upgrade paket '
                        'sebelum masa coba berakhir; tanpa tagihan otomatis.',
                style: AppType.caption.copyWith(color: AppColors.inkMuted),
              ),
            ],
          ),
          child: FilledButton(
            onPressed: () => setState(() {
              _step = 2;
              _error = null;
            }),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
            child: Text(chosen == null || chosen.free
                ? 'Mulai gratis ${_referral.text.trim().isEmpty ? 7 : 14} hari'
                : 'Lanjut dengan ${chosen.name}'),
          ),
        ),
      ],
    );
  }

  Widget _ownerStep() {
    final nameField = TextFormField(
      controller: _ownerName,
      decoration: const InputDecoration(labelText: 'Nama Anda', ),
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.name],
      maxLength: 60,
      validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
    );
    final emailField = TextFormField(
      controller: _email,
      decoration: const InputDecoration(labelText: 'Email', ),
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      validator: (v) {
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')) return 'Email tidak valid';
        return _serverError('email');
      },
      onChanged: (_) => _serverErrors.remove('email'),
    );
    final passwordField = TextFormField(
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
    );
    final pinField = _pinField(_pin, 'PIN kasir (6 digit)', (v) {
      if (!RegExp(r'^\d{6}$').hasMatch(v ?? '')) return 'Isi 6 angka';
      if (weakPin(v!)) return 'Terlalu mudah ditebak';
      return _serverError('pin');
    });
    final pin2Field = _pinField(_pin2, 'Ulangi PIN', (v) => v == _pin.text ? null : 'PIN tidak sama');

    return Form(
      key: _ownerForm,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormHeader(
              step: 'Langkah 3 dari 4',
              title: 'Akun owner',
              subtitle: 'Email & password untuk menambah tablet. PIN untuk masuk kasir sehari-hari.',
              onBack: () => setState(() {
                _step = 1;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpace.s5),
            FormSection(
              title: 'Data owner',
              caption: 'Email dipakai untuk masuk dari tablet baru, kode verifikasi, dan kuitansi.',
              children: [FieldGrid(children: [nameField, emailField, passwordField])],
            ),
            const FormSectionDivider(),
            FormSection(
              title: 'PIN kasir',
              caption: '6 angka untuk masuk kasir sehari-hari. Hindari angka berurutan atau sama semua.',
              children: [FieldGrid(children: [pinField, pin2Field])],
            ),
            const FormSectionDivider(),
            FormSection(
              title: 'Persetujuan',
              children: [
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
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.s3),
              Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpace.s5),
            FormActions(child: FilledButton(
              onPressed: _busy ? null : _sendCode,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Kirim kode verifikasi'),
            )),
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
          step: 'Langkah 4 dari 4',
          title: 'Verifikasi email',
          subtitle: _codeInfo ?? 'Masukkan kode 6 digit yang kami kirim ke ${_email.text.trim()}.',
          onBack: () => setState(() {
            _step = 2;
            _error = null;
          }),
        ),
        const SizedBox(height: AppSpace.s5),
        FormSection(
          title: 'Kode verifikasi',
          caption: 'Tidak ada di kotak masuk? Periksa folder spam / promosi. Kode berlaku 15 menit.',
          children: [
            FieldGrid(children: [
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
              Wrap(
                spacing: AppSpace.s2,
                children: [
                  TextButton(onPressed: _busy ? null : () => _sendCode(resend: true), child: const Text('Kirim ulang kode'), ),
                  TextButton(onPressed: _busy ? null : () => setState(() => _step = 2), child: const Text('Ubah email'), ),
                ],
              ),
            ]),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.s3),
          Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpace.s5),
        FormActions(child: FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Daftar & mulai'),
        )),
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

  void _showTerms(BuildContext context) => LegalScreen.open(context);
}


/// Bagian formulir: judul + keterangan di kiri, isian di kanan (layar lebar); bertumpuk di HP.
class FormSection extends StatelessWidget {
  const FormSection({super.key, required this.title, this.caption, required this.children});

  final String title;
  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppType.title),
      if (caption != null) ...[
        const SizedBox(height: AppSpace.s1),
        Text(caption!, style: AppType.caption.copyWith(color: AppColors.inkMuted, height: 1.45)),
      ],
    ]);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 860) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: AppSpace.s3), body]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 260, child: head),
        const SizedBox(width: AppSpace.s8),
        Expanded(child: body),
      ]);
    });
  }
}

class FormSectionDivider extends StatelessWidget {
  const FormSectionDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.s5), child: Divider(height: 1));
}

/// Isian dua kolom di layar lebar (berpasangan, rata atas); satu kolom di HP.
class FieldGrid extends StatelessWidget {
  const FieldGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final two = c.maxWidth >= 520;
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += two ? 2 : 1) {
        if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpace.s3));
        rows.add(two
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: children[i]),
                const SizedBox(width: AppSpace.s4),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
              ])
            : children[i]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}

/// Baris tombol bawah: di layar lebar tombol di kanan (lebar tetap), isian tambahan di kiri; di HP bertumpuk.
class FormActions extends StatelessWidget {
  const FormActions({super.key, required this.child, this.leading});

  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 720) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (leading != null) ...[leading!, const SizedBox(height: AppSpace.s4)],
          child,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: leading == null ? const SizedBox() : Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 472), child: leading),
        )),
        const SizedBox(width: AppSpace.s6),
        SizedBox(width: 300, child: child),
      ]);
    });
  }
}
