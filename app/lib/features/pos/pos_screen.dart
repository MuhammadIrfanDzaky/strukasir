import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import '../menu/modifier_selection.dart';

/// Layar kasir: kategori + grid produk. Ketuk produk → pilih modifier.
/// Keranjang & pembayaran dibangun di M4; untuk sekarang panel kanan menampilkan pilihan terakhir.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String? _categoryId;
  ModifierSelection? _last;

  Future<void> _pick(Menu menu, MenuProduct product) async {
    final selection = ModifierSelection(product, menu.groupsFor(product));
    final ok = selection.groups.isEmpty ||
        (await showDialog<bool>(
              context: context,
              builder: (_) => ModifierDialog(selection: selection),
            ) ??
            false);
    if (ok) setState(() => _last = selection);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(menuProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Menu gagal dimuat: $e'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => ref.invalidate(menuProvider), child: const Text('Coba lagi')),
        ]),
      ),
      data: (s) {
        final categories = s.menu.activeCategories;
        final categoryId = _categoryId ?? categories.firstOrNull?.id;
        final products = categoryId == null ? <MenuProduct>[] : s.menu.productsIn(categoryId);

        return Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.fromCache)
                    MaterialBanner(
                      content: Text(s.refreshError == null
                          ? 'Memakai menu tersimpan, sedang memeriksa pembaruan…'
                          : 'Offline — memakai menu tersimpan. (${s.refreshError})'),
                      actions: [
                        TextButton(
                          onPressed: () => ref.read(menuProvider.notifier).refresh(),
                          child: const Text('Muat ulang'),
                        ),
                      ],
                    ),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      children: [
                        for (final c in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(c.name),
                              selected: c.id == categoryId,
                              onSelected: (_) => setState(() => _categoryId = c.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: products.isEmpty
                        ? const Center(child: Text('Belum ada produk di kategori ini.'))
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisExtent: 110,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: products.length,
                            itemBuilder: (_, i) => _ProductTile(
                              product: products[i],
                              onTap: () => _pick(s.menu, products[i]),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Keranjang', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Keranjang & pembayaran menyusul di M4.'),
                    if (_last != null) ...[
                      const Divider(height: 32),
                      Text('Pilihan terakhir', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(_last!.product.name, style: Theme.of(context).textTheme.titleMedium),
                      for (final m in _last!.chosen)
                        Text('+ ${m.name}${m.priceDelta > 0 ? ' (${rupiah(m.priceDelta)})' : ''}'),
                      const SizedBox(height: 4),
                      Text(rp(_last!.unitPrice), style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final MenuProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      color: product.soldOut ? theme.colorScheme.surfaceContainerHighest : null,
      child: InkWell(
        onTap: product.sellable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(product.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              ),
              Text(product.soldOut ? 'HABIS' : rp(product.price),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: product.soldOut ? theme.colorScheme.error : theme.colorScheme.primary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog pilih modifier. Tombol "Tambah" aktif hanya bila semua grup wajib terpenuhi.
class ModifierDialog extends StatefulWidget {
  const ModifierDialog({super.key, required this.selection});

  final ModifierSelection selection;

  @override
  State<ModifierDialog> createState() => _ModifierDialogState();
}

class _ModifierDialogState extends State<ModifierDialog> {
  ModifierSelection get s => widget.selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(s.product.name),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final g in s.groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Row(children: [
                  Text(g.name, style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  Text(g.rule, style: theme.textTheme.bodySmall),
                ]),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in g.activeModifiers)
                    FilterChip(
                      label: Text(m.priceDelta > 0 ? '${m.name}  +${rupiah(m.priceDelta)}' : m.name),
                      selected: s.isSelected(g, m),
                      onSelected: (_) => setState(() => s.toggle(g, m)),
                    ),
                ],
              ),
              if (s.errorFor(g) case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(
          onPressed: s.isValid ? () => Navigator.pop(context, true) : null,
          child: Text('Tambah · ${rp(s.unitPrice)}'),
        ),
      ],
    );
  }
}
