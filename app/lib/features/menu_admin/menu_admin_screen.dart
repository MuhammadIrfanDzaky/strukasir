import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import 'menu_admin_api.dart';
import 'product_import.dart';

/// Kelola menu oleh owner: produk, kategori, grup modifier.
class MenuAdminScreen extends ConsumerWidget {
  const MenuAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(menuProvider);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const ColoredBox(
            color: AppColors.surface,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.symmetric(horizontal: AppSpace.s3),
              tabs: [Tab(text: 'Produk'), Tab(text: 'Kategori'), Tab(text: 'Pilihan / Modifier')],
            ),
          ),
          Expanded(
            child: state.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorState(
                title: 'Menu gagal dimuat',
                message: '$e',
                onRetry: () => ref.invalidate(menuProvider),
              ),
              data: (s) => TabBarView(children: [
                _ProductsTab(menu: s.menu),
                _CategoriesTab(menu: s.menu),
                _GroupsTab(menu: s.menu),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jalankan aksi simpan/hapus dan tampilkan error API sebagai snackbar.
Future<bool> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      final detail = e.fieldErrors.values.expand((v) => v).join('\n');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail.isEmpty ? e.message : detail)));
    }
    return false;
  }
}

/// Daftar + tombol tambah mengambang di kanan bawah (tidak memakan satu baris di layar pendek).
Widget _withAddButton(String label, VoidCallback onPressed, List<Widget> children) => Stack(children: [
      ListView(padding: const EdgeInsets.only(bottom: 88), children: children),
      Positioned(
        right: AppSpace.s4,
        bottom: AppSpace.s4,
        child: FloatingActionButton.extended(
          heroTag: label,
          onPressed: onPressed,
          icon: const Icon(Icons.add_rounded),
          label: Text(label),
        ),
      ),
    ]);

// ───────────────────────────── Produk ─────────────────────────────

class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab({required this.menu});

  final Menu menu;

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  String _query = '';

  /// Filter kategori; null = semua.
  String? _categoryId;

  Menu get menu => widget.menu;

  @override
  Widget build(BuildContext context) {
    if (menu.categories.isEmpty) {
      return AppEmptyState(
        icon: Icons.category_rounded,
        title: 'Belum ada kategori',
        message: 'Buat kategori dulu di tab "Kategori", atau import menu dari file CSV.',
        action: OutlinedButton.icon(
          onPressed: () => importProducts(context, ref),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Import CSV'),
        ),
      );
    }

    final categories = [
      for (final c in menu.categories)
        if (_categoryId == null || c.id == _categoryId) c,
    ];
    final groups = [
      for (final c in categories)
        (c, menu.productsIn(c.id, includeInactive: true).where((p) => p.matches(_query)).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    final count = groups.fold<int>(0, (n, g) => n + g.$2.length);
    final compact = context.isCompact;

    final toolbar = Padding(
      padding: EdgeInsets.fromLTRB(compact ? AppSpace.s3 : AppSpace.s4, AppSpace.s3, compact ? AppSpace.s3 : AppSpace.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Cari nama atau kode produk',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: AppSpace.s2),
              compact
                  ? IconButton.outlined(
                      tooltip: 'Import CSV',
                      onPressed: () => importProducts(context, ref),
                      icon: const Icon(Icons.upload_file_rounded),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => importProducts(context, ref),
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Import CSV'),
                    ),
            ],
          ),
          const SizedBox(height: AppSpace.s2),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (id, label) in [(null, 'Semua'), for (final c in menu.categories) (c.id, c.name)])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.s2),
                    child: ChoiceChip(
                      label: Text(label),
                      showCheckmark: false,
                      selected: _categoryId == id,
                      onSelected: (_) => setState(() => _categoryId = id),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
            child: Text('$count produk', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ),
        ],
      ),
    );

    final empty = AppEmptyState(
      icon: Icons.search_off_rounded,
      title: 'Tidak ada produk yang cocok',
      message: _query.isEmpty ? null : 'Tidak ada nama atau kode yang memuat "$_query".',
    );
    final rows = [
      for (final (c, products) in groups) ...[
        Container(
          color: AppColors.surfaceSunken,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s2),
          child: AppOverline('${c.name} · ${products.length}', color: AppColors.ink),
        ),
        for (final p in products) _ProductRow(product: p, menu: menu, onTap: () => _openForm(context, p)),
      ],
    ];

    // Layar pendek (HP landscape): toolbar ikut di-scroll supaya daftar produk tetap dapat ruang.
    if (context.isShort) {
      return _withAddButton('Produk baru', () => _openForm(context, null), [
        toolbar,
        if (groups.isEmpty) SizedBox(height: 220, child: empty) else ...rows,
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        Expanded(child: groups.isEmpty ? empty : _withAddButton('Produk baru', () => _openForm(context, null), rows)),
      ],
    );
  }

  void _openForm(BuildContext context, MenuProduct? product) =>
      showDialog<void>(context: context, builder: (_) => ProductForm(menu: menu, product: product));
}

