import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
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
  /// Kategori terpilih; null = Semua (default).
  String? _categoryId;

  Future<void> _pick(Menu menu, MenuProduct product) async {
    final selection = ModifierSelection(product, menu.groupsFor(product));
    final ok =
        selection.groups.isEmpty ||
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
      error: (e, _) =>
          AppErrorState(title: 'Menu gagal dimuat', message: '$e', onRetry: () => ref.invalidate(menuProvider)),
      data: (s) {
        final categories = s.menu.activeCategories;
        // Kategori yang dipilih bisa hilang setelah menu diperbarui → kembali ke Semua.
        final categoryId = categories.any((c) => c.id == _categoryId) ? _categoryId : null;
        final products = categoryId == null
            ? [for (final c in categories) ...s.menu.productsIn(c.id)]
            : s.menu.productsIn(categoryId);

        final short = context.isShort;
        final catalog = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.fromCache)
              MaterialBanner(
                leading: const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
                content: Text(
                  s.refreshError == null
                      ? 'Memakai menu tersimpan, sedang memeriksa pembaruan…'
                      : 'Offline: memakai menu tersimpan. (${s.refreshError})',
                ),
                actions: [
                  TextButton(
                    onPressed: () => ref.read(menuProvider.notifier).refresh(),
                    child: const Text('Muat ulang'),
                  ),
                ],
              ),
            SizedBox(
              height: short ? 52 : 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(AppSpace.s4, short ? AppSpace.s2 : AppSpace.s3, AppSpace.s4, 0),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.s2),
                    child: ChoiceChip(
                      label: const Text('Semua'),
                      showCheckmark: false,
                      selected: categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                  ),
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
                  ? AppEmptyState(
                      icon: Icons.local_cafe_rounded,
                      title: 'Belum ada produk',
                      message: categoryId == null
                          ? 'Menu masih kosong. Owner bisa menambah produk di Kelola Menu.'
                          : 'Kategori ini masih kosong. Owner bisa menambah produk di Kelola Menu.',
                    )
                  : GridView.builder(
                      padding: EdgeInsets.all(context.isCompact ? AppSpace.s3 : AppSpace.s4),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: context.isCompact ? 180 : 210,
                        mainAxisExtent: short ? 100 : (context.isCompact ? 104 : 116),
                        crossAxisSpacing: context.isCompact ? AppSpace.s2 : AppSpace.s3,
                        mainAxisSpacing: context.isCompact ? AppSpace.s2 : AppSpace.s3,
                      ),
                      itemCount: products.length,
                      itemBuilder: (_, i) =>
                          _ProductTile(product: products[i], onTap: () => _pick(s.menu, products[i])),
                    ),
            ),
          ],
        );

        return LayoutBuilder(
          builder: (context, box) {
            // Tablet portrait (tinggi) → keranjang di bawah katalog; katalog tetap lebar.
            if (box.maxHeight > box.maxWidth && box.maxWidth >= 520 && box.maxHeight >= 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: catalog),
                  SizedBox(
                    height: (box.maxHeight * 0.44).clamp(420.0, 560.0),
                    child: const CartPanel(dock: CartDock.bottom),
                  ),
                ],
              );
            }
            // Lebar cukup → katalog & keranjang berdampingan (tablet landscape, HP besar landscape).
            if (box.maxWidth >= 720) {
              final cartWidth = (box.maxWidth * 0.4).clamp(340.0, 440.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: catalog),
                  SizedBox(width: cartWidth, child: const CartPanel()),
                ],
              );
            }
            // HP: katalog penuh + ringkasan keranjang di bawah; ketuk untuk membuka pesanan.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: catalog),
                _CartBar(onOpen: _openCart),
              ],
            );
          },
        );
      },
    );
  }

  /// Keranjang layar penuh (HP). Aksi bayar memakai context & ref layar ini supaya dialog
  /// "Lunas"/kembalian tetap tampil setelah halaman keranjang tertutup.
  void _openCart() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CartPage(hostRef: ref, hostContext: context),
    ),
  );
}

/// Ringkasan keranjang di bawah katalog (HP).
class _CartBar extends ConsumerWidget {
  const _CartBar({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartTotalsProvider).grandTotal;
    final count = cart.lines.fold<int>(0, (n, l) => n + l.qty);
    final short = context.isShort;
    final summary = cart.isEmpty ? 'Keranjang kosong' : '$count item${cart.isSaved ? ' · ${cart.number}' : ''}';

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: cart.isEmpty ? null : onOpen,
        child: Container(
          padding: EdgeInsets.fromLTRB(AppSpace.s4, short ? AppSpace.s1 : AppSpace.s2, AppSpace.s3, short ? AppSpace.s1 : AppSpace.s2),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: short
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            AppOverline(summary),
                            const SizedBox(width: AppSpace.s3),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(rp(total), style: AppType.titleLg),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppOverline(summary),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(rp(total), style: AppType.moneyLg),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: AppSpace.s3),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: Size(0, short ? AppSize.touch : AppSize.touchLg)),
                  onPressed: cart.isEmpty ? null : onOpen,
                  icon: const Icon(Icons.shopping_bag_rounded),
                  label: const Text('Lihat pesanan'),
                ),
              ],
            ),
          ),
        ),
      ),
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
          padding: EdgeInsets.all(context.isShort ? AppSpace.s3 : AppSpace.s3 + 2),
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
      scrollable: true,
      title: Text(s.product.name),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in s.groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.s4, bottom: AppSpace.s2),
                child: Wrap(
                  spacing: AppSpace.s2,
                  runSpacing: AppSpace.s1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [Text(g.name, style: AppType.title), AppBadge(g.rule)],
                ),
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
