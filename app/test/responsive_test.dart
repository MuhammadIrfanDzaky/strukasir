// Uji tampilan responsif: setiap layar & dialog utama dirender di 12 ukuran layar
// (HP kecil/sedang/besar, tablet kecil/sedang/besar; portrait & landscape) dan gagal bila ada
// elemen yang meluber (RenderFlex overflow) atau error layout lain.
//
// Screenshot untuk dicek mata: SHOT_DIR=<folder> flutter test test/responsive_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:berrybrew_pos/core/api_client.dart';
import 'package:berrybrew_pos/core/theme/theme.dart';
import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/cart/payment_dialog.dart';
import 'package:berrybrew_pos/features/customers/credit_dialogs.dart';
import 'package:berrybrew_pos/features/customers/customer_api.dart';
import 'package:berrybrew_pos/features/customers/customer_form.dart';
import 'package:berrybrew_pos/features/customers/customers_screen.dart';
import 'package:berrybrew_pos/features/customers/member_tier.dart';
import 'package:berrybrew_pos/features/customers/messaging.dart';
import 'package:berrybrew_pos/features/customers/tier_settings_screen.dart';
import 'package:berrybrew_pos/features/history/history_screen.dart';
import 'package:berrybrew_pos/features/loyalty/loyalty_models.dart';
import 'package:berrybrew_pos/features/loyalty/loyalty_settings_screen.dart';
import 'package:berrybrew_pos/features/menu/menu_controller.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/menu_admin/menu_admin_screen.dart';
import 'package:berrybrew_pos/features/printing/printer_service.dart';
import 'package:berrybrew_pos/features/printing/printer_settings_screen.dart';
import 'package:berrybrew_pos/features/printing/receipt_logo.dart';
import 'package:berrybrew_pos/features/printing/receipt_settings_screen.dart';
import 'package:berrybrew_pos/features/printing/stations.dart';
import 'package:berrybrew_pos/features/printing/stations_screen.dart';
import 'package:berrybrew_pos/features/session/account_dialogs.dart';
import 'package:berrybrew_pos/features/session/login_screen.dart';
import 'package:berrybrew_pos/features/session/session_controller.dart';
import 'package:berrybrew_pos/features/session/setup_screen.dart';
import 'package:berrybrew_pos/features/session/signup_options.dart';
import 'package:berrybrew_pos/features/settings/feature_settings_screen.dart';
import 'package:berrybrew_pos/features/shift/cash_dialogs.dart';
import 'package:berrybrew_pos/features/shift/shift_controller.dart';
import 'package:berrybrew_pos/features/shift/shift_dialogs.dart';
import 'package:berrybrew_pos/home_shell.dart';
import 'package:berrybrew_pos/main.dart' show appBuilder;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'menu_test.dart' show menuJson;
import 'receipt_format_test.dart' show order;

const sizes = <String, Size>{
  'hp-kecil-portrait': Size(320, 568),
  'hp-kecil-landscape': Size(568, 320),
  'hp-portrait': Size(360, 780),
  'hp-landscape': Size(780, 360),
  'hp-besar-portrait': Size(430, 932),
  'hp-besar-landscape': Size(932, 430),
  'tablet-kecil-portrait': Size(600, 960),
  'tablet-kecil-landscape': Size(960, 600),
  'tablet-portrait': Size(800, 1280),
  'tablet-landscape': Size(1280, 800),
  'tablet-besar-portrait': Size(1024, 1366),
  'tablet-besar-landscape': Size(1366, 1024),
};

// ───────────────────────────── data palsu ─────────────────────────────

final device = DeviceInfo.fromJson({'id': 'd1', 'code': 'T1', 'name': 'Tablet Kasir', 'tenant_name': 'BerryBrew'});
const owner = SessionUser(id: 'u1', name: 'Rina Amelia', role: 'owner', permissions: {
  'reports.view', 'menu.manage', 'settings.manage', 'discount.within_limit', 'discount.over_limit', 'order.void',
  'customers.view', 'customers.manage',
});

/// Menu contoh + beberapa produk tambahan (nama panjang, habis) supaya grid terisi.
final bigMenu = Menu.fromJson({
  ...menuJson,
  'features': <String, dynamic>{...menuJson['features'] as Map<String, dynamic>, 'customers': true, 'loyalty': true, 'member_tiers': true, 'customer_credit': true, 'customer_messaging': true},
  'member_tiers': tiersJson,
  'loyalty': loyaltyJson,
  'categories': [
    ...menuJson['categories'] as List,
    {'id': 'c3', 'name': 'Non-kopi', 'sort': 2, 'active': true},
    {'id': 'c4', 'name': 'Makanan ringan', 'sort': 3, 'active': true},
  ],
  'products': [
    ...menuJson['products'] as List,
    for (final (i, name) in [
      'Kopi Susu Gula Aren', 'Es Kopi Susu Berry Spesial Ukuran Jumbo', 'Cappuccino', 'Caffè Latte',
      'Matcha Latte', 'Croissant Almond', 'Mixed Berry Yakult Soda', 'V60 Single Origin Gayo',
    ].indexed)
      {
        'id': 'x$i', 'category_id': 'c1', 'name': name, 'price': 18000 + i * 1500,
        'active': true, 'sold_out': i == 5, 'sort': 10 + i, 'modifier_group_ids': [],
        'code': 'BB${(i + 1).toString().padLeft(2, '0')}', 'cost': i.isEven ? 9000 + i * 500 : null, 'favorite': i < 3,
      },
  ],
});

final tiersJson = [
  {'id': 't1', 'name': 'Silver', 'threshold': 500000, 'discount_bp': 500, 'earn_multiplier': 1, 'color': 'silver'},
  {'id': 't2', 'name': 'Gold', 'threshold': 2000000, 'discount_bp': 1000, 'earn_multiplier': 2, 'color': 'gold'},
  {'id': 't3', 'name': 'Platinum Prioritas', 'threshold': 5000000, 'discount_bp': 1500, 'earn_multiplier': 3, 'color': 'platinum'},
];

