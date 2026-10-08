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
  /// Kategori terpilih; null = Semua (default), [_favorites] = produk favorit.
  String? _categoryId;
  static const _favorites = '__favorit__';

  /// Pencarian nama / kode produk (lintas kategori). null = kotak cari tertutup.
  String? _query;

  Future<void> _pick(Menu menu, MenuProduct product) async {
    final selection = ModifierSelection(product, menu.modifiersOn ? menu.groupsFor(product) : const []);
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
        // Kasir: produk urut abjad di "Semua" (per kategori), per kategori, favorit, dan hasil cari.
        final byCategory = {for (final c in categories) c.id: s.menu.productsByName(c.id)};
        final all = [for (final c in categories) ...byCategory[c.id]!];
        final hasFavorites = all.any((p) => p.favorite);
        // Kategori yang dipilih bisa hilang setelah menu diperbarui → kembali ke Semua.
        final categoryId = (_categoryId == _favorites && hasFavorites) || categories.any((c) => c.id == _categoryId)
            ? _categoryId
            : null;
        final searching = _query != null && _query!.trim().isNotEmpty;
        final products = searching
            ? Menu.sortByName(all.where((p) => p.matches(_query!)))
            : switch (categoryId) {
                null => all,
                _favorites => Menu.sortByName(all.where((p) => p.favorite)),
                final id => byCategory[id] ?? const <MenuProduct>[],
              };

        Widget chip(String label, String? id, {IconData? icon}) => Padding(
              padding: const EdgeInsets.only(right: AppSpace.s2),
              child: ChoiceChip(
                avatar: icon == null ? null : Icon(icon, size: 18),
                label: Text(label),
                showCheckmark: false,
                selected: !searching && categoryId == id,
                onSelected: (_) => setState(() => _categoryId = id),
              ),
            );

        final short = context.isShort;
        final gridPad = context.isCompact ? AppSpace.s3 : AppSpace.s4;
        final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: context.isCompact ? 180 : 210,
          mainAxisExtent: short ? 100 : (context.isCompact ? 104 : 116),
          crossAxisSpacing: context.isCompact ? AppSpace.s2 : AppSpace.s3,
          mainAxisSpacing: context.isCompact ? AppSpace.s2 : AppSpace.s3,
        );
        Widget tile(MenuProduct p) => _ProductTile(product: p, onTap: () => _pick(s.menu, p));
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
              child: Padding(
                padding: EdgeInsets.fromLTRB(AppSpace.s2, short ? AppSpace.s2 : AppSpace.s3, 0, 0),
                child: _query != null
                    // Kotak cari menggantikan baris kategori; tutup → kembali ke kategori.
                    ? Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: AppSpace.s2),
                              child: TextField(
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'Cari nama atau kode produk',
                                  prefixIcon: Icon(Icons.search_rounded),
                                  isDense: true,
                                ),
                                onChanged: (v) => setState(() => _query = v),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tutup pencarian',
                            onPressed: () => setState(() => _query = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          const SizedBox(width: AppSpace.s2),
                        ],
                      )
                    : ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: AppSpace.s4),
                        children: [
                          IconButton(
                            tooltip: 'Cari produk',
                            onPressed: () => setState(() => _query = ''),
                            icon: const Icon(Icons.search_rounded),
                          ),
                          chip('Semua', null),
                          if (hasFavorites) chip('Favorit', _favorites, icon: Icons.star_rounded),
                          for (final c in categories) chip(c.name, c.id),
                        ],
                      ),
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? searching
                      ? AppEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'Produk tidak ditemukan',
                          message: 'Tidak ada nama atau kode yang memuat "${_query!.trim()}".',
                        )
                      : AppEmptyState(
                          icon: Icons.local_cafe_rounded,
                          title: 'Belum ada produk',
                          message: categoryId == null
                              ? 'Menu masih kosong. Owner bisa menambah produk di Kelola Menu.'
                              : 'Kategori ini masih kosong. Owner bisa menambah produk di Kelola Menu.',
                        )
                  : categoryId == null && !searching
                      // "Semua": dikelompokkan per kategori dengan judul, supaya tetap ada pembeda.
                      ? CustomScrollView(
                          slivers: [
                            for (final (i, c) in categories.indexed)
                              if (byCategory[c.id]!.isNotEmpty) ...[
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(gridPad, i == 0 ? gridPad : AppSpace.s2, gridPad, 0),
                                  sliver: SliverToBoxAdapter(
                                    child: _CategoryHeader(c.name, byCategory[c.id]!.length),
                                  ),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(gridPad, AppSpace.s2, gridPad, gridPad),
                                  sliver: SliverGrid.builder(
                                    gridDelegate: gridDelegate,
                                    itemCount: byCategory[c.id]!.length,
                                    itemBuilder: (_, j) => tile(byCategory[c.id]![j]),
                                  ),
                                ),
                              ],
                          ],
                        )
                      : GridView.builder(
                          padding: EdgeInsets.all(gridPad),
                          gridDelegate: gridDelegate,
                          itemCount: products.length,
                          itemBuilder: (_, i) => tile(products[i]),
                        ),
            ),
          ],
        );

        return LayoutBuilder(
          builder: (context, box) {
            // Pilihan tata letak memakai tinggi TANPA keyboard: kalau ikut berubah saat keyboard
            // muncul, panel keranjang dibangun ulang dan kolom yang sedang diketik kehilangan fokus.
            // Inset diambil dari View (layar fisik): Scaffold menghapus viewInsets dari MediaQuery isinya.
            final view = View.of(context);
            final height = box.maxHeight + view.viewInsets.bottom / view.devicePixelRatio;
            // Tablet portrait (tinggi) → keranjang di bawah katalog; katalog tetap lebar.
            if (height > box.maxWidth && box.maxWidth >= 520 && height >= 900) {
              final dock = (height * 0.44).clamp(420.0, 560.0);
              // Sedang mencari → katalog (dengan kotak cari) wajib terlihat; keranjang yang mengecil.
              final room = _query != null ? box.maxHeight - 160 : box.maxHeight;
              final cartHeight = (dock < room ? dock : room).clamp(0.0, box.maxHeight);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Saat keyboard terbuka, keranjang tetap utuh; katalog mengecil / disembunyikan sementara.
                  Expanded(child: box.maxHeight - cartHeight >= 140 ? catalog : const SizedBox.shrink()),
                  SizedBox(height: cartHeight, child: const CartPanel(dock: CartDock.bottom)),
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

/// Judul kelompok di tab "Semua": garis aksen + nama kategori + jumlah produk + garis pembatas.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader(this.name, this.count);

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.smAll),
        ),
        const SizedBox(width: AppSpace.s2),
        // Lebar nama dibatasi (bukan Flexible) supaya garis pembatas memenuhi sisa baris.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: AppColors.ink, letterSpacing: 0.6)),
        ),
        const SizedBox(width: AppSpace.s2),
        Text('$count', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
        const SizedBox(width: AppSpace.s3),
        const Expanded(child: Divider(height: 1, color: AppColors.line)),
      ],
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