/// Satu produk di Kelola Menu: nama + kode, harga jual, modal, margin, status.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.menu, required this.onTap});

  final MenuProduct product;
  final Menu menu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final margin = p.marginPercent;
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    final groups = menu.groupsFor(p).map((g) => g.name).join(', ');

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s2, AppSpace.s3),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpace.s2,
                      runSpacing: AppSpace.s1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          p.name,
                          style: AppType.bodyStrong.copyWith(
                            decoration: p.active ? null : TextDecoration.lineThrough,
                            color: p.active ? AppColors.ink : AppColors.inkMuted,
                          ),
                        ),
                        if (p.favorite) const Icon(Icons.star_rounded, size: 18, color: AppColors.accent),
                        if (p.code != null) AppBadge(p.code!),
                        if (!p.active) const AppBadge('Nonaktif'),
                        if (p.soldOut) const AppBadge('Habis', tone: AppTone.danger),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s1),
                    Wrap(
                      spacing: AppSpace.s4,
                      runSpacing: AppSpace.s1,
                      children: [
                        Text(rp(p.price), style: AppType.bodyStrong.copyWith(color: AppColors.primary)),
                        Text(p.cost == null ? 'Modal belum diisi' : 'Modal ${rp(p.cost!)}', style: muted),
                        if (margin != null)
                          Text(
                            'Margin ${margin.toStringAsFixed(0)}%',
                            style: muted.copyWith(
                              color: margin < 0 ? AppColors.danger : AppColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    if (groups.isNotEmpty) Text(groups, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductForm extends ConsumerStatefulWidget {
  const ProductForm({super.key, required this.menu, this.product});

  final Menu menu;
  final MenuProduct? product;

  @override
  ConsumerState<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<ProductForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _price = TextEditingController(text: widget.product == null ? '' : rupiah(widget.product!.price));
  late final _code = TextEditingController(text: widget.product?.code);
  late final _cost = TextEditingController(text: widget.product?.cost == null ? '' : rupiah(widget.product!.cost!));
  late bool _favorite = widget.product?.favorite ?? false;
  late String? _categoryId = widget.product?.categoryId ?? widget.menu.categories.firstOrNull?.id;
  late bool _active = widget.product?.active ?? true;
  late bool _soldOut = widget.product?.soldOut ?? false;
  late final List<String> _groupIds = [...?widget.product?.modifierGroupIds];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _code.dispose();
    _cost.dispose();
    super.dispose();
  }

  /// Margin dari isian saat ini, mis. "Margin 50% · laba Rp 3.000 per porsi".
  String? get _marginText {
    final price = parseRupiah(_price.text);
    final cost = parseRupiah(_cost.text);
    if (price == null || cost == null || price == 0) return null;
    final margin = (price - cost) * 100 / price;
    return 'Margin ${margin.toStringAsFixed(margin.abs() < 10 ? 1 : 0)}% · laba ${rp(price - cost)} per porsi';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await _run(
      context,
      () => ref.read(menuAdminApiProvider).saveProduct(
            id: widget.product?.id,
            categoryId: _categoryId!,
            name: _name.text,
            price: parseRupiah(_price.text)!,
            code: _code.text,
            cost: _cost.text.trim().isEmpty ? null : parseRupiah(_cost.text),
            favorite: _favorite,
            active: _active,
            soldOut: _soldOut,
            modifierGroupIds: _groupIds,
          ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.product == null ? 'Produk baru' : 'Ubah produk'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama produk'),
                validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
              ),
              const SizedBox(height: AppSpace.s3),
              TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Kode produk (opsional)', hintText: 'mis. BB03'),
                validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[A-Za-z0-9._-]{1,30}$').hasMatch(v!.trim())
                    ? null
                    : 'Huruf, angka, titik, minus, atau garis bawah (maks. 30)',
              ),
              const SizedBox(height: AppSpace.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Harga jual', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      validator: (v) => parseRupiah(v ?? '') == null ? 'Isi harga dalam angka' : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s3),
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      decoration: const InputDecoration(labelText: 'Modal (HPP)', prefixText: 'Rp '),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty || parseRupiah(v!) != null ? null : 'Isi dalam angka',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s1),
                child: Text(
                  _marginText ?? 'Isi modal untuk melihat margin & laba kotor di laporan.',
                  style: AppType.caption.copyWith(
                    color: (parseRupiah(_cost.text) ?? 0) > (parseRupiah(_price.text) ?? 0)
                        ? AppColors.danger
                        : AppColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.s3),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  for (final c in widget.menu.categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Pilih kategori' : null,
              ),
              SwitchListTile(
                title: const Text('Aktif (tampil di kasir)'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                title: const Text('Habis hari ini'),
                value: _soldOut,
                onChanged: (v) => setState(() => _soldOut = v),
              ),
              SwitchListTile(
                title: const Text('Favorit'),
                subtitle: const Text('Tampil di filter "Favorit" layar kasir'),
                value: _favorite,
                onChanged: (v) => setState(() => _favorite = v),
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.s2), child: Divider()),
              const AppOverline('Pilihan untuk produk ini (urutan = urutan tampil)'),
              for (final g in widget.menu.modifierGroups)
                CheckboxListTile(
                  title: Text(g.name),
                  subtitle: Text('${g.rule} · ${g.activeModifiers.map((m) => m.name).join(', ')}'),
                  value: _groupIds.contains(g.id),
                  onChanged: (v) => setState(() => v! ? _groupIds.add(g.id) : _groupIds.remove(g.id)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
      ],
    );
  }
}

// ───────────────────────────── Kategori ─────────────────────────────

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab({required this.menu});

  final Menu menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(menuAdminApiProvider);

    return _withAddButton('Kategori baru', () => _edit(context, api, null), [
              for (final c in menu.categories)
                ListTile(
                  tileColor: AppColors.surface,
                  title: Text(c.name),
                  subtitle: Text('${menu.productsIn(c.id, includeInactive: true).length} produk'
                      '${c.active ? '' : ' · nonaktif'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: c.active,
                      onChanged: (v) => _run(
                          context, () => api.saveCategory(id: c.id, name: c.name, active: v, sort: c.sort)),
                    ),
                    IconButton(
                        tooltip: 'Ubah', icon: const Icon(Icons.edit_rounded), onPressed: () => _edit(context, api, c)),
                    IconButton(
                      tooltip: 'Hapus',
                      color: AppColors.danger,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        if (await _confirm(context, 'Hapus kategori "${c.name}"?') && context.mounted) {
                          await _run(context, () => api.deleteCategory(c.id));
                        }
                      },
                    ),
                  ]),
                ),
            ]);
  }

  Future<void> _edit(BuildContext context, MenuAdminApi api, MenuCategory? c) async {
    final name = await _askText(context, c == null ? 'Kategori baru' : 'Ubah kategori', c?.name ?? '');
    if (name == null || !context.mounted) return;
    await _run(
      context,
      () => api.saveCategory(id: c?.id, name: name, active: c?.active ?? true, sort: c?.sort ?? menu.categories.length),
    );
  }
}

