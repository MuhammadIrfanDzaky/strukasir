import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/shop_clock.dart';
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
                            trailing: p.active && menu != null && p.runsAt(ShopClock.wall(menu.utcOffset)) ? const AppBadge('Berjalan', tone: AppTone.success) : null,
                          ),
                        ),
                      const SizedBox(height: AppSpace.s3),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(onPressed: () => _editPromo(), child: const Text('Tambah promo'), ),
                      ),
                    ]),
                    ListView(padding: EdgeInsets.fromLTRB(pad, pad, pad, 96), children: [
                      Text('Kasir memasukkan kode di keranjang (tombol Voucher). Tidak bisa digabung dengan diskon order atau hadiah potongan.',
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
  late final Promotion? _p = widget.promo;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late String _type = _p?.type ?? 'percent';
  late final _value = TextEditingController(text: _initialValue(_p));
  late int _buy = _p == null || _p.buyQty == 0 ? (_type == 'min_qty' ? 3 : 2) : _p.buyQty;
  late int _free = _p == null || _p.freeQty == 0 ? 1 : _p.freeQty;
  late String _scope = _p?.scope ?? 'all';
  late final Set<String> _targets = {...?_p?.targetIds};
  late final List<({String? productId, int qty})> _bundle = _p?.bundleItems.isNotEmpty == true
      ? [for (final b in _p!.bundleItems) (productId: b.productId, qty: b.qty)]
      : [(productId: null, qty: 1), (productId: null, qty: 1)];
  late final Set<int> _days = {...?_p?.days};
  late bool _timed = _p?.times?.isNotEmpty == true;
  late final List<(TimeOfDay, TimeOfDay)> _windows = _p?.times?.isNotEmpty == true
      ? [for (final w in _p!.times!) (_parse(w.start), _parse(w.end))]
      : [(const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 17, minute: 0))];
  late bool _active = _p?.active ?? true;
  String? _error;
  bool _busy = false;

  static const _maxWindows = 4;

  static String _initialValue(Promotion? p) => switch (p?.type) {
        null || 'bogo' => '',
        'percent' || 'min_qty' => percentBp(p!.value).replaceAll('%', ''),
        _ => rupiah(p!.value),
      };

  static TimeOfDay _parse(String hm) => TimeOfDay(hour: int.parse(hm.substring(0, 2)), minute: int.parse(hm.substring(3, 5)));
  static String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _percentType => _type == 'percent' || _type == 'min_qty';

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  /// Harga normal isi paket (harga dasar × qty).
  int get _bundleNormal => _bundle.fold(0, (s, b) => s + (b.productId == null ? 0 : (widget.menu.product(b.productId!)?.price ?? 0) * b.qty));

  Future<void> _submit() async {
    final percent = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    final amount = parseRupiah(_value.text);
    final bundle = [for (final b in _bundle) if (b.productId != null) {'product_id': b.productId, 'qty': b.qty}];
    setState(() {
      _busy = true;
      _error = null;
    });
    await _save(
      context,
      ref,
      _p == null ? 'post' : 'put',
      _p == null ? '/promotions' : '/promotions/${_p.id}',
      {
        'name': _name.text.trim(),
        'type': _type,
        if (_percentType) 'value': ((percent ?? 0) * 100).round(),
        if (_type == 'amount' || _type == 'price' || _type == 'bundle') 'value': amount,
        if (_type == 'bogo') ...{'buy_qty': _buy, 'free_qty': _free},
        if (_type == 'min_qty') 'buy_qty': _buy,
        if (_type == 'bundle') 'bundle_items': bundle,
        'scope': _type == 'bundle' ? 'all' : _scope,
        'target_ids': _type == 'bundle' || _scope == 'all' ? null : _targets.toList(),
        'days': _days.isEmpty ? null : (_days.toList()..sort()),
        'times': _timed ? [for (final (s, e) in _windows) {'start': _fmt(s), 'end': _fmt(e)}] : null,
        'active': _active,
      },
      (e) => setState(() => _error = e),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickTime(int i, bool start) async {
    final (s, e) = _windows[i];
    final t = await showTimePicker(context: context, initialTime: start ? s : e);
    if (t != null) setState(() => _windows[i] = start ? (t, e) : (s, t));
  }

  Widget _caption(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.s1),
        child: Text(text, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
      );

  Widget _labeled(String label, Widget child) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label),
        const SizedBox(width: AppSpace.s3),
        child,
      ]);

  /// Isian sesuai tipe promo.
  List<Widget> _typeFields(List<MenuProduct> products) {
    TextField money(String label, {String? helper}) => TextField(
          controller: _value,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: _type == 'bundle' ? (_) => setState(() {}) : null,
          decoration: InputDecoration(labelText: label, prefixText: 'Rp ', helperText: helper, helperMaxLines: 2),
        );
    TextField percentField() => TextField(
          controller: _value,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'Diskon', suffixText: '%'),
        );
    switch (_type) {
      case 'percent':
        return [percentField()];
      case 'amount':
        return [money('Potongan per item')];
      case 'price':
        return [money('Harga jual per item selama promo', helper: 'Tambahan (topping, ukuran) tetap dibayar.')];
      case 'min_qty':
        return [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.s5, runSpacing: AppSpace.s2, children: [
            _labeled('Minimal beli', NumberStepper(value: _buy, min: 2, onChanged: (v) => setState(() => _buy = v))),
            SizedBox(width: 160, child: percentField()),
          ]),
          _caption('Diskon berlaku untuk item yang dibeli sebanyak minimal jumlah ini dalam satu baris.'),
        ];
      case 'bogo':
        return [
          // Wrap: di HP sempit pasangan "gratis [−1+]" turun ke baris berikutnya.
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.s5, runSpacing: AppSpace.s2, children: [
            _labeled('Beli', NumberStepper(value: _buy, onChanged: (v) => setState(() => _buy = v))),
            _labeled('gratis', NumberStepper(value: _free, onChanged: (v) => setState(() => _free = v))),
          ]),
          _caption('Item gratis dihitung dari harga dasar produk yang sama (tambahan tetap dibayar).'),
        ];
      default: // bundle
        final normal = _bundleNormal;
        final price = parseRupiah(_value.text) ?? 0;
        return [
          Text('Isi paket', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s1),
          for (final (i, b) in _bundle.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s2),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('$i-${b.productId}'),
                    initialValue: products.any((p) => p.id == b.productId) ? b.productId : null,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    decoration: const InputDecoration(labelText: 'Produk', isDense: true),
                    items: [
                      for (final p in products)
                        DropdownMenuItem(value: p.id, child: Text('${p.name} · ${rp(p.price)}', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _bundle[i] = (productId: v, qty: b.qty)),
                  ),
                ),
                const SizedBox(width: AppSpace.s2),
                NumberStepper(value: b.qty, onChanged: (v) => setState(() => _bundle[i] = (productId: b.productId, qty: v))),
                IconButton(
                  tooltip: 'Hapus',
                  onPressed: _bundle.length > 1 ? () => setState(() => _bundle.removeAt(i)) : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
          if (_bundle.length < 10)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _bundle.add((productId: null, qty: 1))),
                child: const Text('+ Tambah isi paket'),
              ),
            ),
          const SizedBox(height: AppSpace.s2),
          money('Harga paket',
              helper: normal == 0
                  ? 'Tambahan (topping, ukuran) tetap dibayar.'
                  : 'Harga normal ${rp(normal)}${price > 0 && price < normal ? ' · pelanggan hemat ${rp(normal - price)}' : ''}'),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.menu.activeCategories;
    final products = [...widget.menu.products.where((p) => p.active)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    const dayNames = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return AlertDialog(
      scrollable: true,
      title: Text(_p == null ? 'Tambah promo' : 'Ubah promo'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nama promo (tampil di keranjang & struk)', hintText: 'mis. Happy Hour', counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Jenis promo'),
            items: [for (final e in promotionTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() {
              if (v == null || v == _type) return;
              _type = v;
              _value.clear();
              if (_type == 'min_qty' && _buy < 2) _buy = 3;
            }),
          ),
          const SizedBox(height: AppSpace.s3),
          ..._typeFields(products),
          if (_type != 'bundle') ...[
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
            subtitle: Text(_timed ? [for (final (s, e) in _windows) '${_fmt(s)}–${_fmt(e)}'].join(', ') : 'Sepanjang hari'),
          ),
          if (_timed) ...[
            for (final (i, (s, e)) in _windows.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => _pickTime(i, true), child: Text('Mulai ${_fmt(s)}'))),
                  const SizedBox(width: AppSpace.s2),
                  Expanded(child: OutlinedButton(onPressed: () => _pickTime(i, false), child: Text('Selesai ${_fmt(e)}'))),
                  IconButton(
                    tooltip: 'Hapus rentang',
                    onPressed: _windows.length > 1 ? () => setState(() => _windows.removeAt(i)) : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),
            if (_windows.length < _maxWindows)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _windows.add((const TimeOfDay(hour: 19, minute: 0), const TimeOfDay(hour: 21, minute: 0)))),
                  child: const Text('+ Tambah rentang jam'),
                ),
              ),
            _caption('Promo mengikuti jam order dibuat: open bill yang dibuat di jam promo tetap dapat promo walau dibayar setelahnya.'),
          ],
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
