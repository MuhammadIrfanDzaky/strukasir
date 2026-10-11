import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import 'session_controller.dart';

final staffProvider = FutureProvider.autoDispose<List<StaffMember>>(
    (ref) => ref.read(sessionProvider.notifier).staff());

/// Pilih nama, lalu masukkan PIN.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key, required this.session});

  final NeedsLogin session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffProvider);
    final tenant = session.device.tenantName.isEmpty ? 'Strukasir' : session.device.tenantName;

    final stacked = context.screen.width < 720;
    final device = Row(children: [
      const Icon(Icons.tablet_android_rounded, size: 18, color: AppColors.onInkMuted),
      const SizedBox(width: AppSpace.s2),
      Flexible(
        child: Text('Tablet ${session.device.code}',
            style: AppType.body.copyWith(color: AppColors.onInkMuted), overflow: TextOverflow.ellipsis),
      ),
    ]);

    // Kembali ke layar awal (Daftar / Masuk) — mis. tablet dipakai usaha lain. Butuh PIN owner.
    final leave = TextButton(style: TextButton.styleFrom(foregroundColor: AppColors.onInkMuted, padding: EdgeInsets.zero), onPressed: () => _leave(context, ref, staff.value ?? const []), child: const Text('Ganti usaha / keluarkan tablet'), );

    final brand = stacked
        ? Container(
            color: AppColors.ink,
            padding: const EdgeInsets.fromLTRB(AppSpace.s5, AppSpace.s4, AppSpace.s5, AppSpace.s4),
            child: SafeArea(
              bottom: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const BrandLockup(height: 32, reversed: true),
                const SizedBox(height: AppSpace.s4),
                const AppOverline('Kedai', color: AppColors.onInkMuted),
                Text(tenant,
                    style: AppType.titleLg.copyWith(color: AppColors.onInk), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpace.s1),
                device,
                leave,
              ]),
            ),
          )
        : Container(
            width: context.screen.width >= 1000 ? 360 : 280,
            color: AppColors.ink,
            padding: EdgeInsets.all(context.isShort ? AppSpace.s5 : AppSpace.s8),
            child: SafeArea(
              right: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                BrandLockup(height: context.isShort ? 32 : 44, reversed: true),
                const Spacer(),
                const AppOverline('Kedai', color: AppColors.onInkMuted),
                const SizedBox(height: AppSpace.s1),
                Text(tenant,
                    style: (context.isShort ? AppType.titleLg : AppType.headline).copyWith(color: AppColors.onInk),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpace.s2),
                device,
                const SizedBox(height: AppSpace.s3),
                leave,
              ]),
            ),
          );

    final picker = staff.when(
      loading: () => const AppLoading(),
      error: (e, _) => AppErrorState(
        title: 'Daftar staf gagal dimuat',
        message: '$e',
        onRetry: () => ref.invalidate(staffProvider),
      ),
      data: (members) => LayoutBuilder(builder: (context, box) {
        final pad = box.maxWidth < 600 ? AppSpace.s4 : AppSpace.s8;
        final width = (box.maxWidth - pad * 2).clamp(0.0, 640.0);
        // Kartu staf mengisi lebar: minimal 2 kolom di HP, lebar kartu ±150–200 dp.
        final cols = columnsFor(width, minItem: 150, spacing: AppSpace.s3, min: 2, max: 4);
        final cardWidth = (width - AppSpace.s3 * (cols - 1)) / cols;
        return Align(
          alignment: stacked ? Alignment.topCenter : Alignment.center,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('Siapa yang bertugas?', style: box.maxWidth < 600 ? AppType.titleLg : AppType.headline),
                    ),
                    IconButton(
                      tooltip: 'Muat ulang',
                      onPressed: () => ref.invalidate(staffProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.s1),
                  Text('Pilih nama Anda, lalu masukkan PIN.', style: AppType.body.copyWith(color: AppColors.inkMuted)),
                  const SizedBox(height: AppSpace.s5),
                  Wrap(
                    spacing: AppSpace.s3,
                    runSpacing: AppSpace.s3,
                    children: [
                      for (final m in members)
                        _StaffCard(
                          member: m,
                          width: cardWidth,
                          onTap: () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => PinDialog(member: m),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );

    return Scaffold(
      body: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [brand, Expanded(child: picker)])
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [brand, Expanded(child: picker)]),
    );
  }
}

Future<void> _leave(BuildContext context, WidgetRef ref, List<StaffMember> members) async {
  final owner = members.where((m) => m.role == 'owner').firstOrNull;
  if (owner == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daftar staf belum termuat. Ketuk muat ulang, lalu coba lagi.')));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keluarkan tablet dari usaha?'),
      content: const SizedBox(
        width: 420,
        child: Text(
          'Tablet kembali ke layar awal (Daftar usaha baru / Masuk) dan semua kasir di tablet ini keluar. '
          'Data transaksi tetap tersimpan di server.\n\nDibutuhkan PIN owner.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Lanjut'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinDialog(member: owner, unregister: true),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member, required this.onTap, this.width = 196});

  final StaffMember member;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final owner = member.role == 'owner';
    // Tinggi mengikuti isi (font sistem bisa diperbesar di perangkat); semua kartu memakai badge
    // supaya tingginya tetap seragam.
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: const BorderSide(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppAvatar(member.name),
              const SizedBox(height: AppSpace.s3),
              Text(member.name, style: AppType.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              owner
                  ? const AppBadge('Owner', tone: AppTone.brand, )
                  : const AppBadge('Kasir', ),
            ]),
          ),
        ),
      ),
    );
  }
}

