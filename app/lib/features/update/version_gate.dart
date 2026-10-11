import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../session/session_controller.dart';

/// Bandingkan versi semantik "1.2.3" (bagian build "+4" diabaikan). <0 jika a lebih lama dari b.
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final nums = v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    return [for (var i = 0; i < 3; i++) i < nums.length ? nums[i] : 0];
  }

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = pa[i].compareTo(pb[i]);
    if (d != 0) return d;
  }
  return 0;
}

class UpdateInfo {
  const UpdateInfo({required this.current, required this.minVersion, this.downloadUrl});

  final String current;
  final String minVersion;
  final String? downloadUrl;

  bool get mustUpdate => compareVersions(current, minVersion) < 0;
}

/// Dicek sekali per alamat server. Gagal (offline) → tidak memblokir; kasir tetap bisa berjualan.
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  final serverUrl = switch (ref.watch(sessionProvider).value) {
    NeedsLogin(:final serverUrl) || LoggedIn(:final serverUrl) => serverUrl,
    _ => null,
  };
  if (serverUrl == null) return null;

  try {
    final res = await ApiClient(baseUrl: serverUrl).get('/app/version');
    final info = await PackageInfo.fromPlatform();
    final url = res['download_url'] as String?;
    return UpdateInfo(
      current: info.version,
      minVersion: res['min_version'] as String? ?? '0.0.0',
      downloadUrl: (url?.isEmpty ?? true) ? null : url,
    );
  } on ApiException {
    return null;
  }
});

/// Membungkus aplikasi: versi di bawah minimum → layar "Perbarui aplikasi".
class VersionGate extends ConsumerWidget {
  const VersionGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateInfoProvider).value;
    if (info == null || !info.mustUpdate) return child;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(size: 72),
            const SizedBox(height: AppSpace.s5),
            Text('Perbarui aplikasi', style: AppType.headline),
            const SizedBox(height: AppSpace.s2),
            Text(
                'Versi terpasang ${info.current}. Minimal versi ${info.minVersion} agar data tetap aman '
                'dan sesuai server.',
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpace.s6),
            if (info.downloadUrl != null)
              FilledButton(onPressed: () => launchUrl(Uri.parse(info.downloadUrl!), mode: LaunchMode.externalApplication), child: const Text('Unduh versi terbaru'), )
            else
              Text('Hubungi admin untuk file pembaruan.', style: AppType.bodyStrong),
            const SizedBox(height: AppSpace.s2),
            TextButton(onPressed: () => ref.invalidate(updateInfoProvider), child: const Text('Periksa lagi')),
          ]),
        ),
      ),
    );
  }
}
