import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/theme.dart';
import 'core/ui/components.dart';
import 'features/cart/cart_controller.dart';
import 'features/menu/menu_controller.dart';
import 'features/session/login_screen.dart';
import 'features/session/session_controller.dart';
import 'features/session/setup_screen.dart';
import 'features/shift/shift_controller.dart';
import 'features/update/version_gate.dart';
import 'home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tablet kasir dipakai mendatar.
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const ProviderScope(child: StrukasirApp()));
}

class StrukasirApp extends StatelessWidget {
  const StrukasirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Strukasir',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const VersionGate(child: SessionGate()),
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

    return ref.watch(sessionProvider).when(
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