class PinDialog extends ConsumerStatefulWidget {
  const PinDialog({super.key, required this.member, this.unregister = false});

  final StaffMember member;

  /// True = PIN owner dipakai untuk mengeluarkan tablet dari usaha, bukan untuk login.
  final bool unregister;

  @override
  ConsumerState<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends ConsumerState<PinDialog> {
  static const _maxLength = 6;
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_pin.length < 4 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(sessionProvider.notifier);
      widget.unregister
          ? await session.unregisterWithOwnerPin(widget.member.id, _pin)
          : await session.pinLogin(widget.member.id, _pin);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _press(String key) {
    if (_busy) return;
    setState(() {
      _error = null;
      if (key == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < _maxLength) {
        _pin += key;
      }
    });
    if (_pin.length == _maxLength) _submit();
  }

  Widget _key(String k) {
    final onPressed = _busy ? null : () => k == 'OK' ? _submit() : _press(k);
    final child = k == '⌫'
        ? const Icon(Icons.backspace_rounded, semanticLabel: 'Hapus')
        : Text(k, style: AppType.headline.copyWith(fontSize: 24, color: k == 'OK' ? AppColors.onPrimary : AppColors.ink));
    final style = ButtonStyle(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadius.mdAll)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    );
    return k == 'OK'
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton(
            onPressed: onPressed,
            style: style.copyWith(
              backgroundColor: const WidgetStatePropertyAll(AppColors.surfaceSunken),
              foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
            ),
            child: child,
          );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _maxLength; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.all(6),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < _pin.length ? AppColors.primary : AppColors.surface,
                border: Border.all(color: i < _pin.length ? AppColors.primary : AppColors.lineStrong, width: 1.5),
              ),
            ),
        ],
      );

  Widget _errorLine() => SizedBox(
        height: 32,
        child: Center(
          child: _error == null
              ? null
              : Text(_error!, textAlign: TextAlign.center, style: AppType.caption.copyWith(color: AppColors.danger)),
        ),
      );

  /// Keypad 3×4. Baris biasa (bukan GridView) supaya aman di dialog yang bisa di-scroll.
  Widget _keypad(double aspect) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, row) in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['OK', '0', '⌫'],
          ].indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.s2),
              child: Row(children: [
                for (final (j, k) in row.indexed) ...[
                  if (j > 0) const SizedBox(width: AppSpace.s2),
                  Expanded(child: AspectRatio(aspectRatio: aspect, child: _key(k))),
                ],
              ]),
            ),
        ],
      );

  String get _prompt => widget.unregister ? 'PIN owner untuk mengeluarkan tablet' : 'Masukkan PIN';

  @override
  Widget build(BuildContext context) {
    final cancel = TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Batal'));

    if (context.isShort) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s4),
          child: SizedBox(
            width: 520,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AppAvatar(widget.member.name, size: 44),
                  const SizedBox(height: AppSpace.s2),
                  Text(widget.member.name, style: AppType.title, textAlign: TextAlign.center),
                  Text(_prompt, style: AppType.caption.copyWith(color: AppColors.inkMuted), textAlign: TextAlign.center),
                  const SizedBox(height: AppSpace.s2),
                  _dots(),
                  _errorLine(),
                  cancel,
                ]),
              ),
              const SizedBox(width: AppSpace.s4),
              SizedBox(width: 252, child: _keypad(1.9)),
            ]),
          ),
        ),
      );
    }

    return AlertDialog(
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(AppSpace.s6, AppSpace.s6, AppSpace.s6, AppSpace.s2),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(widget.member.name, size: 56),
            const SizedBox(height: AppSpace.s3),
            Text(widget.member.name, style: AppType.titleLg, textAlign: TextAlign.center),
            Text(_prompt, style: AppType.body.copyWith(color: AppColors.inkMuted), textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.s4),
            _dots(),
            _errorLine(),
            _keypad(1.6),
          ],
        ),
      ),
      actions: [cancel],
    );
  }
}
