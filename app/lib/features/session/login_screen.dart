import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
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

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 360,
            color: AppColors.ink,
            padding: const EdgeInsets.all(AppSpace.s8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BrandLockup(height: 44, reversed: true),
              const Spacer(),
              const AppOverline('Kedai', color: AppColors.onInkMuted),
              const SizedBox(height: AppSpace.s1),
              Text(tenant, style: AppType.headline.copyWith(color: AppColors.onInk)),
              const SizedBox(height: AppSpace.s2),
              Row(children: [
                const Icon(Icons.tablet_android_rounded, size: 18, color: AppColors.onInkMuted),
                const SizedBox(width: AppSpace.s2),
                Text('Tablet ${session.device.code}', style: AppType.body.copyWith(color: AppColors.onInkMuted)),
              ]),
            ]),
          ),
          Expanded(
            child: staff.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorState(
                title: 'Daftar staf gagal dimuat',
                message: '$e',
                onRetry: () => ref.invalidate(staffProvider),
              ),
              data: (members) => Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.s8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text('Siapa yang bertugas?', style: AppType.headline)),
                          IconButton(
                            tooltip: 'Muat ulang',
                            onPressed: () => ref.invalidate(staffProvider),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ]),
                        const SizedBox(height: AppSpace.s1),
                        Text('Pilih nama Anda, lalu masukkan PIN.',
                            style: AppType.body.copyWith(color: AppColors.inkMuted)),
                        const SizedBox(height: AppSpace.s6),
                        Wrap(
                          spacing: AppSpace.s4,
                          runSpacing: AppSpace.s4,
                          children: [
                            for (final m in members)
                              _StaffCard(
                                member: m,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.member, required this.onTap});

  final StaffMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final owner = member.role == 'owner';
    return SizedBox(
      width: 196,
      height: 148,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: const BorderSide(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppAvatar(member.name),
              const Spacer(),
              Text(member.name, style: AppType.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              owner
                  ? const AppBadge('Owner', tone: AppTone.brand, icon: Icons.verified_user_rounded)
                  : Text('Kasir', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

class PinDialog extends ConsumerStatefulWidget {
  const PinDialog({super.key, required this.member});

  final StaffMember member;

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
      await ref.read(sessionProvider.notifier).pinLogin(widget.member.id, _pin);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(AppSpace.s6, AppSpace.s6, AppSpace.s6, AppSpace.s2),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(widget.member.name, size: 56),
            const SizedBox(height: AppSpace.s3),
            Text(widget.member.name, style: AppType.titleLg),
            Text('Masukkan PIN', style: AppType.body.copyWith(color: AppColors.inkMuted)),
            const SizedBox(height: AppSpace.s4),
            Row(
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
            ),
            SizedBox(
              height: 32,
              child: Center(
                child: _error == null
                    ? null
                    : Text(_error!, textAlign: TextAlign.center, style: AppType.caption.copyWith(color: AppColors.danger)),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: AppSpace.s2,
              crossAxisSpacing: AppSpace.s2,
              childAspectRatio: 1.6,
              children: [
                for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'OK', '0', '⌫']) _key(k),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Batal')),
      ],
    );
  }
}