final loyaltyJson = <String, dynamic>{
  'active': true, 'name': 'BerryCard', 'unit': 'stempel', 'earn_mode': 'per_item', 'category_ids': ['c1'],
  'earn_per_amount': null, 'earn_min_order': null, 'expiry_months': 6,
  'rewards': [
    {'id': 'r1', 'name': 'Potongan Rp 5.000', 'cost': 5, 'type': 'amount', 'product_id': null, 'value': 5000},
    {'id': 'r2', 'name': 'Gratis Kopi Susu Gula Aren', 'cost': 10, 'type': 'free_product', 'product_id': 'x0', 'value': 0},
    {'id': 'r3', 'name': 'Diskon ulang tahun 25%', 'cost': 20, 'type': 'percent', 'product_id': null, 'value': 2500},
  ],
};

final sampleLogo = () {
  final image = img.Image(width: 600, height: 300);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  img.fillCircle(image, x: 300, y: 150, radius: 110, color: img.ColorRgb8(230, 170, 60));
  return base64Encode(processLogo((img.encodePng(image), const LogoOptions()))!.png);
}();

final reportJson = {
  'sales': 12845000, 'cost': 6100000, 'gross_profit': 6745000, 'cost_missing_items': 12, 'orders': 412, 'average': 31177, 'discounts': 215000, 'service': 0, 'tax': 0,
  'voids': {'orders': 3, 'refunded': 87000},
  'expenses': {
    'total': 1250000,
    'by_category': [
      {'key': 'ingredients', 'label': 'Belanja bahan', 'total': 820000},
      {'key': 'operational', 'label': 'Operasional (gas, air, listrik)', 'total': 280000},
      {'key': 'wages', 'label': 'Gaji / upah harian', 'total': 150000},
    ],
    'withdrawals': 3000000,
  },
  'net_profit': 5495000,
  'by_method': {'cash': 7340000, 'debit': 1205000, 'qris': 4300000, 'credit': 640000},
  'by_cashier': [
    {'name': 'Rina Amelia', 'orders': 230, 'sales': 7200000},
    {'name': 'Budi Santoso', 'orders': 182, 'sales': 5645000},
  ],
  'top_products': [
    {'qty': 120, 'name': 'Kopi Susu Gula Aren', 'revenue': 2160000, 'profit': 1080000},
    {'qty': 96, 'name': 'Es Kopi Susu Berry Spesial Ukuran Jumbo', 'revenue': 2208000},
  ],
  'from': '2026-09-30',
  'to': '2026-10-06',
  'daily': [{'date': '2026-09-30', 'orders': 58, 'sales': 1787886}, {'date': '2026-10-01', 'orders': 60, 'sales': 1843164}, {'date': '2026-10-02', 'orders': 50, 'sales': 1565119}, {'date': '2026-10-03', 'orders': 51, 'sales': 1584965}, {'date': '2026-10-04', 'orders': 66, 'sales': 2029801}, {'date': '2026-10-05', 'orders': 77, 'sales': 2400255}, {'date': '2026-10-06', 'orders': 54, 'sales': 1656457}],
  'hourly': [{'hour': 0, 'orders': 0, 'sales': 0}, {'hour': 1, 'orders': 0, 'sales': 0}, {'hour': 2, 'orders': 0, 'sales': 0}, {'hour': 3, 'orders': 0, 'sales': 0}, {'hour': 4, 'orders': 0, 'sales': 0}, {'hour': 5, 'orders': 0, 'sales': 0}, {'hour': 6, 'orders': 0, 'sales': 0}, {'hour': 7, 'orders': 3, 'sales': 93000}, {'hour': 8, 'orders': 8, 'sales': 248000}, {'hour': 9, 'orders': 12, 'sales': 372000}, {'hour': 10, 'orders': 20, 'sales': 620000}, {'hour': 11, 'orders': 16, 'sales': 496000}, {'hour': 12, 'orders': 14, 'sales': 434000}, {'hour': 13, 'orders': 10, 'sales': 310000}, {'hour': 14, 'orders': 11, 'sales': 341000}, {'hour': 15, 'orders': 15, 'sales': 465000}, {'hour': 16, 'orders': 18, 'sales': 558000}, {'hour': 17, 'orders': 22, 'sales': 682000}, {'hour': 18, 'orders': 19, 'sales': 589000}, {'hour': 19, 'orders': 24, 'sales': 744000}, {'hour': 20, 'orders': 21, 'sales': 651000}, {'hour': 21, 'orders': 12, 'sales': 372000}, {'hour': 22, 'orders': 5, 'sales': 155000}, {'hour': 23, 'orders': 0, 'sales': 0}],
  'weekday': [{'day': 1, 'orders': 48, 'sales': 1488000}, {'day': 2, 'orders': 52, 'sales': 1612000}, {'day': 3, 'orders': 50, 'sales': 1550000}, {'day': 4, 'orders': 55, 'sales': 1705000}, {'day': 5, 'orders': 63, 'sales': 1953000}, {'day': 6, 'orders': 78, 'sales': 2418000}, {'day': 7, 'orders': 66, 'sales': 2046000}],
  'by_category': [
    {'name': 'Coffee', 'qty': 260, 'revenue': 7400000},
    {'name': 'Non Coffee', 'qty': 110, 'revenue': 3100000},
    {'name': 'Snacks', 'qty': 95, 'revenue': 1650000},
    {'name': 'Manual Brew', 'qty': 25, 'revenue': 695000},
  ],
  'credit': {
    'issued': 640000, 'repaid': 215000, 'outstanding': 1185000, 'debtors': 9,
    'top': [
      {'id': 'cu1', 'code': 'M0031', 'name': 'Pak Darmawan Siregar', 'balance': 385000},
      {'id': 'cu2', 'code': 'M0007', 'name': 'Bu Sari', 'balance': 120000},
    ],
  },
  'by_tier': [
    {'name': 'Gold', 'orders': 64, 'sales': 2480000, 'customers': 12, 'discount': 248000},
    {'name': 'Silver', 'orders': 41, 'sales': 1210000, 'customers': 19, 'discount': 60500},
  ],
  'loyalty': {
    'earned': 386, 'redeemed': 140,
    'rewards': [
      {'name': 'Gratis Kopi Susu Gula Aren', 'count': 9, 'discount': 162000},
      {'name': 'Potongan Rp 5.000', 'count': 10, 'discount': 50000},
    ],
  },
  'customers': {
    'orders': 151, 'sales': 5320000, 'active': 64, 'new': 12, 'returning': 52,
    'top': [
      {'id': 'cu1', 'code': 'M0007', 'name': 'Andi Saputra', 'orders': 9, 'sales': 412000},
      {'id': 'cu2', 'code': 'M0012', 'name': 'Siti Nurhaliza Putri Ramadhani', 'orders': 7, 'sales': 296000},
    ],
  },
  'previous': {'from': '2026-09-23', 'to': '2026-09-29', 'orders': 380, 'sales': 11900000, 'average': 31315, 'gross_profit': 6900000},
};