// ───────────────────────────── Grup modifier ─────────────────────────────

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab({required this.menu});

  final Menu menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _withAddButton('Grup pilihan baru', () => _open(context, null), [
              for (final g in menu.modifierGroups)
                ListTile(
                  tileColor: AppColors.surface,
                  title: Text('${g.name}  ·  ${g.rule}'),
                  subtitle: Text(g.activeModifiers
                      .map((m) => m.priceDelta > 0 ? '${m.name} (+${rupiah(m.priceDelta)})' : m.name)
                      .join(', ')),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => _open(context, g),
                ),
            ]);
  }

  void _open(BuildContext context, MenuModifierGroup? group) =>
      showDialog<void>(context: context, builder: (_) => ModifierGroupForm(group: group));
}

class _OptionRow {
  _OptionRow({this.id, String name = '', int price = 0})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price == 0 ? '0' : rupiah(price));

  final String? id;
  final TextEditingController name;
  final TextEditingController price;
}

class ModifierGroupForm extends ConsumerStatefulWidget {
  const ModifierGroupForm({super.key, this.group});

  final MenuModifierGroup? group;

  @override
  ConsumerState<ModifierGroupForm> createState() => _ModifierGroupFormState();
}

class _ModifierGroupFormState extends ConsumerState<ModifierGroupForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.group?.name);
  late bool _required = (widget.group?.minSelect ?? 0) > 0;
  late int _max = widget.group?.maxSelect ?? 1;

  /// Satu pilihan boleh lebih dari sekali (mis. Extra shot x2), maks. [_maxQty] per pilihan.
  late bool _allowQty = widget.group?.allowQuantity ?? false;
  late int _maxQty = (widget.group?.maxQuantity ?? 1) < 2 ? 3 : widget.group!.maxQuantity;
  late final List<_OptionRow> _rows = widget.group == null
      ? [_OptionRow()]
      : [for (final m in widget.group!.activeModifiers) _OptionRow(id: m.id, name: m.name, price: m.priceDelta)];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    for (final r in _rows) {
      r.name.dispose();
      r.price.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final api = ref.read(menuAdminApiProvider);
    final ok = await _run(
      context,
      () => api.saveModifierGroup(
        id: widget.group?.id,
        name: _name.text,
        minSelect: _required ? 1 : 0,
        maxSelect: _max,
        allowQuantity: _allowQty,
        maxQuantity: _maxQty,
        modifiers: [
          for (final r in _rows)
            {if (r.id != null) 'id': r.id, 'name': r.name.text.trim(), 'price_delta': parseRupiah(r.price.text) ?? 0},
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await _confirm(context, 'Hapus grup "${widget.group!.name}"? Produk tidak lagi menampilkan pilihan ini.')) {
      return;
    }
    if (!mounted) return;
    final ok = await _run(context, () => ref.read(menuAdminApiProvider).deleteModifierGroup(widget.group!.id));
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.group == null ? 'Grup pilihan baru' : 'Ubah grup pilihan'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama grup (mis. Suhu, Gula, Tambahan)'),
                validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
              ),
              SwitchListTile(
                title: const Text('Wajib dipilih'),
                value: _required,
                onChanged: (v) => setState(() => _required = v),
              ),
              SwitchListTile(
                title: const Text('Boleh pilih lebih dari 1 (jumlah)'),
                subtitle: Text('Mis. Extra shot x2. Cocok untuk grup Tambahan.',
                    style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                value: _allowQty,
                onChanged: (v) => setState(() {
                  _allowQty = v;
                  if (!v && _max > _rows.length) _max = _rows.length;
                }),
              ),
              if (_allowQty)
                Row(children: [
                  const Expanded(child: Text('Maksimal per pilihan')),
                  IconButton(
                      onPressed: _maxQty > 2 ? () => setState(() => _maxQty--) : null,
                      icon: const Icon(Icons.remove_rounded)),
                  Text('$_maxQty', style: AppType.title),
                  IconButton(
                      onPressed: _maxQty < 20 ? () => setState(() => _maxQty++) : null,
                      icon: const Icon(Icons.add_rounded)),
                ]),
              Row(children: [
                // Grup berjumlah: batas total jumlah di grup (mis. maks. 3 tambahan per minuman).
                Expanded(child: Text(_allowQty ? 'Maksimal total jumlah' : 'Maksimal dipilih')),
                IconButton(
                    onPressed: _max > 1 ? () => setState(() => _max--) : null, icon: const Icon(Icons.remove_rounded)),
                Text('$_max', style: AppType.title),
                IconButton(
                    onPressed: _max < (_allowQty ? 20 : _rows.length) ? () => setState(() => _max++) : null,
                    icon: const Icon(Icons.add_rounded)),
              ]),
              const Divider(),
              const SizedBox(height: AppSpace.s3),
              for (final (i, r) in _rows.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s3),
                  child: Builder(builder: (context) {
                    final name = TextFormField(
                      controller: r.name,
                      decoration: InputDecoration(labelText: 'Pilihan ${i + 1}'),
                      validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
                    );
                    final price = TextFormField(
                      controller: r.price,
                      decoration: const InputDecoration(labelText: 'Tambahan harga', prefixText: '+Rp '),
                      keyboardType: TextInputType.number,
                    );
                    final remove = IconButton(
                      tooltip: 'Hapus pilihan',
                      onPressed: _rows.length > 1
                          ? () => setState(() {
                                _rows.removeAt(i);
                                if (!_allowQty && _max > _rows.length) _max = _rows.length;
                              })
                          : null,
                      icon: const Icon(Icons.close_rounded),
                    );
                    // HP sempit: nama & harga bertumpuk supaya kolom tidak terlalu kecil.
                    if (context.isCompact) {
                      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Column(children: [name, const SizedBox(height: AppSpace.s2), price])),
                        remove,
                      ]);
                    }
                    return Row(children: [
                      Expanded(flex: 3, child: name),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: price),
                      remove,
                    ]);
                  }),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_OptionRow())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah pilihan'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.group != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _busy ? null : _delete,
            child: const Text('Hapus grup'),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
      ],
    );
  }
}

// ───────────────────────────── Dialog bantu ─────────────────────────────

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        scrollable: true,
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ya')),
        ],
      ),
    ) ??
    false;

Future<String?> _askText(BuildContext context, String title, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      scrollable: true,
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Nama')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(context, v);
          },
          child: const Text('Simpan'),
        ),
      ],
    ),
  ); // controller tidak di-dispose di sini: dialog masih beranimasi keluar saat Future selesai.
}
