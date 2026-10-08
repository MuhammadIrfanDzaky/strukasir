import 'package:berrybrew_pos/core/money.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bentuk JSON sama persis dengan respons `GET /api/v1/menu`.
final menuJson = <String, dynamic>{
  'version': 'abc123',
  'pricing': {'service_bp': 0, 'tax_bp': 0, 'rounding_unit': 0, 'cashier_discount_limit_bp': 1000},
  'features': {'modifiers': true, 'discounts': true, 'split_payment': true, 'open_bill': true},
  'categories': [
    {'id': 'c1', 'name': 'Kopi', 'sort': 0, 'active': true},
    {'id': 'c2', 'name': 'Arsip', 'sort': 1, 'active': false},
  ],
  'products': [
    {
      'id': 'p1', 'category_id': 'c1', 'name': 'Americano', 'price': 13000,
      'active': true, 'sold_out': false, 'sort': 0, 'modifier_group_ids': ['g1', 'g3'],
    },
    {
      'id': 'p2', 'category_id': 'c1', 'name': 'Lama', 'price': 10000,
      'active': false, 'sold_out': false, 'sort': 1, 'modifier_group_ids': [],
    },
  ],
  'modifier_groups': [
    {
      'id': 'g1', 'name': 'Suhu', 'min_select': 1, 'max_select': 1, 'sort': 0,
      'modifiers': [
        {'id': 'hot', 'name': 'Hot', 'price_delta': 0, 'active': true, 'sort': 0},
        {'id': 'cold', 'name': 'Cold', 'price_delta': 2000, 'active': true, 'sort': 1},
      ],
    },
    {
      'id': 'g3', 'name': 'Tambahan', 'min_select': 0, 'max_select': 2, 'sort': 2,
      'allow_quantity': true, 'max_quantity': 2,
      'modifiers': [
        {'id': 'shot', 'name': 'Extra shot', 'price_delta': 5000, 'active': true, 'sort': 0},
        {'id': 'oat', 'name': 'Oat milk', 'price_delta': 6000, 'active': true, 'sort': 1},
        {'id': 'syrup', 'name': 'Sirup', 'price_delta': 3000, 'active': true, 'sort': 2},
        {'id': 'old', 'name': 'Lama', 'price_delta': 1000, 'active': false, 'sort': 3},
      ],
    },
  ],
};

