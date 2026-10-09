import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import '../outlets/outlets_screen.dart';
import '../session/session_controller.dart';
import 'inventory_models.dart';

Future<Map<String, dynamic>> _call(WidgetRef ref, String method, String path, [Map<String, dynamic>? data]) => ref
    .read(sessionProvider.notifier)
    .authed(
      (api, token) => switch (method) {
        'post' => api.post(path, token: token, data: data),
        'put' => api.put(path, token: token, data: data),
        _ => api.get(path, token: token),
      },
    );

String _firstError(ApiException e) => e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message;

/// Pengaturan → Stok & resep (owner, fitur `inventory`).
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  InventoryData? _data;
  String? _error;

  /// Multi-outlet: outlet yang sedang dikelola (null = outlet tablet ini).
  String? _outlet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await _call(ref, 'get', _outlet == null ? '/inventory' : '/inventory?outlet=$_outlet');
      if (mounted) setState(() => _data = InventoryData.fromJson(res['data'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Dialog yang mengubah stok/resep → muat ulang; HPP di menu owner ikut berubah.
  Future<void> _open(Widget dialog, {bool refreshMenu = false}) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => dialog);
    if (saved == true) {
      await _load();
      if (refreshMenu) ref.read(menuProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final menu = ref.watch(menuProvider).value?.menu;
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: AppColors.surfaceApp,
        appBar: AppBar(
          title: const Text('Stok & resep'),
          actions: [
            if (menu?.multiOutlet ?? false)
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.s3),
                child: OutletPicker(
                  maxWidth: context.isCompact ? 130 : 220,
                  value: _outlet ?? menu?.outlet?.id,
                  onChanged: (v) {
                    setState(() {
                      _outlet = v == menu?.outlet?.id ? null : v;
                      _data = null;
                    });
                    _load();
                  },
                ),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Bahan'),
              Tab(text: 'Resep'),
            ],
          ),
        ),
        body: _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : data == null || menu == null
            ? const AppLoading()
            : TabBarView(
                children: [
                  RefreshIndicator(onRefresh: _load, child: _ingredients(data, pad)),
                  RefreshIndicator(onRefresh: _load, child: _recipes(data, menu, pad)),
                ],
              ),
      ),
    );
  }

  Widget _ingredients(InventoryData data, double pad) {
    final active = data.ingredients.where((i) => i.active).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
      children: [
        Wrap(
          spacing: AppSpace.s3,
          runSpacing: AppSpace.s3,
          children: [AppStatCard('Nilai stok', rp(data.value), width: 170), AppStatCard('Stok menipis', '${data.lowCount} bahan', width: 170)],
        ),
        const SizedBox(height: AppSpace.s3),
        Wrap(
          spacing: AppSpace.s2,
          runSpacing: AppSpace.s2,
          children: [
            FilledButton.icon(
              onPressed: active.isEmpty ? null : () => _open(_StockDialog(kind: 'purchase', data: data, outletId: _outlet), refreshMenu: true),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Pembelian'),
            ),
            OutlinedButton.icon(
              onPressed: active.isEmpty ? null : () => _open(_StockDialog(kind: 'waste', data: data, outletId: _outlet)),
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('Terbuang'),
            ),
            OutlinedButton.icon(
              onPressed: active.isEmpty ? null : () => _open(_StockDialog(kind: 'count', data: data, outletId: _outlet)),
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Stok opname'),
            ),
            OutlinedButton.icon(onPressed: () => _open(const _IngredientForm()), icon: const Icon(Icons.add_rounded), label: const Text('Tambah bahan')),
          ],
        ),
        const SizedBox(height: AppSpace.s3),
        if (data.ingredients.isEmpty)
          const AppEmptyState(
            icon: Icons.inventory_2_rounded,
            title: 'Belum ada bahan',
            message:
                'Tambah bahan (mis. Biji kopi g, Susu ml, Cup pcs), catat pembelian, lalu isi resep tiap produk. '
                'Stok terpotong otomatis setiap order lunas.',
          ),
        for (final i in data.ingredients)
          Card(
            child: ListTile(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IngredientScreen(ingredient: i, outletId: _outlet)));
                _load();
              },
              leading: Icon(
                Icons.inventory_2_rounded,
                color: !i.active
                    ? AppColors.inkDisabled
                    : i.low
                    ? AppColors.danger
                    : AppColors.primary,
              ),
              title: Text(i.name, style: AppType.bodyStrong.copyWith(color: i.active ? null : AppColors.inkMuted)),
              subtitle: Text(
                [
                  i.costText,
                  if (i.minStock != null) 'min. ${qtyText(i.minStock!)} ${i.unit}',
                  if (i.usedIn == 0) 'belum dipakai resep',
                  if (!i.active) 'nonaktif',
                ].join(' · '),
                style: AppType.caption.copyWith(color: AppColors.inkMuted),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(i.stockText, style: AppType.bodyStrong.copyWith(color: i.negative ? AppColors.danger : null)),
                  if (i.low) AppBadge(i.negative ? 'Minus' : 'Menipis', tone: AppTone.danger),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _recipes(InventoryData data, Menu menu, double pad) {
    final products = [...menu.products.where((p) => p.active)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
      children: [
        Text(
          'Pemakaian bahan per 1 porsi. HPP dihitung dari resep × modal rata-rata dan dipakai di laporan laba.',
          style: AppType.body.copyWith(color: AppColors.inkMuted),
        ),
        if (data.ingredients.isEmpty) ...[
          const SizedBox(height: AppSpace.s3),
          Text('Tambah bahan dulu di tab Bahan.', style: AppType.bodyStrong.copyWith(color: AppColors.warning)),
        ],
        const SizedBox(height: AppSpace.s3),
        for (final p in products)
          Builder(
            builder: (context) {
              final lines = data.productRecipes[p.id] ?? const <RecipeLine>[];
              final cost = data.productCosts[p.id];
              final margin = cost == null || p.price == 0 ? null : (p.price - cost) * 100 / p.price;
              return Card(
                child: ListTile(
                  onTap: data.ingredients.isEmpty
                      ? null
                      : () =>
                            _open(_RecipeDialog(title: p.name, path: '/recipes/product/${p.id}', lines: lines, data: data, price: p.price), refreshMenu: true),
                  title: Text(p.name, style: AppType.bodyStrong),
                  subtitle: Text(
                    lines.isEmpty ? 'Belum ada resep' : data.summary(lines),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted.copyWith(color: lines.isEmpty ? AppColors.warning : null),
                  ),
                  trailing: cost == null
                      ? const Icon(Icons.chevron_right_rounded)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('HPP ${rp(cost)}', style: AppType.bodyStrong),
                            if (margin != null)
                              Text(
                                'margin ${margin.toStringAsFixed(0)}%',
                                style: muted.copyWith(color: margin < 0 ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                ),
              );
            },
          ),
        if (menu.modifierGroups.any((g) => g.activeModifiers.isNotEmpty)) ...[
          const SizedBox(height: AppSpace.s4),
          Text('Pilihan varian', style: AppType.title),
          const SizedBox(height: AppSpace.s1),
          Text(
            'Bahan tambahan per 1 pilihan (mis. Extra shot +18 g kopi). Varian pengganti: isi minus untuk bahan '
            'yang tidak dipakai (Oat milk: +150 ml oat, −150 ml susu).',
            style: muted,
          ),
          const SizedBox(height: AppSpace.s2),
          for (final g in menu.modifierGroups)
            for (final m in g.activeModifiers)
              Builder(
                builder: (context) {
                  final lines = data.modifierRecipes[m.id] ?? const <RecipeLine>[];
                  final cost = data.costOf(lines).round();
                  return Card(
                    child: ListTile(
                      dense: true,
                      onTap: data.ingredients.isEmpty
                          ? null
                          : () => _open(
                              _RecipeDialog(title: '${g.name} · ${m.name}', path: '/recipes/modifier/${m.id}', lines: lines, data: data, allowNegative: true),
                              refreshMenu: true,
                            ),
                      title: Text('${g.name} · ${m.name}', style: AppType.bodyStrong),
                      subtitle: Text(lines.isEmpty ? 'Tidak mengubah bahan' : data.summary(lines), style: muted),
                      trailing: lines.isEmpty ? null : Text('${cost < 0 ? '−' : '+'}${rp(cost.abs())}', style: AppType.bodyStrong),
                    ),
                  );
                },
              ),
        ],
      ],
    );
  }
}

/// Detail satu bahan: ubah data + riwayat stok.
class IngredientScreen extends ConsumerStatefulWidget {
  const IngredientScreen({super.key, required this.ingredient, this.outletId});

  final Ingredient ingredient;

  /// Outlet yang dilihat (null = outlet tablet ini).
  final String? outletId;

  @override
  ConsumerState<IngredientScreen> createState() => _IngredientScreenState();
}

class _IngredientScreenState extends ConsumerState<IngredientScreen> {
  late Ingredient _ingredient = widget.ingredient;
  List<Map<String, dynamic>>? _moves;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await _call(ref, 'get',
          '/ingredients/${_ingredient.id}/movements${widget.outletId == null ? '' : '?outlet=${widget.outletId}'}');
      final data = res['data'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _ingredient = Ingredient.fromJson({...data['ingredient'] as Map<String, dynamic>, 'used_in': _ingredient.usedIn});
          _moves = (data['movements'] as List).cast<Map<String, dynamic>>();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static const _icons = {
    'purchase': Icons.add_shopping_cart_rounded,
    'sale': Icons.point_of_sale_rounded,
    'void': Icons.undo_rounded,
    'waste': Icons.delete_sweep_rounded,
    'count': Icons.fact_check_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final i = _ingredient;
    final moves = _moves;
    final pad = context.isCompact ? AppSpace.s3 : AppSpace.s5;
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(
        title: Text(i.name),
        actions: [
          IconButton(
            tooltip: 'Ubah bahan',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final saved = await showDialog<bool>(
                context: context,
                builder: (_) => _IngredientForm(ingredient: i),
              );
              if (saved == true) _load();
            },
          ),
        ],
      ),
      body: _error != null
          ? AppErrorState(message: _error!, onRetry: _load)
          : moves == null
          ? const AppLoading()
          : ListView(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
              children: [
                Wrap(
                  spacing: AppSpace.s3,
                  runSpacing: AppSpace.s3,
                  children: [
                    AppStatCard('Stok', i.stockText, width: 160),
                    AppStatCard('Modal rata-rata', i.costText, width: 160),
                    AppStatCard('Nilai stok', rp(i.value), width: 160),
                  ],
                ),
                const SizedBox(height: AppSpace.s4),
                AppSectionCard(
                  title: 'Riwayat stok',
                  empty: 'Belum ada catatan stok.',
                  children: [
                    for (final m in moves)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(_icons[m['kind']] ?? Icons.swap_vert_rounded, color: AppColors.inkMuted),
                        title: Text(
                          '${m['kind_label']} ${(m['qty'] as num) > 0 ? '+' : ''}${qtyText((m['qty'] as num).toDouble())} ${i.unit}',
                          style: AppType.bodyStrong.copyWith(color: (m['qty'] as num) < 0 ? AppColors.danger : AppColors.success),
                        ),
                        subtitle: Text(
                          [
                            _when(m['created_at'] as String),
                            if (m['order_number'] != null) 'order ${m['order_number']}',
                            if (m['supplier'] != null) m['supplier'],
                            if (m['kind'] == 'purchase') '${costPerUnit((m['unit_cost'] as num).toDouble())}/${i.unit}',
                            if (m['note'] != null) m['note'],
                            if (m['user'] != null) m['user'],
                          ].join(' · '),
                          style: muted,
                        ),
                        trailing: Text('sisa ${qtyText((m['balance_after'] as num).toDouble())}', style: muted),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  static String _when(String iso) {
    final t = DateTime.parse(iso).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _IngredientForm extends ConsumerStatefulWidget {
  const _IngredientForm({this.ingredient});

  final Ingredient? ingredient;

  @override
  ConsumerState<_IngredientForm> createState() => _IngredientFormState();
}

class _IngredientFormState extends ConsumerState<_IngredientForm> {
  late final _name = TextEditingController(text: widget.ingredient?.name ?? '');
  late String _unit = widget.ingredient?.unit ?? 'g';
  late final _min = TextEditingController(text: widget.ingredient?.minStock == null ? '' : qtyText(widget.ingredient!.minStock!));
  late bool _active = widget.ingredient?.active ?? true;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final i = widget.ingredient;
    try {
      await _call(ref, i == null ? 'post' : 'put', i == null ? '/ingredients' : '/ingredients/${i.id}', {
        'name': _name.text.trim(),
        'unit': _unit,
        'min_stock': parseQty(_min.text),
        'active': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.ingredient == null ? 'Tambah bahan' : 'Ubah bahan'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nama bahan', hintText: 'mis. Susu UHT', counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          Text('Satuan dasar (pembelian boleh diisi kg / L)', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s1),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'g', label: Text('gram')),
              ButtonSegment(value: 'ml', label: Text('ml')),
              ButtonSegment(value: 'pcs', label: Text('pcs')),
            ],
            selected: {_unit},
            onSelectionChanged: (v) => setState(() => _unit = v.first),
          ),
          const SizedBox(height: AppSpace.s3),
          TextField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(labelText: 'Peringatan stok menipis di bawah (opsional)', suffixText: _unit),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Aktif')),
          if (_error != null) Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger)),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
      FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan')),
    ],
  );
}

/// Satu baris input bahan di dialog stok/resep.
class _Line {
  _Line({this.ingredientId, String qty = '', String cost = ''}) : qty = TextEditingController(text: qty), cost = TextEditingController(text: cost);

  String? ingredientId;
  final TextEditingController qty;
  final TextEditingController cost;

  /// Input pembelian dalam satuan besar (kg / L) → dikali 1000.
  bool big = false;

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

/// Pembelian (`purchase`), terbuang (`waste`), atau stok opname (`count`).
class _StockDialog extends ConsumerStatefulWidget {
  const _StockDialog({required this.kind, required this.data, this.outletId});

  final String kind;
  final InventoryData data;

  /// Outlet lain yang dipilih owner (null = outlet tablet ini).
  final String? outletId;

  @override
  ConsumerState<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends ConsumerState<_StockDialog> {
  final _id = const Uuid().v4(); // sekali per dialog: tombol ditekan ulang tidak dobel
  late final List<Ingredient> _active = widget.data.ingredients.where((i) => i.active).toList();
  late final List<_Line> _lines = widget.kind == 'count' ? [for (final i in _active) _Line(ingredientId: i.id)] : [_Line()];
  final _supplier = TextEditingController();
  final _note = TextEditingController();
  bool _fromCash = false;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _supplier.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    'purchase' => 'Pembelian stok',
    'waste' => 'Bahan terbuang / rusak',
    _ => 'Stok opname',
  };

  double? _qty(_Line l) {
    final q = parseQty(l.qty.text);
    return q == null ? null : (l.big ? q * 1000 : q);
  }

  int get _total => _lines.fold(0, (s, l) => s + (parseRupiah(l.cost.text) ?? 0));

  Future<void> _submit() async {
    final lines = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final q = _qty(l);
      if (widget.kind == 'count') {
        if (l.qty.text.trim().isEmpty) continue; // tidak dihitung = tidak diubah
        if (q == null || q < 0) return setState(() => _error = 'Isi hasil hitung dengan angka.');
        lines.add({'ingredient_id': l.ingredientId, 'counted': q});
        continue;
      }
      if (l.ingredientId == null && l.qty.text.trim().isEmpty) continue;
      if (l.ingredientId == null) return setState(() => _error = 'Pilih bahan di setiap baris.');
      if (q == null || q <= 0) return setState(() => _error = 'Isi jumlah lebih dari 0.');
      lines.add({'ingredient_id': l.ingredientId, 'qty': q, if (widget.kind == 'purchase') 'total_cost': parseRupiah(l.cost.text) ?? 0});
    }
    if (lines.isEmpty) return setState(() => _error = widget.kind == 'count' ? 'Isi minimal satu hasil hitung.' : 'Isi minimal satu bahan.');

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _call(
        ref,
        'post',
        switch (widget.kind) {
          'purchase' => '/stock/purchases',
          'waste' => '/stock/waste',
          _ => '/stock/counts',
        },
        {
          'id': _id,
        'outlet_id': ?widget.outletId,
          'lines': lines,
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
          if (widget.kind == 'purchase') ...{if (_supplier.text.trim().isNotEmpty) 'supplier': _supplier.text.trim(), 'paid_from_cash': _fromCash && widget.outletId == null},
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    final qtyFormat = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return AlertDialog(
      scrollable: true,
      title: Text(_title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch (widget.kind) {
              'purchase' => 'Isi jumlah & total harga per bahan. Modal rata-rata dihitung ulang otomatis.',
              'waste' => 'Bahan yang tumpah, basi, atau rusak. Tercatat sebagai kerugian di laporan.',
              _ => 'Isi hasil hitung fisik. Kosongkan bahan yang tidak dihitung. Selisih tercatat sebagai susut / lebih.',
            }, style: muted),
            const SizedBox(height: AppSpace.s3),
            if (widget.kind == 'count')
              for (final l in _lines)
                Builder(
                  builder: (context) {
                    final i = widget.data.ingredient(l.ingredientId!)!;
                    final q = _qty(l);
                    final diff = q == null ? null : q - i.stock;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.s2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(i.name, style: AppType.bodyStrong),
                                Text(
                                  'tercatat ${i.stockText}${diff == null || diff.abs() < 0.0005 ? '' : ' · selisih ${diff > 0 ? '+' : ''}${qtyText(diff)}'}',
                                  style: muted.copyWith(color: diff != null && diff < -0.0005 ? AppColors.danger : null),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.s2),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: l.qty,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: qtyFormat,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(hintText: '0', suffixText: i.unit, isDense: true),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
            else ...[
              for (final l in _lines)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpace.s2),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.s3),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: l.ingredientId,
                                decoration: const InputDecoration(labelText: 'Bahan', isDense: true),
                                items: [
                                  for (final i in _active)
                                    DropdownMenuItem(
                                      value: i.id,
                                      child: Text('${i.name} (${i.stockText})', overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                                onChanged: (v) => setState(() {
                                  l.ingredientId = v;
                                  l.big = false;
                                }),
                              ),
                            ),
                            if (_lines.length > 1)
                              IconButton(
                                tooltip: 'Hapus baris',
                                onPressed: () => setState(() => _lines.remove(l..dispose())),
                                icon: const Icon(Icons.close_rounded),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.s2),
                        Row(
                          children: [
                            Expanded(child: _qtyField(l, qtyFormat)),
                            if (widget.kind == 'purchase') ...[
                              const SizedBox(width: AppSpace.s2),
                              Expanded(
                                child: TextField(
                                  controller: l.cost,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(labelText: 'Harga', prefixText: 'Rp ', isDense: true),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _lines.length >= 50 ? null : () => setState(() => _lines.add(_Line())),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah bahan'),
                ),
              ),
            ],
            if (widget.kind == 'purchase') ...[
              const SizedBox(height: AppSpace.s2),
              TextField(
                controller: _supplier,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Supplier / toko (opsional)', counterText: ''),
              ),
              if (widget.outletId == null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _fromCash,
                onChanged: (v) => setState(() => _fromCash = v),
                title: const Text('Dibayar dari laci kas'),
                subtitle: Text(_fromCash ? 'Tercatat sebagai kas keluar ${rp(_total)} di shift tablet ini' : 'Dibayar di luar laci (transfer, uang owner)'),
              ),
            ],
            const SizedBox(height: AppSpace.s2),
            TextField(
              controller: _note,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: widget.kind == 'waste' ? 'Alasan (wajib)' : 'Catatan (opsional)',
                hintText: widget.kind == 'waste' ? 'mis. susu basi, gelas pecah' : null,
                counterText: '',
              ),
            ),
            if (_error != null) ...[const SizedBox(height: AppSpace.s2), Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(widget.kind == 'purchase' && _total > 0 ? 'Simpan · ${rp(_total)}' : 'Simpan')),
      ],
    );
  }

  Widget _qtyField(_Line l, List<TextInputFormatter> format) {
    final unit = l.ingredientId == null ? null : widget.data.ingredient(l.ingredientId!)?.unit;
    final big = unit == null ? null : bigUnit(unit);
    return TextField(
      controller: l.qty,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: format,
      decoration: InputDecoration(
        labelText: 'Jumlah',
        isDense: true,
        // Ketuk satuan untuk ganti g ↔ kg / ml ↔ L.
        suffixIcon: unit == null ? null : TextButton(onPressed: big == null ? null : () => setState(() => l.big = !l.big), child: Text(l.big ? big! : unit)),
      ),
    );
  }
}

/// Resep satu produk atau satu pilihan varian (ganti seluruh baris).
class _RecipeDialog extends ConsumerStatefulWidget {
  const _RecipeDialog({required this.title, required this.path, required this.lines, required this.data, this.allowNegative = false, this.price});

  final String title;
  final String path;
  final List<RecipeLine> lines;
  final InventoryData data;
  final bool allowNegative;
  final int? price;

  @override
  ConsumerState<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends ConsumerState<_RecipeDialog> {
  late final List<_Line> _lines = [
    for (final l in widget.lines) _Line(ingredientId: l.ingredientId, qty: qtyText(l.qty).replaceAll('.', '')),
    if (widget.lines.isEmpty) _Line(),
  ];
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<RecipeLine> get _parsed => [
    for (final l in _lines)
      if (l.ingredientId != null && parseQty(l.qty.text) != null) RecipeLine(l.ingredientId!, parseQty(l.qty.text)!),
  ];

  Future<void> _submit() async {
    final items = <Map<String, dynamic>>[];
    for (final l in _lines) {
      if (l.ingredientId == null && l.qty.text.trim().isEmpty) continue;
      final q = parseQty(l.qty.text);
      if (l.ingredientId == null) return setState(() => _error = 'Pilih bahan di setiap baris.');
      if (q == null || q == 0 || (!widget.allowNegative && q < 0)) {
        return setState(() => _error = widget.allowNegative ? 'Jumlah tidak boleh 0.' : 'Isi jumlah lebih dari 0.');
      }
      items.add({'ingredient_id': l.ingredientId, 'qty': q});
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _call(ref, 'put', widget.path, {'items': items});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _firstError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cost = widget.data.costOf(_parsed).round();
    final price = widget.price;
    final ingredients = widget.data.ingredients.where((i) => i.active || _lines.any((l) => l.ingredientId == i.id)).toList();
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    return AlertDialog(
      scrollable: true,
      title: Text('Resep ${widget.title}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.allowNegative ? 'Per 1 pilihan. Isi minus (−) untuk bahan yang digantikan.' : 'Pemakaian bahan untuk 1 porsi.', style: muted),
            const SizedBox(height: AppSpace.s3),
            for (final l in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                // HP: nama bahan satu baris penuh, jumlah di bawahnya.
                child: Flex(
                  direction: context.isCompact ? Axis.vertical : Axis.horizontal,
                  children: [
                    Flexible(
                      flex: context.isCompact ? 0 : 1,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: l.ingredientId,
                        decoration: const InputDecoration(labelText: 'Bahan', isDense: true),
                        items: [
                          for (final i in ingredients)
                            DropdownMenuItem(
                              value: i.id,
                              child: Text(i.name, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => l.ingredientId = v),
                      ),
                    ),
                    const SizedBox(width: AppSpace.s2, height: AppSpace.s2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: context.isCompact ? 150 : 110,
                          child: TextField(
                            controller: l.qty,
                            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: widget.allowNegative),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(widget.allowNegative ? r'[0-9,\-]' : r'[0-9,]'))],
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Jumlah',
                              isDense: true,
                              suffixText: l.ingredientId == null ? null : widget.data.ingredient(l.ingredientId!)?.unit,
                            ),
                          ),
                        ),
                        IconButton(tooltip: 'Hapus bahan', onPressed: () => setState(() => _lines.remove(l..dispose())), icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _lines.length >= 30 ? null : () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah bahan'),
              ),
            ),
            const Divider(),
            AppSummaryRow(widget.allowNegative ? 'Tambahan HPP' : 'HPP per porsi', '${cost < 0 ? '−' : ''}${rp(cost.abs())}'),
            if (price != null && price > 0 && _parsed.isNotEmpty)
              AppSummaryRow(
                'Margin',
                '${((price - cost) * 100 / price).toStringAsFixed(0)}% · laba ${rp(price - cost)}',
                valueColor: cost > price ? AppColors.danger : AppColors.success,
              ),
            if (_parsed.any((l) => (widget.data.ingredient(l.ingredientId)?.avgCost ?? 0) == 0))
              Text('Ada bahan tanpa modal (belum ada pembelian): HPP belum lengkap.', style: muted.copyWith(color: AppColors.warning)),
            if (_error != null) ...[const SizedBox(height: AppSpace.s2), Text(_error!, style: AppType.caption.copyWith(color: AppColors.danger))],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Simpan resep')),
      ],
    );
  }
}
