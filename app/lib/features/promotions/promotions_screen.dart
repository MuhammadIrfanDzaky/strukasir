import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import '../session/session_controller.dart';
import 'promotion_models.dart';

/// Pengaturan → Promo & voucher (owner).
class PromotionsScreen extends ConsumerStatefulWidget {
  const PromotionsScreen({super.key});

  @override
  ConsumerState<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends ConsumerState<PromotionsScreen> {
  List<Promotion>? _promos;
  List<Map<String, dynamic>>? _vouchers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/settings/promotions', token: token));
      final data = res['data'] as Map<String, dynamic>;
      setState(() {
        _promos = (data['promotions'] as List).cast<Map<String, dynamic>>().map(Promotion.fromJson).toList();
        _vouchers = (data['vouchers'] as List).cast<Map<String, dynamic>>();
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _editPromo([Promotion? p]) async {
    final menu = ref.read(menuProvider).value?.menu;
    if (menu == null) return;
    final saved = await showDialog<bool>(context: context, builder: (_) => _PromoForm(menu: menu, promo: p));
    if (saved == true) {
      _load();
      ref.read(menuProvider.notifier).refresh();
    }
  }

  Future<void> _editVoucher([Map<String, dynamic>? v]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _VoucherForm(voucher: v));
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final promos = _promos;
    final vouchers = _vouchers;
    final menu = ref.watch(menuProvider).value?.menu;
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.surfaceApp,
        appBar: AppBar(
          title: const Text('Promo & voucher'),
          bottom: const TabBar(tabs: [Tab(text: 'Promo otomatis'), Tab(text: 'Voucher')]),
        ),
        body: _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : promos == null || vouchers == null
                ? const AppLoading()
                : TabBarView(children: [
                    ListView(padding: EdgeInsets.fromLTRB(pad, pad, pad, 96), children: [
                      Text('Berlaku otomatis di kasir sesuai jadwal (mis. happy hour). Per item dipakai potongan terbesar '
                          'antara promo dan diskon tingkat member; item yang sudah didiskon manual tidak ikut.',
                          style: AppType.body.copyWith(color: AppColors.inkMuted)),
                      const SizedBox(height: AppSpace.s3),
                      if (promos.isEmpty) const AppEmptyState(icon: Icons.local_offer_rounded, title: 'Belum ada promo'),
                      for (final p in promos)
                        Card(
                          child: ListTile(
                            onTap: () => _editPromo(p),
                            title: Text(p.name, style: AppType.bodyStrong),
                            subtitle: Text(
                              [p.effect, _target(p, menu), p.schedule, if (!p.active) 'nonaktif'].join(' · '),
                              style: AppType.caption.copyWith(color: AppColors.inkMuted),
                            ),
                            trailing: p.active && p.runsAt(DateTime.now()) ? const AppBadge('Berjalan', tone: AppTone.success) : null,
                          ),
                        ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(onPressed: () => _editPromo(), child: const Text('Tambah promo'), ),
                      ),
                    ]),
                    ListView(padding: EdgeInsets.fromLTRB(pad, pad, pad, 96), children: [
                      Text('Kasir memasukkan kode di keranjang (Pakai voucher). Tidak bisa digabung dengan diskon order atau hadiah potongan.',
                          style: AppType.body.copyWith(color: AppColors.inkMuted)),
                      const SizedBox(height: AppSpace.s3),
                      if (vouchers.isEmpty) const AppEmptyState(icon: Icons.confirmation_number_rounded, title: 'Belum ada voucher'),
                      for (final v in vouchers)
                        Card(
                          child: ListTile(
                            onTap: () => _editVoucher(v),
                            title: Text(v['code'] as String, style: AppType.bodyStrong.copyWith(letterSpacing: 1)),
                            subtitle: Text(
                              [
                                VoucherTerms.fromJson(v).effect,
                                if ((v['min_spend'] as int? ?? 0) > 0) 'min. ${rp(v['min_spend'] as int)}',
                                'terpakai ${v['used']}${v['usage_limit'] == null ? '' : '/${v['usage_limit']}'}',
                                if (v['ends_on'] != null) 's/d ${v['ends_on']}',
                                if (v['active'] != true) 'nonaktif',
                              ].join(' · '),
                              style: AppType.caption.copyWith(color: AppColors.inkMuted),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(onPressed: () => _editVoucher(), child: const Text('Tambah voucher'), ),
                      ),
                    ]),
                  ]),
      ),
    );
  }

  static String _target(Promotion p, Menu? menu) => switch (p.scope) {
        'categories' => p.targetIds.map((id) => menu?.category(id)?.name ?? '?').join(', '),
        'products' => p.targetIds.length == 1 ? (menu?.product(p.targetIds.first)?.name ?? '1 produk') : '${p.targetIds.length} produk',
        _ => 'semua produk',
      };
}

Future<void> _save(BuildContext context, WidgetRef ref, String method, String path, Map<String, dynamic> data, void Function(String?) onError) async {
  try {
    await ref.read(sessionProvider.notifier).authed((api, token) =>
        method == 'post' ? api.post(path, token: token, data: data) : api.put(path, token: token, data: data));
    if (context.mounted) Navigator.pop(context, true);
  } on ApiException catch (e) {
    onError(e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message);
  }
}

class _PromoForm extends ConsumerStatefulWidget {
  const _PromoForm({required this.menu, this.promo});

  final Menu menu;
  final Promotion? promo;

  @override
  ConsumerState<_PromoForm> createState() => _PromoFormState();
}

class _PromoFormState extends ConsumerState<_PromoForm> {
  late final _name = TextEditingController(text: widget.promo?.name ?? '');
  late String _type = widget.promo?.type ?? 'percent';
  late final _value = TextEditingController(
      text: widget.promo == null
          ? ''
          : widget.promo!.type == 'percent'
              ? percentBp(widget.promo!.value).replaceAll('%', '')
              : widget.promo!.type == 'amount' ? rupiah(widget.promo!.value) : '');
  late int _buy = widget.promo?.buyQty == 0 || widget.promo == null ? 2 : widget.promo!.buyQty;
  late int _free = widget.promo?.freeQty == 0 || widget.promo == null ? 1 : widget.promo!.freeQty;
  late String _scope = widget.promo?.scope ?? 'all';
  late final Set<String> _targets = {...?widget.promo?.targetIds};
  late final Set<int> _days = {...?widget.promo?.days};
  late bool _timed = widget.promo?.startTime != null;
  late TimeOfDay _start = _parse(widget.promo?.startTime) ?? const TimeOfDay(hour: 14, minute: 0);
  late TimeOfDay _end = _parse(widget.promo?.endTime) ?? const TimeOfDay(hour: 17, minute: 0);
  late bool _active = widget.promo?.active ?? true;
  String? _error;
  bool _busy = false;

  static TimeOfDay? _parse(String? hm) =>
      hm == null ? null : TimeOfDay(hour: int.parse(hm.substring(0, 2)), minute: int.parse(hm.substring(3, 5)));
  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final percent = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    final amount = parseRupiah(_value.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    await _save(
      context,
      ref,
      widget.promo == null ? 'post' : 'put',
      widget.promo == null ? '/promotions' : '/promotions/${widget.promo!.id}',
      {
        'name': _name.text.trim(),
        'type': _type,
        if (_type == 'percent') 'value': ((percent ?? 0) * 100).round(),
        if (_type == 'amount') 'value': amount ?? 0,
        if (_type == 'bogo') ...{'buy_qty': _buy, 'free_qty': _free},
        'scope': _scope,
        'target_ids': _scope == 'all' ? null : _targets.toList(),
        'days': _days.isEmpty ? null : (_days.toList()..sort()),
        'start_time': _timed ? _fmt(_start) : null,
        'end_time': _timed ? _fmt(_end) : null,
        'active': _active,
      },
      (e) => setState(() => _error = e),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.menu.activeCategories;
    final products = [...widget.menu.products.where((p) => p.active)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    const dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return AlertDialog(
      scrollable: true,
      title: Text(widget.promo == null ? 'Tambah promo' : 'Ubah promo'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama promo (tampil di keranjang & struk)', hintText: 'mis. Happy Hour', counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'percent', label: Text('Diskon %')),
              ButtonSegment(value: 'amount', label: Text('Rp/item')),
              ButtonSegment(value: 'bogo', label: Text('Beli X gratis Y')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() {
              _type = v.first;
              _value.clear();
            }),
          ),
          const SizedBox(height: AppSpace.s3),
          if (_type == 'bogo')
            // Wrap: di HP sempit pasangan "gratis [−1+]" turun ke baris berikutnya.
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.s5, runSpacing: AppSpace.s2, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Beli'),
                const SizedBox(width: AppSpace.s3),
                NumberStepper(value: _buy, onChanged: (v) => setState(() => _buy = v)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('gratis'),
                const SizedBox(width: AppSpace.s3),
                NumberStepper(value: _free, onChanged: (v) => setState(() => _free = v)),
              ]),
            ])
          else
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: _type == 'percent' ? 'Diskon' : 'Potongan per item',
                suffixText: _type == 'percent' ? '%' : null,
                prefixText: _type == 'amount' ? 'Rp ' : null,
              ),
            ),
          if (_type == 'bogo')
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s1),
              child: Text('Item gratis dihitung dari harga dasar produk yang sama (tambahan tetap dibayar).',
                  style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ),
          const SizedBox(height: AppSpace.s4),
          Text('Berlaku untuk', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s1),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'all', label: Text('Semua')),
              ButtonSegment(value: 'categories', label: Text('Kategori')),
              ButtonSegment(value: 'products', label: Text('Produk')),
            ],
            selected: {_scope},
            onSelectionChanged: (v) => setState(() {
              _scope = v.first;
              _targets.clear();
            }),
          ),
          if (_scope != 'all') ...[
            const SizedBox(height: AppSpace.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
                  for (final (id, name) in _scope == 'categories'
                      ? [for (final c in categories) (c.id, c.name)]
                      : [for (final p in products) (p.id, p.name)])
                    FilterChip(
                      label: Text(name),
                      selected: _targets.contains(id),
                      onSelected: (v) => setState(() => v ? _targets.add(id) : _targets.remove(id)),
                    ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.s4),
          Text('Hari (kosong = setiap hari)', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s1),
          Wrap(spacing: AppSpace.s1, runSpacing: AppSpace.s1, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                showCheckmark: false,
                label: Text(dayNames[d - 1]),
                selected: _days.contains(d),
                onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
              ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _timed,
            onChanged: (v) => setState(() => _timed = v),
            title: const Text('Hanya jam tertentu'),
            subtitle: _timed ? Text('${_fmt(_start)} – ${_fmt(_end)}') : const Text('Sepanjang hari'),
          ),
          if (_timed)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _start);
                    if (t != null) setState(() => _start = t);
                  },
                  child: Text('Mulai ${_fmt(_start)}'),
                ),
              ),
              const SizedBox(width: AppSpace.s2),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _end);
                    if (t != null) setState(() => _end = t);
                  },
                  child: Text('Selesai ${_fmt(_end)}'),
                ),
              ),
            ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Aktif'),
          ),
          if (_error != null) Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan')),
      ],
    );
  }
}