void main() {
  final menu = Menu.fromJson(menuJson);
  final americano = menu.products.first;

  ModifierSelection select() => ModifierSelection(americano, menu.groupsFor(americano));
  MenuModifierGroup grp(String id) => menu.modifierGroups.firstWhere((g) => g.id == id);
  MenuModifier mod(String groupId, String id) => grp(groupId).modifiers.firstWhere((m) => m.id == id);

  group('MenuProduct: kode, modal, favorit', () {
    final p = MenuProduct.fromJson({
      'id': 'p', 'category_id': 'c', 'name': 'Air Mineral', 'price': 6000, 'active': true, 'sold_out': false,
      'sort': 0, 'modifier_group_ids': [], 'code': 'BB03', 'cost': 3000, 'favorite': true,
    });

    test('margin dari modal', () {
      expect(p.marginPercent, 50);
      expect(americano.marginPercent, isNull, reason: 'modal tidak dikirim (kasir) / belum diisi');
      expect(p.favorite, isTrue);
      expect(americano.favorite, isFalse);
    });

    test('cari nama atau kode tanpa beda huruf', () {
      expect(p.matches('mineral'), isTrue);
      expect(p.matches('bb03'), isTrue);
      expect(p.matches('  '), isTrue);
      expect(p.matches('latte'), isFalse);
    });
  });

  group('Menu.fromJson', () {
    test('memfilter kategori & produk nonaktif untuk kasir', () {
      expect(menu.activeCategories.map((c) => c.name), ['Kopi']);
      expect(menu.productsIn('c1').map((p) => p.name), ['Americano']);
      expect(menu.productsIn('c1', includeInactive: true), hasLength(2));
    });

    test('grup modifier mengikuti urutan produk', () {
      expect(menu.groupsFor(americano).map((g) => g.name), ['Suhu', 'Tambahan']);
    });

    test('fitur nama pelanggan & varian: default aktif, ikut pengaturan kedai', () {
      Menu withFeatures(Map<String, bool> f) => Menu.fromJson({...menuJson, 'features': f});

      expect(withFeatures({}).customerNameOn, isTrue, reason: 'server lama tanpa kunci = tetap wajib');
      expect(withFeatures({}).modifiersOn, isTrue);
      final off = withFeatures({'customer_name': false, 'modifiers': false});
      expect([off.customerNameOn, off.modifiersOn], [false, false]);
    });

    test('label kolom nama mengikuti cara jualan (default: dengan meja)', () {
      expect(Menu.fromJson(menuJson).customerLabelHint, 'Nama pelanggan / meja');
      expect(Menu.fromJson({...menuJson, 'customer_label_hint': 'Nama pelanggan'}).customerLabelHint, 'Nama pelanggan');
    });
  });

  group('ModifierSelection', () {
    test('grup wajib pilih-1 otomatis terisi pilihan pertama', () {
      final s = select();
      expect(s.chosen.map((m) => m.name), ['Hot']);
      expect(s.isValid, isTrue);
      expect(s.unitPrice, 13000);
    });

    test('grup wajib tidak bisa dikosongkan, hanya diganti', () {
      final s = select()
        ..toggle(grp('g1'), mod('g1', 'hot'))
        ..toggle(grp('g1'), mod('g1', 'cold'));
      expect(s.chosen.map((m) => m.name), ['Cold']);
      expect(s.unitPrice, 15000); // Americano Cold = 15.000, sama seperti di Kloa
    });

    test('grup maks 2 menolak pilihan ketiga', () {
      final s = select()
        ..toggle(grp('g3'), mod('g3', 'shot'))
        ..toggle(grp('g3'), mod('g3', 'oat'))
        ..toggle(grp('g3'), mod('g3', 'syrup'));
      expect(s.selectedIn(grp('g3')), ['shot', 'oat']);
      expect(s.unitPrice, 13000 + 5000 + 6000);
    });

    test('grup berjumlah: Extra shot x2, dibatasi maks. per opsi & total grup', () {
      final g = grp('g3');
      final shot = mod('g3', 'shot');
      final s = select()
        ..increment(g, shot)
        ..increment(g, shot);
      expect(s.count(g, shot), 2);
      expect(s.chosen.map((m) => m.id), ['hot', 'shot', 'shot'], reason: 'ID diulang = jumlah (format API)');
      expect(s.unitPrice, 13000 + 2 * 5000);
      expect(s.canIncrement(g, shot), isFalse, reason: 'maks. 2 per opsi');
      expect(s.canIncrement(g, mod('g3', 'oat')), isFalse, reason: 'total grup sudah 2');

      s.decrement(g, shot);
      expect(s.count(g, shot), 1);
      expect(s.canIncrement(g, mod('g3', 'oat')), isTrue);
      expect(g.rule, 'Opsional, maks 2 (total)');
    });

    test('ringkasan pilihan menggabungkan jumlah', () {
      final shot = mod('g3', 'shot');
      expect(modifierSummary([mod('g1', 'cold'), shot, shot]), 'Cold, Extra shot ×2');
      expect(modifierSummary([shot, shot], times: 'x'), 'Extra shot x2');
    });

    test('pilihan nonaktif tidak bisa dipilih', () {
      final s = select()..toggle(grp('g3'), mod('g3', 'old'));
      expect(s.selectedIn(grp('g3')), isEmpty);
    });

    test('grup wajib tanpa pilihan aktif membuat seleksi tidak valid', () {
      final g = MenuModifierGroup(id: 'gx', name: 'Ukuran', minSelect: 1, maxSelect: 1, modifiers: const []);
      final s = ModifierSelection(americano, [g]);
      expect(s.isValid, isFalse);
      expect(s.errorFor(g), 'Ukuran: wajib pilih 1');
    });
  });

  group('money', () {
    test('format & parse rupiah', () {
      expect(rupiah(1250000), '1.250.000');
      expect(rp(13000), 'Rp 13.000');
      expect(parseRupiah('Rp 13.000'), 13000);
      expect(parseRupiah('abc'), isNull);
    });
  });
}