/// Satu opsi di grup berjumlah: nama + harga, lalu − jumlah +.
class _QuantityOption extends StatelessWidget {
  const _QuantityOption({required this.selection, required this.group, required this.modifier, required this.onChanged});

  final ModifierSelection selection;
  final MenuModifierGroup group;
  final MenuModifier modifier;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final n = selection.count(group, modifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(modifier.name, style: n > 0 ? AppType.bodyStrong : AppType.body),
                if (modifier.priceDelta > 0)
                  Text('+${rupiah(modifier.priceDelta)}', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Kurangi ${modifier.name}',
            onPressed: n == 0
                ? null
                : () {
                    selection.decrement(group, modifier);
                    onChanged();
                  },
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 40,
            child: Text('$n', textAlign: TextAlign.center, style: AppType.title.copyWith(color: n > 0 ? AppColors.primary : null)),
          ),
          IconButton.outlined(
            tooltip: 'Tambah ${modifier.name}',
            onPressed: selection.canIncrement(group, modifier)
                ? () {
                    selection.increment(group, modifier);
                    onChanged();
                  }
                : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
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
              if (g.allowQuantity)
                // Grup berjumlah: tiap opsi punya tombol − jumlah +.
                for (final m in g.activeModifiers) _QuantityOption(selection: s, group: g, modifier: m, onChanged: () => setState(() {}))
              else
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