class _VoucherForm extends ConsumerStatefulWidget {
  const _VoucherForm({this.voucher});

  final Map<String, dynamic>? voucher;

  @override
  ConsumerState<_VoucherForm> createState() => _VoucherFormState();
}

class _VoucherFormState extends ConsumerState<_VoucherForm> {
  late final Map<String, dynamic>? v = widget.voucher;
  late final _code = TextEditingController(text: v?['code'] as String? ?? '');
  late String _type = v?['type'] as String? ?? 'percent';
  late final _value = TextEditingController(
      text: v == null ? '' : (_type == 'percent' ? percentBp(v!['value'] as int).replaceAll('%', '') : rupiah(v!['value'] as int)));
  late final _max = TextEditingController(text: v?['max_discount'] == null ? '' : rupiah(v!['max_discount'] as int));
  late final _min = TextEditingController(text: (v?['min_spend'] as int? ?? 0) == 0 ? '' : rupiah(v!['min_spend'] as int));
  late final _limit = TextEditingController(text: v?['usage_limit']?.toString() ?? '');
  late String? _endsOn = v?['ends_on'] as String?;
  late bool _active = v?['active'] as bool? ?? true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_code, _value, _max, _min, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final percent = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    await _save(
      context,
      ref,
      v == null ? 'post' : 'put',
      v == null ? '/vouchers' : '/vouchers/${v!['id']}',
      {
        'code': _code.text.trim(),
        'type': _type,
        'value': _type == 'percent' ? ((percent ?? 0) * 100).round() : (parseRupiah(_value.text) ?? 0),
        if (_type == 'percent') 'max_discount': parseRupiah(_max.text),
        'min_spend': parseRupiah(_min.text) ?? 0,
        'usage_limit': int.tryParse(_limit.text.trim()),
        'ends_on': _endsOn,
        'active': _active,
      },
      (e) => setState(() => _error = e),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return AlertDialog(
      scrollable: true,
      title: Text(v == null ? 'Tambah voucher' : 'Ubah voucher'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Kode', hintText: 'mis. HEMAT10', counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'percent', label: Text('Diskon %')), ButtonSegment(value: 'amount', label: Text('Potongan Rp'))],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _value.clear();
            }),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: _type == 'percent' ? 'Diskon' : 'Potongan',
              suffixText: _type == 'percent' ? '%' : null,
              prefixText: _type == 'amount' ? 'Rp ' : null,
            ),
          ),
          if (_type == 'percent') ...[
            const SizedBox(height: AppSpace.s3),
            TextField(controller: _max, keyboardType: TextInputType.number, inputFormatters: money,
                decoration: const InputDecoration(labelText: 'Potongan maksimal (opsional)', prefixText: 'Rp ')),
          ],
          const SizedBox(height: AppSpace.s3),
          TextField(controller: _min, keyboardType: TextInputType.number, inputFormatters: money,
              decoration: const InputDecoration(labelText: 'Minimal belanja (opsional)', prefixText: 'Rp ')),
          const SizedBox(height: AppSpace.s3),
          TextField(controller: _limit, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Kuota pemakaian (kosong = tanpa batas)')),
          const SizedBox(height: AppSpace.s2),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Berlaku sampai'),
            subtitle: Text(_endsOn ?? 'Tanpa batas waktu'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_endsOn != null)
                IconButton(tooltip: 'Hapus tanggal', onPressed: () => setState(() => _endsOn = null), icon: const Icon(Icons.close_rounded)),
              IconButton(
                tooltip: 'Pilih tanggal',
                icon: const Icon(Icons.event_rounded),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(context: context, firstDate: now, lastDate: DateTime(now.year + 3), initialDate: now);
                  if (d != null) {
                    setState(() => _endsOn = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
                  }
                },
              ),
            ]),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (x) => setState(() => _active = x), title: const Text('Aktif')),
          if (_error != null) Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan')),
      ],
    );
  }
}
