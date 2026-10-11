import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import 'customer_api.dart';

/// Form daftar / ubah pelanggan. Kasir: nama, no HP, catatan. Owner ([full]) juga tanggal lahir.
/// Mengembalikan pelanggan yang tersimpan, atau null bila dibatalkan.
Future<Customer?> showCustomerForm(
  BuildContext context, {
  Customer? customer,
  String initialName = '',
  String initialPhone = '',
  required bool phoneRequired,
  bool full = false,
}) =>
    showDialog<Customer>(
      context: context,
      builder: (_) => CustomerFormDialog(
        customer: customer,
        initialName: initialName,
        initialPhone: initialPhone,
        phoneRequired: phoneRequired,
        full: full,
      ),
    );

class CustomerFormDialog extends ConsumerStatefulWidget {
  const CustomerFormDialog({
    super.key,
    this.customer,
    this.initialName = '',
    this.initialPhone = '',
    required this.phoneRequired,
    this.full = false,
  });

  final Customer? customer;
  final String initialName;
  final String initialPhone;
  final bool phoneRequired;
  final bool full;

  @override
  ConsumerState<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<CustomerFormDialog> {
  late final _name = TextEditingController(text: widget.customer?.name ?? widget.initialName);
  late final _phone = TextEditingController(text: formatPhone(widget.customer?.phone).isEmpty
      ? widget.initialPhone
      : formatPhone(widget.customer?.phone));
  late final _note = TextEditingController(text: widget.customer?.note ?? '');
  late String? _birthDate = widget.customer?.birthDate;
  Map<String, String> _errors = {};
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate != null ? DateTime.parse(_birthDate!) : DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Tanggal lahir',
    );
    if (picked != null) {
      setState(() => _birthDate =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Isi nama pelanggan',
      if (widget.phoneRequired && _phone.text.trim().isEmpty) 'phone': 'No HP wajib diisi',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
      _error = null;
    });
    try {
      final saved = await ref.read(customerApiProvider).save(
            id: widget.customer?.id,
            name: _name.text,
            phone: _phone.text,
            birthDate: widget.full ? _birthDate : null,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context, saved);
    } on ApiException catch (e) {
      setState(() {
        _errors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
        _error = e.fieldErrors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.customer != null;
    return AlertDialog(
      scrollable: true,
      title: Text(editing ? 'Ubah pelanggan' : 'Pelanggan baru'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (editing) ...[
              Text('Kode member ${widget.customer!.code}', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
              const SizedBox(height: AppSpace.s3),
            ],
            TextField(
              controller: _name,
              autofocus: !editing && widget.initialName.isEmpty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 80,
              decoration: InputDecoration(labelText: 'Nama *', errorText: _errors['name'], counterText: '', ),
            ),
            const SizedBox(height: AppSpace.s3),
            TextField(
              controller: _phone,
              autofocus: !editing && widget.initialName.isNotEmpty && widget.initialPhone.isEmpty,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))],
              decoration: InputDecoration(labelText: widget.phoneRequired ? 'No HP / WhatsApp *' : 'No HP / WhatsApp', hintText: '0812-3456-7890', errorText: _errors['phone'], helperText: widget.phoneRequired ? null : 'Boleh dikosongkan', ),
            ),
            if (widget.full) ...[
              const SizedBox(height: AppSpace.s3),
              InputDecorator(
                decoration: InputDecoration(labelText: 'Tanggal lahir', errorText: _errors['birth_date'], suffixIcon: _birthDate == null
                      ? null
                      : IconButton(
                          tooltip: 'Hapus tanggal lahir',
                          onPressed: () => setState(() => _birthDate = null),
                          icon: const Icon(Icons.close_rounded),
                        ), ),
                child: InkWell(
                  onTap: _busy ? null : _pickBirthDate,
                  child: Text(_birthDate == null ? 'Pilih tanggal (opsional)' : formatDate(_birthDate!),
                      style: AppType.body.copyWith(color: _birthDate == null ? AppColors.inkMuted : AppColors.ink)),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s3),
            TextField(
              controller: _note,
              maxLength: 200,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Catatan', hintText: 'mis. alergi susu, suka less sugar', errorText: _errors['note'], ),
            ),
            if (!editing)
              Text(
                'Minta izin pelanggan sebelum mencatat datanya.',
                style: AppType.caption.copyWith(color: AppColors.inkMuted),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.s2),
              Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(editing ? 'Simpan' : 'Daftarkan'),
        ),
      ],
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/// "1990-05-01" → "1 Mei 1990".
String formatDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : '${d.day} ${_months[d.month - 1]} ${d.year}';
}
