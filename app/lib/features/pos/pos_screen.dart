import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_panel.dart';
import '../menu/menu_controller.dart';
import '../menu/menu_models.dart';
import '../menu/modifier_selection.dart';

/// Layar kasir: kategori + grid produk. Ketuk produk → pilih modifier.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String? _categoryId;

  Future<void> _pick(Menu menu, MenuProduct product) async {
    final selection = ModifierSelection(product, menu.groupsFor(product));
    final ok = selection.groups.isEmpty ||
        (await showDialog<bool>(
              context: context,
              builder: (_) => ModifierDialog(selection: selection),
            ) ??
            false);
    if (ok) ref.read(cartProvider.notifier).add(selection);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(menuProvider);

    return state.when(
      loading: () => const AppLoading(),
      error: (e, _) => AppErrorState(
        title: 'Menu gagal dimuat',
        message: '$e',
        onRetry: () => ref.invalidate(menuProvider),
      ),
      data: (s) {
        final categories = s.menu.activeCategories;
        final categoryId = _categoryId ?? categories.firstOrNull?.id;
        final products = categoryId == null ? <MenuProduct>[] : s.menu.productsIn(categoryId);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.fromCache)
                    MaterialBanner(
                      leading: const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
                      content: Text(s.refreshError == null
                          ? 'Memakai menu tersimpan, sedang memeriksa pembaruan…'
                          : 'Offline: memakai menu tersimpan. (${s.refreshError})'),
                      actions: [
                        TextButton(
                          onPressed: () => ref.read(menuProvider.notifier).refresh(),
                          child: const Text('Muat ulang'),
                        ),
                      ],
                    ),
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s4, 0),
                      children: [
                        for (final c in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: AppSpace.s2),
                            child: ChoiceChip(
                              label: Text(c.name),
                              showCheckmark: false,
                              selected: c.id == categoryId,
                              onSelected: (_) => setState(() => _categoryId = c.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: products.isEmpty
                        ? const AppEmptyState(
                            icon: Icons.local_cafe_rounded,
                            title: 'Belum ada produk',
                            message: 'Kategori ini masih kosong. Owner bisa menambah produk di Kelola Menu.',
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(AppSpace.s4),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 210,
                              mainAxisExtent: 116,
                              crossAxisSpacing: AppSpace.s3,
                              mainAxisSpacing: AppSpace.s3,
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
            const Expanded(flex: 2, child: CartPanel()),
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
    final soldOut = product.soldOut;
    return Material(
      color: soldOut ? AppColors.surfaceSunken : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: soldOut ? AppColors.surfaceSunken : AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: product.sellable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s3 + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.title.copyWith(color: soldOut ? AppColors.inkMuted : AppColors.ink),
                ),
              ),
              if (soldOut)
                const AppBadge('Habis', tone: AppTone.danger)
              else
                Text(rp(product.price), style: AppType.title.copyWith(color: AppColors.primary)),
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
    return AlertDialog(
      title: Text(s.product.name),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final g in s.groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s2),
                child: Row(children: [
                  Text(g.name, style: AppType.title),
                  const SizedBox(width: AppSpace.s2),
                  AppBadge(g.rule),
                ]),
              ),
              Wrap(
                spacing: AppSpace.s2,
                runSpacing: AppSpace.s2,
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
                  padding: const EdgeInsets.only(top: AppSpace.s1),
                  child: Text(error, style: AppType.caption.copyWith(color: AppColors.danger)),
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