Map<String, dynamic> _f(String key, String label, String desc, {bool on = true, bool available = true, String? requires}) =>
    {'key': key, 'label': label, 'description': desc, 'available': available, 'enabled': on, 'requires': requires};

final featureSettingsJson = {
  'features': [
    _f('customer_name', 'Nama pelanggan / meja', 'Nama pelanggan / nomor meja wajib diisi di setiap order'),
    _f('open_bill', 'Open Bill (bayar nanti)', 'Simpan order dan bayar nanti (struk belum bayar)', requires: 'customer_name'),
    _f('modifiers', 'Varian produk', 'Varian & modifier produk (hot/cold, gula, extra shot)'),
    _f('discounts', 'Diskon', 'Diskon manual per item / per order', on: false),
    _f('tax_service', 'Pajak & service', 'Pajak dan service charge'),
    _f('split_payment', 'Bayar dengan beberapa metode', 'Satu order dibayar dengan beberapa metode', on: false, available: false),
    _f('customers', 'Pelanggan / member', 'Data pelanggan / member: cari & tautkan ke order, riwayat belanja, kelompok pelanggan'),
    _f('loyalty', 'Program loyalitas', 'Program loyalitas: stempel / poin dari belanja member, tukar hadiah', requires: 'customers'),
    _f('customer_messaging', 'Pesan WhatsApp', 'Pesan WhatsApp ke member: struk digital, ucapan ulang tahun, sapa pelanggan lama, pengingat kasbon', requires: 'customers'),
    _f('customer_credit', 'Kasbon (bayar nanti)', 'Kasbon / piutang member: bayar nanti dengan batas, pelunasan di kasir, laporan piutang', requires: 'customers'),
    _f('member_tiers', 'Tingkat member', 'Tingkat member (mis. Silver/Gold): naik otomatis dari belanja, diskon & pengali stempel', requires: 'customers'),
  ],
  'customer_phone_required': true,
  'credit_default_limit': 500000,
  'tax_percent': 10,
  'tax_inclusive': true,
  'service_inclusive': false,
  'service_percent': 5.5,
};

/// Pilihan form daftar (sebagian kecil dari data server).
final signupOptions = SignupOptions.fromJson({
  'sectors': [
    {
      'group': 'food',
      'label': 'Makanan & minuman',
      'items': [
        {'code': 'coffee_shop', 'label': 'Kafe & coffee shop', 'asks_sales_mode': true},
        {'code': 'street_food', 'label': 'Warung & gerobak makanan', 'asks_sales_mode': true},
      ],
    },
    {
      'group': 'service',
      'label': 'Jasa & pelayanan',
      'items': [
        {'code': 'laundry', 'label': 'Laundry', 'asks_sales_mode': false},
      ],
    },
    {
      'group': 'other',
      'label': 'Lainnya',
      'items': [
        {'code': 'other', 'label': 'Lainnya', 'asks_sales_mode': false},
      ],
    },
  ],
  'sales_modes': [
    {'code': 'takeaway', 'label': 'Bawa pulang saja'},
    {'code': 'dine_in', 'label': 'Makan di tempat'},
    {'code': 'mixed', 'label': 'Keduanya'},
  ],
  'regions': [
    {
      'code': '12',
      'name': 'Sumatera Utara',
      'regencies': [
        {'code': '12.71', 'name': 'Kota Medan'},
        {'code': '12.07', 'name': 'Kabupaten Deli Serdang'},
      ],
    },
    {
      'code': '31',
      'name': 'DKI Jakarta',
      'regencies': [
        {'code': '31.71', 'name': 'Kota Administrasi Jakarta Pusat'},
      ],
    },
  ],
});

/// Buka kolom pilihan [field], (opsional) ketik [search], lalu pilih [option].
Future<void> pick(WidgetTester t, String field, String option, {String? search}) async {
  await t.ensureVisible(find.text(field));
  await t.tap(find.text(field));
  await settle(t);
  if (search != null) {
    await t.enterText(find.byType(TextField).last, search);
    await settle(t);
  }
  await t.ensureVisible(find.text(option).last);
  await settle(t);
  await t.tap(find.text(option).last);
  await settle(t);
}

Map<String, dynamic> customerJson(int i, {bool full = true}) => {
      'id': 'cu$i',
      'code': 'M${(i + 1).toString().padLeft(4, '0')}',
      'name': const ['Andi Saputra', 'Siti Nurhaliza Putri Ramadhani', 'Budi', 'Wahyu Pratama'][i % 4],
      'phone': full ? '+6281234567${80 + i}' : '0812****67${80 + i}',
      'note': i == 1 ? 'Alergi susu sapi, ganti oat milk. Suka less sugar dan es dipisah.' : null,
      'visits': i == 3 ? 0 : 12 - i,
      'loyalty_balance': i == 3 ? 0 : 14 - i * 3,
      'tier': i == 3 ? null : {...tiersJson[i % 3], 'manual': i == 2},
      'credit_balance': i == 1 ? 185000 : 0,
      'credit_limit': 500000,
      'credit_limit_custom': i == 1,
      'loyalty_expires_at': i == 3 ? null : '2027-04-0${i + 1}T10:00:00Z',
      'last_visit_at': i == 3 ? null : '2026-10-0${i + 1}T10:00:00Z',
      if (full) ...{
        'birth_date': i == 0 ? '1990-05-01' : null,
        'total_spent': i == 3 ? 0 : 412000 - i * 50000,
        'first_visit_at': '2026-06-01T10:00:00Z',
        'created_at': '2026-06-01T10:00:00Z',
      },
    };

