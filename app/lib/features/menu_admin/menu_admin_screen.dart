import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import 'menu_admin_api.dart';

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
          const TabBar(tabs: [Tab(text: 'Produk'), Tab(text: 'Kategori'), Tab(text: 'Pilihan / Modifier')]),
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Menu gagal dimuat: $e')),
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

Widget _addButton(String label, VoidCallback onPressed) => Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(onPressed: onPressed, icon: const Icon(Icons.add), label: Text(label)),
      ),
    );

// ───────────────────────────── Produk ─────────────────────────────

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({required this.menu});

  final Menu menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (menu.categories.isEmpty) {
      return const Center(child: Text('Buat kategori dulu di tab "Kategori".'));
    }

    return Column(
      children: [
        _addButton('Produk baru', () => _openForm(context, null)),
        Expanded(
          child: ListView(
            children: [
              for (final c in menu.categories) ...[
                ListTile(
                  title: Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                  dense: true,
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                for (final p in menu.productsIn(c.id, includeInactive: true))
                  ListTile(
                    title: Text(p.name,
                        style: TextStyle(decoration: p.active ? null : TextDecoration.lineThrough)),
                    subtitle: Text([
                      rp(p.price),
                      if (!p.active) 'nonaktif',
                      if (p.soldOut) 'habis',
                      ...menu.groupsFor(p).map((g) => g.name),
                    ].join(' · ')),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _openForm(context, p),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openForm(BuildContext context, MenuProduct? product) =>
      showDialog<void>(context: context, builder: (_) => ProductForm(menu: menu, product: product));
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
  late String? _categoryId = widget.product?.categoryId ?? widget.menu.categories.firstOrNull?.id;
  late bool _active = widget.product?.active ?? true;
  late bool _soldOut = widget.product?.soldOut ?? false;
  late final List<String> _groupIds = [...?widget.product?.modifierGroupIds];
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
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
      title: Text(widget.product == null ? 'Produk baru' : 'Ubah produk'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama produk'),
                validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
              ),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Harga', prefixText: 'Rp '),
                keyboardType: TextInputType.number,
                validator: (v) => parseRupiah(v ?? '') == null ? 'Isi harga dalam angka' : null,
              ),
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
              const Divider(),
              Text('Pilihan untuk produk ini (urutan = urutan tampil)',
                  style: Theme.of(context).textTheme.labelLarge),
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

    return Column(
      children: [
        _addButton('Kategori baru', () => _edit(context, api, null)),
        Expanded(
          child: ListView(
            children: [
              for (final c in menu.categories)
                ListTile(
                  title: Text(c.name),
                  subtitle: Text('${menu.productsIn(c.id, includeInactive: true).length} produk'
                      '${c.active ? '' : ' · nonaktif'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: c.active,
                      onChanged: (v) => _run(
                          context, () => api.saveCategory(id: c.id, name: c.name, active: v, sort: c.sort)),
                    ),
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(context, api, c)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await _confirm(context, 'Hapus kategori "${c.name}"?') && context.mounted) {
                          await _run(context, () => api.deleteCategory(c.id));
                        }
                      },
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
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
    return Column(
      children: [
        _addButton('Grup pilihan baru', () => _open(context, null)),
        Expanded(
          child: ListView(
            children: [
              for (final g in menu.modifierGroups)
                ListTile(
                  title: Text('${g.name}  ·  ${g.rule}'),
                  subtitle: Text(g.activeModifiers
                      .map((m) => m.priceDelta > 0 ? '${m.name} (+${rupiah(m.priceDelta)})' : m.name)
                      .join(', ')),
                  trailing: const Icon(Icons.edit),
                  onTap: () => _open(context, g),
                ),
            ],
          ),
        ),
      ],
    );
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
      title: Text(widget.group == null ? 'Grup pilihan baru' : 'Ubah grup pilihan'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
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
              Row(children: [
                const Text('Maksimal dipilih'),
                const Spacer(),
                IconButton(
                    onPressed: _max > 1 ? () => setState(() => _max--) : null, icon: const Icon(Icons.remove)),
                Text('$_max', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    onPressed: _max < _rows.length ? () => setState(() => _max++) : null,
                    icon: const Icon(Icons.add)),
              ]),
              const Divider(),
              for (final (i, r) in _rows.indexed)
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: r.name,
                      decoration: InputDecoration(labelText: 'Pilihan ${i + 1}'),
                      validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: r.price,
                      decoration: const InputDecoration(labelText: 'Tambahan harga', prefixText: '+Rp '),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  IconButton(
                    onPressed: _rows.length > 1
                        ? () => setState(() {
                              _rows.removeAt(i);
                              if (_max > _rows.length) _max = _rows.length;
                            })
                        : null,
                    icon: const Icon(Icons.close),
                  ),
                ]),
              TextButton.icon(
                onPressed: () => setState(() => _rows.add(_OptionRow())),
                icon: const Icon(Icons.add),
                label: const Text('Tambah pilihan'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.group != null)
          TextButton(onPressed: _busy ? null : _delete, child: const Text('Hapus grup')),
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
