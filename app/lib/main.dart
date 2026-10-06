import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'core/ui/components.dart';
import 'core/ui/responsive.dart';
import 'features/cart/cart_controller.dart';
import 'features/menu/menu_controller.dart';
import 'features/session/login_screen.dart';
import 'features/session/session_controller.dart';
import 'features/session/setup_screen.dart';
import 'features/shift/shift_controller.dart';
import 'features/update/version_gate.dart';
import 'home_shell.dart';

/// DSN pelacak error, diisi saat build rilis: `--dart-define=SENTRY_DSN=...`. Kosong = nonaktif.
const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Semua orientasi: tablet & HP, portrait maupun landscape.
  void run() => runApp(const ProviderScope(child: StrukasirApp()));
  if (_sentryDsn.isEmpty) return run();

  await SentryFlutter.init((o) {
    o.dsn = _sentryDsn;
    o.environment = const String.fromEnvironment('SENTRY_ENV', defaultValue: 'production');
    // Privasi: tanpa data pribadi & tanpa screenshot (bisa memuat nama & nominal); hierarki layar default mati.
    o.sendDefaultPii = false;
    o.attachScreenshot = false;
    o.tracesSampleRate = 0;
  }, appRunner: run);
}

class StrukasirApp extends StatelessWidget {
  const StrukasirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Strukasir',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: appBuilder,
      home: const VersionGate(child: SessionGate()),
    );
  }
}

/// Pembungkus semua layar: font sistem tetap dihormati tapi dibatasi 1.2× supaya layar kasir
/// tidak pecah, dan margin dialog mengikuti ukuran layar.
Widget appBuilder(BuildContext context, Widget? child) =>
    MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2, child: ResponsiveDialogs(child: child!));

/// Margin dialog mengikuti layar: di HP lebih rapat supaya isi dialog tidak sesak.
class ResponsiveDialogs extends StatelessWidget {
  const ResponsiveDialogs({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        dialogTheme: theme.dialogTheme.copyWith(
          insetPadding: EdgeInsets.symmetric(
            horizontal: context.isCompact ? AppSpace.s4 : AppSpace.s10,
            vertical: context.isShort ? AppSpace.s3 : AppSpace.s6,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Memilih layar berdasarkan status sesi: daftar tablet → login PIN → aplikasi.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sesi user berganti (login/logout) → menu dimuat ulang untuk user tersebut.
    ref.listen(sessionProvider, (prev, next) {
      if (prev?.value is! LoggedIn && next.value is LoggedIn) {
        ref.invalidate(menuProvider);
        ref.invalidate(shiftProvider);
      }
      // Kasir keluar → keranjang yang belum selesai tidak diwariskan ke kasir berikutnya.
      if (prev?.value is LoggedIn && next.value is! LoggedIn) ref.invalidate(cartProvider);
    });

    return ref
        .watch(sessionProvider)
        .when(
          loading: () => const Scaffold(body: Center(child: BrandMark(size: 72))),
          error: (e, _) => Scaffold(
            body: AppErrorState(
              title: 'Gagal membaca sesi',
              message: '$e',
              onRetry: () => ref.invalidate(sessionProvider),
            ),
          ),
          data: (session) => switch (session) {
            NeedsSetup() => const SetupScreen(),
            NeedsLogin() => LoginScreen(session: session),
            LoggedIn() => HomeShell(key: ValueKey(session.user.id), session: session),
          },
        );
  }
}