final customerDetailJson = {
  ...customerJson(1),
  'favorites': [
    {'name': 'Kopi Susu Gula Aren', 'qty': 14},
    {'name': 'Es Kopi Susu Berry Spesial Ukuran Jumbo', 'qty': 6},
  ],
  'credit_history': [
    {'id': 'h1', 'kind': 'charge', 'amount': 120000, 'method': null, 'label': 'T1-0040', 'reversed': false, 'created_at': '2026-10-05T08:00:00Z'},
    {'id': 'h2', 'kind': 'repayment', 'amount': 50000, 'method': 'cash', 'label': null, 'reversed': false, 'created_at': '2026-10-06T08:00:00Z'},
    {'id': 'h3', 'kind': 'repayment', 'amount': 20000, 'method': 'qris', 'label': null, 'reversed': true, 'created_at': '2026-10-07T08:00:00Z'},
    {'id': 'h4', 'kind': 'reversal', 'amount': 20000, 'method': 'qris', 'label': 'Salah pelanggan', 'reversed': false, 'created_at': '2026-10-07T09:00:00Z'},
  ],
  'tier_progress': {'basis': 'spend', 'window_months': 12, 'metric': 1250000,
    'next': {'name': 'Gold', 'threshold': 2000000, 'remaining': 750000}},
  'loyalty_entries': [
    {'kind': 'earn', 'units': 2, 'note': null, 'order_number': 'T1-0042', 'created_at': '2026-10-06T08:00:00Z'},
    {'kind': 'redeem', 'units': -10, 'note': 'Gratis Kopi Susu Gula Aren', 'order_number': 'T1-0031', 'created_at': '2026-10-01T08:00:00Z'},
    {'kind': 'adjust', 'units': 8, 'note': 'Pindahan kartu stempel kertas yang lama sekali', 'order_number': null, 'created_at': '2026-09-01T08:00:00Z'},
  ],
  'recent_orders': [
    {'id': 'o1', 'number': 'T1-0042', 'status': 'paid', 'grand_total': 51400, 'business_date': '2026-10-06'},
    {'id': 'o2', 'number': 'T2-0108', 'status': 'void', 'grand_total': 18000, 'business_date': '2026-10-02'},
  ],
};

/// Dio palsu: jawab per path tanpa jaringan.
Dio fakeDio() => Dio()
  ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    final path = o.path;
    if (path.startsWith('/shifts/current/cash-movements')) {
      return h.resolve(Response(requestOptions: o, statusCode: 200, data: {
        'data': [
          {'id': 'm1', 'kind': 'out', 'category': 'ingredients', 'category_label': 'Belanja bahan', 'amount': 25000,
            'note': 'Es batu 2 kantong & susu UHT 1 karton untuk stok sore', 'user': 'Budi Santoso', 'cancelled': false,
            'created_at': '2026-10-06T03:15:00Z'},
          {'id': 'm2', 'kind': 'in', 'category': 'float', 'category_label': 'Tambah modal / uang kecil', 'amount': 50000,
            'note': null, 'user': 'Rina Amelia', 'cancelled': true, 'created_at': '2026-10-06T02:00:00Z'},
        ],
        'categories': [
          for (final (kind, key, label) in const [
            ('out', 'ingredients', 'Belanja bahan'), ('out', 'operational', 'Operasional (gas, air, listrik)'),
            ('out', 'wages', 'Gaji / upah harian'), ('out', 'withdrawal', 'Setor ke owner'), ('out', 'other_out', 'Lainnya'),
            ('in', 'float', 'Tambah modal / uang kecil'), ('in', 'other_in', 'Lainnya'),
          ])
            {'kind': kind, 'key': key, 'label': label, 'expense': kind == 'out' && key != 'withdrawal'},
        ],
      }));
    }
    final data = path.startsWith('/settings/features')
        ? {'data': featureSettingsJson}
        : path.startsWith('/messages/audience')
        ? {'data': [
            {'id': 'cu1', 'code': 'M0001', 'name': 'Andi Saputra', 'birth_date': '1990-10-11', 'last_visit_at': '2026-08-20T10:00:00Z',
              'credit_balance': 185000, 'last_sent_at': null},
            {'id': 'cu2', 'code': 'M0012', 'name': 'Siti Nurhaliza Putri Ramadhani', 'birth_date': '1995-10-14',
              'last_visit_at': '2026-07-02T10:00:00Z', 'credit_balance': 45000, 'last_sent_at': '2026-10-08T10:00:00Z'},
          ]}
        : path.startsWith('/settings/messages')
        ? {'data': {
            'templates': [
              for (final (k, t, b) in const [
                ('receipt', 'Struk digital', 'Halo {nama}, terima kasih sudah belanja di {kedai}!\n\n{struk}\n\nSampai jumpa lagi'),
                ('birthday', 'Ucapan ulang tahun', 'Selamat ulang tahun, {nama}! Mampir ke {kedai} ya.'),
                ('winback', 'Sapa pelanggan lama', 'Halo {nama}, sudah lama tidak mampir ke {kedai}.'),
                ('credit_reminder', 'Pengingat kasbon', 'Halo {nama}, kasbon di {kedai} saat ini {sisa_kasbon}.'),
                ('greeting', 'Sapaan umum', 'Halo {nama}, salam dari {kedai}!'),
              ])
                {'key': k, 'title': t, 'body': b, 'default': b},
            ],
            'placeholders': ['{nama}', '{kedai}', '{kode}', '{tingkat}', '{stempel}', '{sisa_kasbon}', '{struk}', '{total}', '{nomor}'],
          }}
        : path.startsWith('/settings/tiers')
        ? {'data': {'basis': 'spend', 'window_months': 12, 'tiers': tiersJson}}
        : path.startsWith('/settings/loyalty')
        ? {'data': {'program': loyaltyJson, 'rewards': loyaltyJson['rewards']}}
        : path.startsWith('/customers/')
        ? {'data': customerDetailJson}
        : path.startsWith('/customers')
        ? {
            'data': [for (var i = 0; i < 4; i++) customerJson(i)],
            'meta': {
              'current_page': 1, 'last_page': 2, 'total': 64, 'phone_required': true,
              'segments': {'all': 64, 'new': 12, 'loyal': 9, 'lost': 21},
            },
          }
        : path.startsWith('/orders')
        ? {'data': [order(), order(status: 'open'), order(status: 'void')]}
        : path.startsWith('/reports')
            ? {'data': reportJson}
            : <String, dynamic>{'data': []};
    h.resolve(Response(requestOptions: o, statusCode: 200, data: data));
  }));

