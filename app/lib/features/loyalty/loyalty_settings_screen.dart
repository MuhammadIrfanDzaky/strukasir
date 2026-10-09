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
import 'loyalty_models.dart';

/// Hadiah yang sedang disunting (id null = baru).
class _RewardDraft {
  _RewardDraft({this.id, required this.name, required this.cost, required this.type, this.productId, this.value = 0});

  factory _RewardDraft.of(LoyaltyReward r) =>
      _RewardDraft(id: r.id, name: r.name, cost: r.cost, type: r.type, productId: r.productId, value: r.value);

  final String? id;
  String name;
  int cost;
  String type;
  String? productId;

  /// Rp (amount) atau basis poin (percent).
  int value;

  LoyaltyReward get asReward =>
      LoyaltyReward(id: id ?? '', name: name, cost: cost, type: type, productId: productId, value: value);

  Map<String, dynamic> toJson() => {
        'id': ?id,
        'name': name.trim(),
        'cost': cost,
        'type': type,
        if (type == 'free_product') 'product_id': productId,
        if (type != 'free_product') 'value': value,
      };
}

const _modes = [
  ('per_item', 'Stempel per item', 'Tiap item yang dibeli = 1 stempel. Cocok untuk kartu "beli 10 gratis 1".'),
  ('per_order', 'Stempel per transaksi', 'Tiap transaksi = 1 stempel, boleh dengan minimal belanja.'),
  ('per_amount', 'Poin per belanja', 'Tiap kelipatan belanja = 1 poin. Cocok untuk belanja bernilai beragam.'),
];

const _expiryOptions = [null, 3, 6, 12, 24];

/// Pengaturan → Program loyalitas (owner): dirakit dari blok — cara dapat, masa berlaku, hadiah.
class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  ConsumerState<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends ConsumerState<LoyaltySettingsScreen> {
  bool _loaded = false;
  String? _loadError;
  String? _error;
  Map<String, String> _fieldErrors = {};
  bool _busy = false;

