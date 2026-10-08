import 'menu_models.dart';

/// "Cold, Extra shot ×2" — opsi yang sama digabung dengan jumlahnya (urutan pertama muncul).
String modifierSummary(Iterable<MenuModifier> modifiers, {String times = '×'}) {
  final counts = <String, int>{};
  for (final m in modifiers) {
    counts[m.name] = (counts[m.name] ?? 0) + 1;
  }
  return counts.entries.map((e) => e.value > 1 ? '${e.key} $times${e.value}' : e.key).join(', ');
}

/// Pilihan modifier untuk satu produk. Logika murni (tanpa UI) agar bisa diuji dan dipakai
/// ulang oleh keranjang (M4). Server tetap memvalidasi ulang saat order dikirim.
class ModifierSelection {
  ModifierSelection(this.product, this.groups) {
    // Grup "pilih tepat 1" yang wajib langsung terisi pilihan pertama → kasir lebih cepat.
    for (final g in groups) {
      final options = g.activeModifiers;
      if (g.minSelect == 1 && g.maxSelect == 1 && options.isNotEmpty) {
        _selected[g.id] = [options.first.id];
      }
    }
  }

  final MenuProduct product;
  final List<MenuModifierGroup> groups;
  final Map<String, List<String>> _selected = {};

  List<String> selectedIn(MenuModifierGroup group) => List.unmodifiable(_selected[group.id] ?? const []);

  bool isSelected(MenuModifierGroup group, MenuModifier modifier) =>
      _selected[group.id]?.contains(modifier.id) ?? false;

  /// Jumlah opsi ini di grup (grup berjumlah bisa >1; grup biasa 0/1).
  int count(MenuModifierGroup group, MenuModifier modifier) =>
      _selected[group.id]?.where((id) => id == modifier.id).length ?? 0;

  int _total(MenuModifierGroup group) => _selected[group.id]?.length ?? 0;

  /// Bisa ditambah lagi: grup berjumlah, belum mencapai maks. per opsi & maks. total grup.
  bool canIncrement(MenuModifierGroup group, MenuModifier modifier) =>
      group.allowQuantity &&
      modifier.active &&
      count(group, modifier) < group.maxQuantity &&
      _total(group) < group.maxSelect;

  /// Tambah satu (grup berjumlah). Diam saja bila sudah penuh.
  void increment(MenuModifierGroup group, MenuModifier modifier) {
    if (!canIncrement(group, modifier)) return;
    _selected.putIfAbsent(group.id, () => []).add(modifier.id);
  }

  /// Kurangi satu (grup berjumlah).
  void decrement(MenuModifierGroup group, MenuModifier modifier) {
    _selected[group.id]?.remove(modifier.id);
  }

  /// Ketuk pilihan. Grup maks 1 berperilaku seperti radio; grup maks >1 seperti checkbox
  /// dan menolak pilihan baru bila sudah penuh.
  void toggle(MenuModifierGroup group, MenuModifier modifier) {
    if (!modifier.active) return;
    final current = _selected.putIfAbsent(group.id, () => []);

    if (current.contains(modifier.id)) {
      if (group.maxSelect == 1 && group.minSelect == 1) return; // radio wajib: tidak bisa dikosongkan
      current.remove(modifier.id);
    } else if (group.maxSelect == 1) {
      current
        ..clear()
        ..add(modifier.id);
    } else if (current.length < group.maxSelect) {
      current.add(modifier.id);
    }
  }

  /// Pesan untuk grup yang belum memenuhi syarat, atau null jika valid.
  String? errorFor(MenuModifierGroup group) {
    final n = _selected[group.id]?.length ?? 0;
    if (n < group.minSelect) return '${group.name}: ${group.rule.toLowerCase()}';
    if (n > group.maxSelect) return '${group.name}: maksimal ${group.maxSelect}';
    return null;
  }

  bool get isValid => groups.every((g) => errorFor(g) == null);

  /// Opsi terpilih; opsi berjumlah muncul berulang (Extra shot x2 = dua kali), sesuai format API.
  List<MenuModifier> get chosen => [
        for (final g in groups)
          for (final m in g.modifiers)
            for (var i = 0; i < count(g, m); i++) m,
      ];

  /// Harga satu unit: harga produk + total tambahan modifier.
  int get unitPrice => product.price + chosen.fold(0, (sum, m) => sum + m.priceDelta);
}