class FakeSession extends SessionController {
  FakeSession(this.initial);

  final Session initial;

  @override
  Future<Session> build() async => initial;

  @override
  Future<T> authed<T>(Future<T> Function(ApiClient api, String token) call) =>
      call(ApiClient(baseUrl: 'http://test', dio: fakeDio()), 'token');

  @override
  Future<String> sendSignupCode({required String serverUrl, required String email, String? ownerName}) async =>
      'Kode dikirim ke $email. Periksa juga folder spam.';
}

class FakeMenu extends MenuController {
  @override
  Future<MenuState> build() async => MenuState(bigMenu);
}

class FakeShift extends ShiftController {
  @override
  Future<Map<String, dynamic>?> build() async => {'opened_at': '2026-10-06T00:58:00Z'};
}

class FakeStations extends StationsController {
  @override
  Future<List<TicketStation>> build() async => const [
        TicketStation(name: 'Bar', categoryIds: ['c1', 'c3']),
        TicketStation(name: 'Dapur makanan', printerMac: 'AA:BB:CC:DD:EE:FF', printerName: 'Printer Dapur Panda 80mm', categoryIds: ['c4'], copies: 2),
      ];
}

class FakePrinter extends PrinterService {
  @override
  Future<SavedPrinter?> build() async => const SavedPrinter('00:11:22:33:44:55', 'iware 58mm');
}

// ───────────────────────────── skenario ─────────────────────────────

typedef Scenario = ({
  String name,
  Session session,
  Widget Function(Session s) home,
  bool fillCart,
  Future<void> Function(WidgetTester t)? act,
});

SessionUser get unverifiedOwner => SessionUser(
    id: owner.id, name: owner.name, role: owner.role, permissions: owner.permissions,
    email: 'rina@contoh.id', emailVerified: false);

LoggedIn get loggedIn => LoggedIn('http://test', device, owner, 'token');

/// Tampilkan [dialog] di atas layar kosong (dialog yang dibuka dari dalam alur).
Widget dialogHost(Widget dialog) => Builder(builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(context: context, builder: (_) => dialog);
      });
      return const Scaffold(body: SizedBox.expand());
    });

Widget home(Session s, [int tab = 0]) => HomeShell(session: s as LoggedIn, initialIndex: tab);