  bool _active = true;
  final _name = TextEditingController(text: 'Kartu Member');
  String _mode = 'per_item';
  final _perAmount = TextEditingController(text: '10.000');
  final _minOrder = TextEditingController();
  final Set<String> _categories = {};
  int? _expiry;
  final List<_RewardDraft> _rewards = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _perAmount.dispose();
    _minOrder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/settings/loyalty', token: token));
      _apply(res['data'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _loadError = e.message);
    }
  }

  void _apply(Map<String, dynamic> data) {
    final p = data['program'] == null ? null : LoyaltyProgram.fromJson(data['program'] as Map<String, dynamic>, rewards: const []);
    final rewards = (data['rewards'] as List).cast<Map<String, dynamic>>().map(LoyaltyReward.fromJson);
    setState(() {
      _loaded = true;
      if (p != null) {
        _active = p.active;
        _name.text = p.name;
        _mode = p.earnMode;
        if (p.earnPerAmount != null) _perAmount.text = rupiah(p.earnPerAmount!);
        _minOrder.text = (p.earnMinOrder ?? 0) > 0 ? rupiah(p.earnMinOrder!) : '';
        _categories
          ..clear()
          ..addAll(p.categoryIds);
        _expiry = p.expiryMonths;
      } else {
        _active = false; // belum pernah diatur: owner menyalakan setelah hadiah siap
      }
      _rewards
        ..clear()
        ..addAll(rewards.map(_RewardDraft.of));
    });
  }

  String get _unit => _mode == 'per_amount' ? 'poin' : 'stempel';

  Future<void> _editReward([int? index]) async {
    final menu = ref.read(menuProvider).value?.menu;
    if (menu == null) return;
    final draft = await showDialog<_RewardDraft>(
      context: context,
      builder: (_) => _RewardForm(menu: menu, unit: _unit, draft: index == null ? null : _rewards[index]),
    );
    if (draft == null) return;
    setState(() {
      if (index == null) {
        _rewards.add(draft);
      } else {
        _rewards[index] = draft;
      }
      _fieldErrors.remove('rewards');
    });
  }

  Future<void> _save() async {
    final perAmount = parseRupiah(_perAmount.text);
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Isi nama program',
      if (_mode == 'per_amount' && (perAmount == null || perAmount < 100)) 'earn_per_amount': 'Minimal Rp 100',
      if (_active && _rewards.isEmpty) 'rewards': 'Tambahkan minimal satu hadiah sebelum program dinyalakan.',
    };
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors = errors);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = {};
    });
    try {
      final res = await ref.read(sessionProvider.notifier).authed((api, token) => api.put('/settings/loyalty', token: token, data: {
            'active': _active,
            'name': _name.text.trim(),
            'earn_mode': _mode,
            if (_mode == 'per_amount') 'earn_per_amount': perAmount,
            if (_mode == 'per_order') 'earn_min_order': parseRupiah(_minOrder.text) ?? 0,
            if (_mode == 'per_item') 'category_ids': _categories.toList(),
            'expiry_months': _expiry,
            'rewards': _rewards.map((r) => r.toJson()).toList(),
          }));
      _apply(res['data'] as Map<String, dynamic>);
      await ref.read(menuProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Program loyalitas disimpan. Semua tablet ikut berubah.')));
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = {for (final f in e.fieldErrors.keys) f: e.field(f)!};
        _error = e.fieldErrors.isEmpty ? e.message : 'Periksa kembali isian yang ditandai.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(menuProvider).value?.menu;
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Program loyalitas')),
      body: !_loaded
          ? (_loadError == null ? const AppLoading() : AppErrorState(message: _loadError!, onRetry: _load))
          : ListView(
              padding: EdgeInsets.all(context.isCompact ? AppSpace.s3 : AppSpace.s5),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: SwitchListTile(
                            value: _active,
                            onChanged: _busy ? null : (v) => setState(() => _active = v),
                            secondary: Icon(Icons.loyalty_rounded, color: _active ? AppColors.primary : AppColors.inkMuted),
                            title: const Text('Program berjalan', style: AppType.bodyStrong),
                            subtitle: Text(
                              _active ? 'Member dapat $_unit dari belanja & bisa tukar hadiah' : 'Mati: tidak ada $_unit baru, hadiah tidak bisa ditukar',
                              style: AppType.caption.copyWith(color: AppColors.inkMuted),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.s3),
                        AppSectionCard(title: 'Nama & cara dapat', children: [
                          TextField(
                            controller: _name,
                            maxLength: 40,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Nama program (tercetak di struk)',
                              hintText: 'mis. BerryCard',
                              errorText: _fieldErrors['name'],
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: AppSpace.s3),
                          RadioGroup<String>(
                            groupValue: _mode,
                            onChanged: (v) => setState(() => _mode = v ?? _mode),
                            child: Column(children: [
                              for (final (key, label, help) in _modes)
                                RadioListTile<String>(
                                  value: key,
                                  enabled: !_busy,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(label, style: AppType.bodyStrong),
                                  subtitle: Text(help, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                                ),
                            ]),
                          ),
                          ..._modeFields(menu),
                        ]),
                        const SizedBox(height: AppSpace.s3),
                        AppSectionCard(title: 'Masa berlaku', children: [
                          DropdownButtonFormField<int?>(
                            initialValue: _expiry,
                            isExpanded: true,
                            decoration: const InputDecoration(isDense: true),
                            items: [
                              for (final m in _expiryOptions)
                                DropdownMenuItem(
                                  value: m,
                                  child: Text(m == null ? 'Tidak pernah hangus' : 'Hangus bila tidak belanja $m bulan'),
                                ),
                            ],
                            onChanged: _busy ? null : (v) => setState(() => _expiry = v),
                          ),
                        ]),
                        const SizedBox(height: AppSpace.s3),
                        AppSectionCard(
                          title: 'Hadiah',
                          trailing: TextButton.icon(
                            onPressed: _busy || _rewards.length >= 20 ? null : () => _editReward(),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Tambah'),
                          ),
                          empty: 'Belum ada hadiah. Tambahkan mis. "10 stempel = gratis 1 kopi".',
                          children: [
                            for (final (i, r) in _rewards.indexed)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(r.type == 'free_product' ? Icons.local_cafe_rounded : Icons.sell_rounded,
                                    color: AppColors.primary),
                                title: Text(r.name, style: AppType.bodyStrong),
                                subtitle: Text(
                                  [
                                    '${r.cost} $_unit',
                                    r.asReward.effect(r.productId == null ? null : menu?.product(r.productId!)?.name),
                                  ].where((t) => t != r.name).join(' · '),
                                  style: AppType.caption.copyWith(color: AppColors.inkMuted),
                                ),
                                onTap: _busy ? null : () => _editReward(i),
                                trailing: IconButton(
                                  tooltip: 'Hapus hadiah',
                                  onPressed: _busy ? null : () => setState(() => _rewards.removeAt(i)),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                ),
                              ),
                          ],
                        ),
                        if (_fieldErrors['rewards'] != null) ...[
                          const SizedBox(height: AppSpace.s2),
                          Text(_fieldErrors['rewards']!, style: AppType.body.copyWith(color: AppColors.danger)),
                        ],
                        const SizedBox(height: AppSpace.s3),
                        _Summary(text: _summary(menu)),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpace.s3),
                          Text(_error!, style: AppType.body.copyWith(color: AppColors.danger)),
                        ],
                        const SizedBox(height: AppSpace.s5),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
                          child: _busy
                              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : const Text('Simpan'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _modeFields(Menu? menu) {
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    switch (_mode) {
      case 'per_amount':
        return [
          TextField(
            controller: _perAmount,
            keyboardType: TextInputType.number,
            inputFormatters: money,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '1 poin tiap belanja',
              prefixText: 'Rp ',
              errorText: _fieldErrors['earn_per_amount'],
            ),
          ),
        ];
      case 'per_order':
        return [
          TextField(
            controller: _minOrder,
            keyboardType: TextInputType.number,
            inputFormatters: money,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Minimal belanja per transaksi',
              prefixText: 'Rp ',
              helperText: 'Kosongkan bila semua transaksi dapat stempel',
              errorText: _fieldErrors['earn_min_order'],
            ),
          ),
        ];
      default:
        final categories = menu?.activeCategories ?? const <MenuCategory>[];
        return [
          const SizedBox(height: AppSpace.s1),
          Text('Kategori yang dapat stempel (kosongkan = semua produk):', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s2),
          Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
            for (final c in categories)
              FilterChip(
                label: Text(c.name),
                selected: _categories.contains(c.id),
                onSelected: _busy
                    ? null
                    : (v) => setState(() => v ? _categories.add(c.id) : _categories.remove(c.id)),
              ),
          ]),
        ];
    }
  }

  /// Ringkasan aturan dalam satu kalimat, seperti yang akan dijelaskan kasir ke pelanggan.
  String _summary(Menu? menu) {
    final program = LoyaltyProgram(
      active: _active,
      name: _name.text.trim().isEmpty ? 'Program' : _name.text.trim(),
      earnMode: _mode,
      earnPerAmount: parseRupiah(_perAmount.text),
      earnMinOrder: parseRupiah(_minOrder.text),
      categoryIds: _categories.toList(),
    );
    final rule = program.earnRule(
      categoryNames: (ids) => '(${ids.map((id) => menu?.category(id)?.name ?? '?').join(', ')})',
    );
    final rewards = _rewards
        .map((r) {
          final effect = r.asReward.effect(r.productId == null ? null : menu?.product(r.productId!)?.name);
          return '${r.cost} $_unit = ${effect[0].toLowerCase()}${effect.substring(1)}';
        })
        .join('; ');
    final expiry = _expiry == null ? '' : ' Saldo hangus bila tidak belanja $_expiry bulan.';
    return '${program.name}: $rule.${rewards.isEmpty ? '' : ' $rewards.'}$expiry';
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpace.s3),
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primaryStrong),
          const SizedBox(width: AppSpace.s2),
          Expanded(child: Text(text, style: AppType.body.copyWith(color: AppColors.primaryStrong))),
        ]),
      );
}

