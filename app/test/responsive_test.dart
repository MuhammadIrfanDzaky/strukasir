// Uji tampilan responsif: setiap layar & dialog utama dirender di 12 ukuran layar
// (HP kecil/sedang/besar, tablet kecil/sedang/besar; portrait & landscape) dan gagal bila ada
// elemen yang meluber (RenderFlex overflow) atau error layout lain.
//
// Screenshot untuk dicek mata: SHOT_DIR=<folder> flutter test test/responsive_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:berrybrew_pos/core/api_client.dart';
import 'package:berrybrew_pos/core/theme/theme.dart';
import 'package:berrybrew_pos/features/cart/cart_controller.dart';
import 'package:berrybrew_pos/features/cart/payment_dialog.dart';
import 'package:berrybrew_pos/features/history/history_screen.dart';
import 'package:berrybrew_pos/features/menu/menu_controller.dart';
import 'package:berrybrew_pos/features/menu/menu_models.dart';
import 'package:berrybrew_pos/features/menu/modifier_selection.dart';
import 'package:berrybrew_pos/features/menu_admin/menu_admin_screen.dart';
import 'package:berrybrew_pos/features/printing/printer_service.dart';
import 'package:berrybrew_pos/features/session/login_screen.dart';
import 'package:berrybrew_pos/features/session/session_controller.dart';
import 'package:berrybrew_pos/features/session/setup_screen.dart';
import 'package:berrybrew_pos/features/shift/shift_controller.dart';
import 'package:berrybrew_pos/home_shell.dart';
import 'package:berrybrew_pos/main.dart' show appBuilder;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  'reports.view', 'menu.manage', 'discount.within_limit', 'discount.over_limit', 'order.void',
});

/// Menu contoh + beberapa produk tambahan (nama panjang, habis) supaya grid terisi.
final bigMenu = Menu.fromJson({
  ...menuJson,
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
      },
  ],
});

final reportJson = {
  'sales': 12845000, 'orders': 412, 'average': 31177, 'discounts': 215000, 'service': 0, 'tax': 0,
  'voids': {'orders': 3, 'refunded': 87000},
  'by_method': {'cash': 7340000, 'debit': 1205000, 'qris': 4300000},
  'by_cashier': [
    {'name': 'Rina Amelia', 'orders': 230, 'sales': 7200000},
    {'name': 'Budi Santoso', 'orders': 182, 'sales': 5645000},
  ],
  'top_products': [
    {'qty': 120, 'name': 'Kopi Susu Gula Aren', 'revenue': 2160000},
    {'qty': 96, 'name': 'Es Kopi Susu Berry Spesial Ukuran Jumbo', 'revenue': 2208000},
  ],
  'daily': [
    {'date': '2026-10-05', 'orders': 60, 'sales': 1900000},
    {'date': '2026-10-06', 'orders': 58, 'sales': 1820000},
  ],
};

/// Dio palsu: jawab per path tanpa jaringan.
Dio fakeDio() => Dio()
  ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
    final path = o.path;
    final data = path.startsWith('/orders')
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
}

class FakeMenu extends MenuController {
  @override
  Future<MenuState> build() async => MenuState(bigMenu);
}

class FakeShift extends ShiftController {
  @override
  Future<Map<String, dynamic>?> build() async => {'opened_at': '2026-10-06T00:58:00Z'};
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
    name: 'login',
    session: NeedsLogin('http://test', device),
    home: (s) => LoginScreen(session: s as NeedsLogin),
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
  (name: 'riwayat', session: loggedIn, home: (s) => home(s, 1), fillCart: false, act: null),
  (
    name: 'riwayat-detail',
    session: loggedIn,
    home: (_) => dialogHost(OrderDetailDialog(order: order())),
    fillCart: false,
    act: null,
  ),
  (name: 'laporan', session: loggedIn, home: (s) => home(s, 2), fillCart: false, act: null),
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
  (name: 'printer', session: loggedIn, home: (s) => home(s, 4), fillCart: false, act: null),
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