final scenarios = <Scenario>[
  (name: 'setup', session: const NeedsSetup(), home: (_) => const SetupScreen(), fillCart: false, act: null),
  (
    name: 'daftar-usaha',
    session: const NeedsSetup(),
    home: (_) => const SetupScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Daftar usaha baru'));
      await settle(t);
      await t.ensureVisible(find.text('Lanjut'));
      await t.tap(find.text('Lanjut')); // tampilkan semua pesan validasi
      await settle(t);
    },
  ),
  (
    name: 'daftar-akun',
    session: const NeedsSetup(),
    home: (_) => const SetupScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Daftar usaha baru'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Alamat server (development)'), 'http://test');
      await t.enterText(find.widgetWithText(TextFormField, 'Nama usaha'), 'Kopi Senja');
      await pick(t, 'Jenis usaha', 'Warung & gerobak makanan');
      await t.ensureVisible(find.text('Keduanya'));
      await t.tap(find.text('Keduanya'));
      await pick(t, 'Provinsi', 'Sumatera Utara');
      await pick(t, 'Kota / kabupaten', 'Kota Medan');
      await t.ensureVisible(find.text('Lanjut'));
      await t.tap(find.text('Lanjut'));
      await settle(t);
      expect(find.text('Akun owner'), findsOneWidget);
      await t.ensureVisible(find.text('Kirim kode verifikasi'));
      await t.tap(find.text('Kirim kode verifikasi')); // tampilkan semua pesan validasi
      await settle(t);
    },
  ),
  (
    name: 'daftar-verifikasi-email',
    session: const NeedsSetup(),
    home: (_) => const SetupScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Daftar usaha baru'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Alamat server (development)'), 'http://test');
      await t.enterText(find.widgetWithText(TextFormField, 'Nama usaha'), 'Laundry Bersih');
      await pick(t, 'Jenis usaha', 'Laundry');
      await pick(t, 'Provinsi', 'Sumatera Utara');
      await pick(t, 'Kota / kabupaten', 'Kota Medan');
      await t.ensureVisible(find.text('Lanjut'));
      await t.tap(find.text('Lanjut'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Nama Anda'), 'Wahyu');
      await t.enterText(find.widgetWithText(TextFormField, 'Email'), 'wahyu@contoh.id');
      await t.enterText(find.widgetWithText(TextFormField, 'Password'), 'rahasia123');
      await t.enterText(find.widgetWithText(TextFormField, 'PIN kasir (6 digit)'), '482915');
      await t.enterText(find.widgetWithText(TextFormField, 'Ulangi PIN'), '482915');
      await t.ensureVisible(find.byType(Checkbox));
      await settle(t);
      await t.tap(find.byType(Checkbox));
      await t.ensureVisible(find.text('Kirim kode verifikasi'));
      await t.tap(find.text('Kirim kode verifikasi'));
      await settle(t);
      expect(find.text('Verifikasi email'), findsOneWidget);
    },
  ),
  (
    name: 'daftar-pilih-jenis-usaha',
    session: const NeedsSetup(),
    home: (_) => const SetupScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Daftar usaha baru'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Alamat server (development)'), 'http://test');
      await t.ensureVisible(find.text('Jenis usaha'));
      await t.tap(find.text('Jenis usaha'));
      await settle(t);
    },
  ),
  (
    name: 'daftar-lainnya',
    session: const NeedsSetup(),
    home: (_) => const SetupScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Daftar usaha baru'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextFormField, 'Alamat server (development)'), 'http://test');
      await pick(t, 'Jenis usaha', 'Lainnya', search: 'lain');
      expect(find.text('Sebutkan bidang usaha'), findsOneWidget);
      expect(find.text('Cara berjualan'), findsNothing, reason: 'hanya usaha makanan & minuman');
    },
  ),
  (
    name: 'kasir-verifikasi-email',
    session: LoggedIn('http://test', device, unverifiedOwner, 'token'),
    home: home,
    fillCart: false,
    act: null,
  ),
  (
    name: 'dialog-lupa-password',
    session: const NeedsSetup(),
    home: (_) => dialogHost(const ForgotPasswordDialog(serverUrl: 'http://test', email: 'rina@contoh.id')),
    fillCart: false,
    act: null,
  ),
  (
    name: 'dialog-verifikasi-email',
    session: LoggedIn('http://test', device, unverifiedOwner, 'token'),
    home: (_) => dialogHost(const VerifyEmailDialog(email: 'rina@contoh.id')),
    fillCart: false,
    act: null,
  ),
  (
    name: 'masuk-owner',
    session: const NeedsSetup(),
    home: (_) => const SetupScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Sudah punya akun? Masuk'));
      await settle(t);
    },
  ),
  (
    name: 'login',
    session: NeedsLogin('http://test', device),
    home: (s) => LoginScreen(session: s as NeedsLogin),
    fillCart: false,
    act: null,
  ),
  (
    name: 'dialog-pin-keluarkan-tablet',
    session: NeedsLogin('http://test', device),
    home: (_) => dialogHost(const PinDialog(member: StaffMember('u1', 'Rina Amelia', 'owner'), unregister: true)),
    fillCart: false,
    act: null,
  ),
  (
    name: 'login-pin',
    session: NeedsLogin('http://test', device),
    home: (s) => LoginScreen(session: s as NeedsLogin),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Budi Santoso'));
      await settle(t);
    },
  ),
  (name: 'kasir-kosong', session: loggedIn, home: home, fillCart: false, act: null),
  (name: 'kasir-isi', session: loggedIn, home: home, fillCart: true, act: null),
  (
    name: 'kasir-halaman-pesanan',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isEmpty) return; // layar lebar: keranjang sudah tampil di samping/bawah
      await t.tap(open);
      await settle(t);
    },
  ),
  (
    name: 'kasir-modifier',
    session: loggedIn,
    home: home,
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Americano'));
      await settle(t);
    },
  ),
  (
    name: 'dialog-bayar',
    session: loggedIn,
    home: (_) => dialogHost(const PaymentDialog(total: 51400, splitEnabled: true, number: 'T1-0042')),
    fillCart: false,
    act: null,
  ),
  (
    name: 'dialog-bayar-split',
    session: loggedIn,
    home: (_) => dialogHost(const PaymentDialog(total: 51400, splitEnabled: true, number: 'T1-0042')),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Bagi ke metode lain'));
      await settle(t);
    },
  ),
  (
    name: 'dialog-bayar-kasbon',
    session: loggedIn,
    home: (_) => dialogHost(const PaymentDialog(
          total: 51400,
          splitEnabled: true,
          number: 'T1-0042',
          creditCustomer: CartCustomer(id: 'cu1', code: 'M0031', name: 'Pak Darmawan Siregar', creditBalance: 470000, creditLimit: 500000),
        )),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Kasbon'));
      await settle(t);
    },
  ),
  (
    name: 'dialog-pelunasan-kasbon',
    session: loggedIn,
    home: (_) => Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showRepayDialog(context, customerId: 'cu1', name: 'Pak Darmawan Siregar', balance: 185000);
          });
          return const Scaffold(body: SizedBox.expand());
        }),
    fillCart: false,
    act: null,
  ),
  (name: 'pesan-wa-daftar', session: loggedIn, home: (_) => const MessagingScreen(creditOn: true), fillCart: false, act: null),
  (name: 'pesan-wa-template', session: loggedIn, home: (_) => const MessageTemplatesScreen(), fillCart: false, act: null),
  (
    name: 'riwayat-detail-member',
    session: loggedIn,
    home: (_) => dialogHost(OrderDetailDialog(order: {
          ...order(),
          'customer': {'id': 'cu1', 'code': 'M0001', 'name': 'Andi', 'anonymized': false},
        })),
    fillCart: false,
    act: (t) async => expect(find.text('Struk via WA'), findsOneWidget),
  ),
  (
    name: 'shift-menu',
    session: loggedIn,
    home: home,
    fillCart: false,
    act: (t) async {
      await t.tap(find.textContaining('Shift'));
      await settle(t);
      expect(find.text('Kas keluar'), findsOneWidget);
    },
  ),
  (
    name: 'kas-keluar',
    session: loggedIn,
    home: (_) => Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) => showCashDialog(context, kind: 'out'));
          return const Scaffold(body: SizedBox.expand());
        }),
    fillCart: false,
    act: null,
  ),
  (
    name: 'kas-daftar',
    session: loggedIn,
    home: (_) => Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) => showCashListDialog(context));
          return const Scaffold(body: SizedBox.expand());
        }),
    fillCart: false,
    act: null,
  ),
  (
    name: 'unduh-laporan',
    session: loggedIn,
    home: (s) => home(s, 2),
    fillCart: false,
    act: (t) async {
      await t.tap(find.byTooltip('Unduh CSV / Excel'));
      await settle(t);
      expect(find.text('Rekap pajak (PB1) per hari'), findsOneWidget);
    },
  ),
  (
    name: 'shift-ditutup',
    session: loggedIn,
    home: (_) => dialogHost(const ShiftResultDialog(shift: {
          'id': 's1', 'opened_at': '2026-10-06T00:58:00Z', 'closed_at': '2026-10-06T14:00:00Z', 'opened_by': 'Budi', 'closed_by': 'Budi',
          'expected_cash': 1225000, 'counted_cash': 1220000, 'difference': -5000, 'note': null,
          'summary': {
            'opening_cash': 200000, 'cash_in': 1100000, 'cash_refund': 0, 'cash_extra_in': 50000, 'cash_out': 125000,
            'credit_repaid_cash': 0, 'by_method': {'cash': 1100000, 'debit': 150000, 'qris': 640000, 'credit': 45000},
            'paid_orders': 58, 'refunds': 1,
          },
        })),
    fillCart: false,
    act: null,
  ),
  (name: 'tiket-stasiun', session: loggedIn, home: (_) => const StationsScreen(), fillCart: false, act: null),
  (
    name: 'tiket-form',
    session: loggedIn,
    home: (_) => const StationsScreen(),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('Dapur makanan'));
      await settle(t);
      expect(find.text('Ubah stasiun'), findsOneWidget);
    },
  ),
  (name: 'riwayat', session: loggedIn, home: (s) => home(s, 1), fillCart: false, act: null),
  (
    name: 'riwayat-detail',
    session: loggedIn,
    home: (_) => dialogHost(OrderDetailDialog(order: order())),
    fillCart: false,
    act: null,
  ),
  (name: 'laporan', session: loggedIn, home: (s) => home(s, 2), fillCart: false, act: null),
  (
    name: 'dashboard-7-hari',
    session: loggedIn,
    home: (s) => home(s, 2),
    fillCart: false,
    act: (t) async {
      await t.tap(find.text('7 hari'));
      await settle(t);
      await t.scrollUntilVisible(find.text('Program loyalitas'), 300, scrollable: find.byType(Scrollable).last);
      await settle(t);
    },
  ),
  (name: 'kelola-menu', session: loggedIn, home: (s) => home(s, 3), fillCart: false, act: null),
  (
    name: 'form-produk',
    session: loggedIn,
    home: (_) => dialogHost(ProductForm(menu: bigMenu, product: bigMenu.products.first)),
    fillCart: false,
    act: null,
  ),
  (
    name: 'form-grup-pilihan',
    session: loggedIn,
    home: (_) => dialogHost(ModifierGroupForm(group: bigMenu.modifierGroups.last)),
    fillCart: false,
    act: null,
  ),
  // Tab terakhir: di HP (6 tab untuk owner) Pengaturan dibuka dari menu akun sebagai halaman sendiri.
  (name: 'printer', session: loggedIn, home: (s) => home(s, 99), fillCart: false, act: null),
  (
    name: 'printer-halaman',
    session: loggedIn,
    home: (_) => Scaffold(appBar: AppBar(title: const Text('Pengaturan')), body: const PrinterSettingsScreen()),
    fillCart: false,
    act: null,
  ),
  (name: 'pelanggan', session: loggedIn, home: (s) => home(s, 4), fillCart: false, act: null),
  (name: 'loyalitas-pengaturan', session: loggedIn, home: (_) => const LoyaltySettingsScreen(), fillCart: false, act: null),
  (name: 'tingkat-pengaturan', session: loggedIn, home: (_) => const TierSettingsScreen(), fillCart: false, act: null),
  (
    name: 'tingkat-form',
    session: loggedIn,
    home: (_) => const TierSettingsScreen(),
    fillCart: false,
    act: (t) async {
      await t.ensureVisible(find.text('Platinum Prioritas'));
      await settle(t);
      await t.tap(find.text('Platinum Prioritas'));
      await settle(t);
      expect(find.text('Ubah tingkat'), findsOneWidget);
    },
  ),
  (
    name: 'kasir-member-gold',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final container = ProviderScope.containerOf(t.element(find.byType(HomeShell)));
      container.read(cartProvider.notifier).setCustomer(CartCustomer(
          id: 'cu1', code: 'M0002', name: 'Siti Nurhaliza Putri Ramadhani', visits: 11, balance: 12,
          tier: MemberTier.fromJson(tiersJson[2])));
      await settle(t);
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isNotEmpty) {
        await t.tap(open);
        await settle(t);
      }
    },
  ),
  (
    name: 'loyalitas-form-hadiah',
    session: loggedIn,
    home: (_) => const LoyaltySettingsScreen(),
    fillCart: false,
    act: (t) async {
      await t.ensureVisible(find.text('Tambah').first);
      await settle(t);
      await t.tap(find.text('Tambah').first);
      await settle(t);
      expect(find.text('Tambah hadiah'), findsOneWidget);
    },
  ),
  (
    name: 'kasir-tukar-hadiah',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final container = ProviderScope.containerOf(t.element(find.byType(HomeShell)));
      container.read(cartProvider.notifier).setCustomer(
          const CartCustomer(id: 'cu1', code: 'M0002', name: 'Siti Nurhaliza Putri Ramadhani', visits: 11, balance: 12));
      await settle(t);
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isNotEmpty) {
        await t.tap(open);
        await settle(t);
      }
      // Layar sangat pendek: tombol bisa di luar area yang sudah dibangun daftar keranjang.
      if (find.text('Tukar hadiah').evaluate().isEmpty) {
        final list = find.ancestor(of: find.text('Order baru'), matching: find.byType(Scrollable)).first;
        await t.scrollUntilVisible(find.text('Tukar hadiah'), 40, scrollable: list);
      }
      await t.ensureVisible(find.text('Tukar hadiah').last);
      await settle(t);
      await t.tap(find.text('Tukar hadiah').last);
      await settle(t);
      expect(find.text('Kurang 8 stempel'), findsNothing);
    },
  ),
  (
    name: 'kasir-hadiah-aktif',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final container = ProviderScope.containerOf(t.element(find.byType(HomeShell)));
      final cart = container.read(cartProvider.notifier);
      cart.setCustomer(const CartCustomer(id: 'cu1', code: 'M0002', name: 'Siti Nurhaliza Putri Ramadhani', visits: 11, balance: 12));
      cart.setReward(LoyaltyReward.fromJson(loyaltyJson['rewards'][0] as Map<String, dynamic>));
      await settle(t);
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isNotEmpty) {
        await t.tap(open);
        await settle(t);
      }
    },
  ),
  (
    name: 'pelanggan-detail',
    session: loggedIn,
    home: (_) => const CustomerDetailScreen(customerId: 'cu1', phoneRequired: true),
    fillCart: false,
    act: null,
  ),
  (
    name: 'form-pelanggan',
    session: loggedIn,
    home: (_) => dialogHost(CustomerFormDialog(customer: Customer.fromJson(customerJson(0)), phoneRequired: true, full: true)),
    fillCart: false,
    act: null,
  ),
  (
    name: 'kasir-pilih-member',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isNotEmpty) {
        await t.tap(open);
        await settle(t);
      }
      await t.ensureVisible(find.byTooltip('Pilih member').last);
      await t.tap(find.byTooltip('Pilih member').last);
      await settle(t);
      expect(find.text('Pelanggan baru'), findsOneWidget);
    },
  ),
  (
    name: 'kasir-member-tertaut',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final container = ProviderScope.containerOf(t.element(find.byType(HomeShell)));
      container.read(cartProvider.notifier).setCustomer(const CartCustomer(
          id: 'cu1', code: 'M0002', name: 'Siti Nurhaliza Putri Ramadhani', visits: 11,
          note: 'Alergi susu sapi, ganti oat milk. Suka less sugar dan es dipisah.'));
      await settle(t);
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isNotEmpty) {
        await t.tap(open);
        await settle(t);
      }
    },
  ),
  (
    name: 'kasir-cek-pesanan',
    session: loggedIn,
    home: home,
    fillCart: true,
    act: (t) async {
      final open = find.text('Lihat pesanan');
      if (open.evaluate().isNotEmpty) {
        await t.tap(open);
        await settle(t);
      }
      await t.tap(find.text('Cek pesanan'));
      await settle(t);
    },
  ),
  (
    name: 'kasir-cari',
    session: loggedIn,
    home: home,
    fillCart: false,
    act: (t) async {
      await t.tap(find.byTooltip('Cari produk'));
      await settle(t);
      await t.enterText(find.widgetWithText(TextField, 'Cari nama atau kode produk'), 'bb0');
      await settle(t);
    },
  ),
  (
    name: 'import-format',
    session: loggedIn,
    home: (s) => home(s, 3),
    fillCart: false,
    act: (t) async {
      final button = find.text('Import CSV');
      await t.tap(button.evaluate().isNotEmpty ? button : find.byTooltip('Import CSV'));
      await settle(t);
    },
  ),
  (name: 'pengaturan-fitur', session: loggedIn, home: (_) => const FeatureSettingsScreen(), fillCart: false, act: null),
  (
    name: 'pengaturan-struk',
    session: loggedIn,
    home: (_) => ReceiptSettingsScreen(
          current: ReceiptSettings(
            name: 'BERRYBREW KOPI',
            header: 'Jl Garu 2 A No. 5 C Harjosari 1\nMedan Amplas',
            footer: 'Terima Kasih atas Kunjungan Anda, dengan senang hati melayani dan menanti kunjungan Anda berikutnya',
            logoBase64: sampleLogo,
          ),
        ),
    fillCart: false,
    act: null,
  ),
];