/// Form satu hadiah: nama, harga stempel/poin, jenis (gratis produk / potongan Rp / potongan %).
class _RewardForm extends StatefulWidget {
  const _RewardForm({required this.menu, required this.unit, this.draft});

  final Menu menu;
  final String unit;
  final _RewardDraft? draft;

  @override
  State<_RewardForm> createState() => _RewardFormState();
}

class _RewardFormState extends State<_RewardForm> {
  late final _name = TextEditingController(text: widget.draft?.name ?? '');
  late final _cost = TextEditingController(text: widget.draft == null ? '10' : '${widget.draft!.cost}');
  late String _type = widget.draft?.type ?? 'free_product';
  late String? _productId = widget.draft?.productId;
  late final _value = TextEditingController(
    text: switch (widget.draft) {
      _RewardDraft(type: 'amount', :final value) => rupiah(value),
      _RewardDraft(type: 'percent', :final value) => percentBp(value).replaceAll('%', ''),
      _ => '',
    },
  );
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final cost = int.tryParse(_cost.text.trim());
    final percent = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    final amount = parseRupiah(_value.text);
    final errors = <String, String>{
      if (cost == null || cost < 1) 'cost': 'Minimal 1',
      if (_type == 'free_product' && _productId == null) 'product': 'Pilih produk',
      if (_type == 'amount' && (amount == null || amount < 1)) 'value': 'Isi potongan',
      if (_type == 'percent' && (percent == null || percent <= 0 || percent > 100)) 'value': 'Isi 1–100',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final product = _productId == null ? null : widget.menu.product(_productId!);
    final value = _type == 'amount' ? amount! : (_type == 'percent' ? (percent! * 100).round() : 0);
    final draft = _RewardDraft(id: widget.draft?.id, name: '', cost: cost!, type: _type, productId: _type == 'free_product' ? _productId : null, value: value);
    draft.name = _name.text.trim().isNotEmpty ? _name.text.trim() : draft.asReward.effect(product?.name);
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    final products = [...widget.menu.products.where((p) => p.active)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return AlertDialog(
      scrollable: true,
      title: Text(widget.draft == null ? 'Tambah hadiah' : 'Ubah hadiah'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'free_product', label: Text('Gratis produk')),
                ButtonSegment(value: 'amount', label: Text('Potongan Rp')),
                ButtonSegment(value: 'percent', label: Text('Potongan %')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() {
                _type = v.first;
                _value.clear();
                _errors = {};
              }),
            ),
            const SizedBox(height: AppSpace.s3),
            if (_type == 'free_product')
              DropdownButtonFormField<String>(
                initialValue: products.any((p) => p.id == _productId) ? _productId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Produk yang digratiskan', errorText: _errors['product']),
                items: [for (final p in products) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _productId = v),
              )
            else
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: _type == 'amount' ? 'Besar potongan' : 'Persen potongan',
                  prefixText: _type == 'amount' ? 'Rp ' : null,
                  suffixText: _type == 'percent' ? '%' : null,
                  errorText: _errors['value'],
                ),
              ),
            const SizedBox(height: AppSpace.s3),
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Ditukar dengan', suffixText: widget.unit, errorText: _errors['cost']),
            ),
            const SizedBox(height: AppSpace.s3),
            TextField(
              controller: _name,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Nama hadiah (opsional)', hintText: 'Otomatis bila dikosongkan', counterText: ''),
            ),
            if (_type == 'free_product')
              Text('Gratis 1 porsi harga dasar; tambahan (mis. extra shot) tetap dibayar.',
                  style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }
}