// ───────────────────────────── harness ─────────────────────────────

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final file = File(p);
    if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  final shotDir = Platform.environment['SHOT_DIR'];

  setUpAll(() async {
    // Font asli supaya lebar teks sama dengan di perangkat (font uji bawaan jauh lebih lebar).
    await loadFont('PlusJakartaSans', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/PlusJakartaSans-$w.ttf',
    ]);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
      await loadFont('MaterialIcons', ['$fonts/materialicons-regular.otf', '$fonts/MaterialIcons-Regular.otf']);
      await loadFont('Roboto', ['$fonts/roboto-regular.ttf', '$fonts/Roboto-Regular.ttf']);
    }
    // Pratinjau struk memakai font monospace sistem; di Windows pakai Consolas (bila ada).
    await loadFont('monospace', ['C:/Windows/Fonts/consola.ttf', 'C:/Windows/Fonts/consolab.ttf']);
  });

  // Skala font: normal dan terbesar Android (app membatasinya jadi 1.2×).
  for (final textScale in const [1.0, 1.3]) {
  for (final sc in scenarios) {
    for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
      testWidgets('${sc.name} @ $sizeName · font ${textScale}x', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);

        final boundary = GlobalKey();
        final container = ProviderContainer(overrides: [
          sessionProvider.overrideWith(() => FakeSession(sc.session)),
          menuProvider.overrideWith(FakeMenu.new),
          shiftProvider.overrideWith(FakeShift.new),
          printerProvider.overrideWith(FakePrinter.new),
          stationsProvider.overrideWith(FakeStations.new),
          signupOptionsLoaderProvider.overrideWithValue((_) async => signupOptions),
          staffProvider.overrideWith((ref) async => const [
                StaffMember('u1', 'Rina Amelia', 'owner'),
                StaffMember('u2', 'Budi Santoso', 'cashier'),
                StaffMember('u3', 'Siti Nurhaliza Putri', 'cashier'),
              ]),
        ]);
        addTearDown(container.dispose);
        await container.read(sessionProvider.future);
        if (sc.fillCart) {
          await container.read(menuProvider.future);
          final cart = container.read(cartProvider.notifier);
          for (final p in bigMenu.products.where((p) => p.sellable && p.modifierGroupIds.isEmpty).take(4)) {
            cart.add(ModifierSelection(p, const []));
          }
          cart.setCustomerLabel('Wahyu');
        }

        await t.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Builder(builder: (context) => appBuilder(context, child)),
              ),
              home: sc.home(sc.session),
            ),
          ),
        ));
        await settle(t);
        await sc.act?.call(t);
        // Image.memory (logo) di-decode secara async sungguhan.
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await settle(t);

        if (shotDir != null) {
          await t.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await render.toImage();
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$shotDir/${sc.name}__$sizeName${textScale == 1 ? '' : '__font$textScale'}.png')..createSync(recursive: true);
            file.writeAsBytesSync(png!.buffer.asUint8List());
          });
        }

        expect(t.takeException(), isNull, reason: '${sc.name} @ $sizeName ($size) font ${textScale}x');
      });
    }
  }
  }
}
