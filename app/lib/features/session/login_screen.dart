import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(session.device.tenantName.isEmpty ? 'BerryBrew POS' : session.device.tenantName),
        actions: [
          Center(child: Text('Tablet ${session.device.code}  ')),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.invalidate(staffProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorRetry(message: '$e', onRetry: () => ref.invalidate(staffProvider)),
        data: (members) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('Siapa yang bertugas?', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final m in members)
                      SizedBox(
                        width: 170,
                        height: 110,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => PinDialog(member: m),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(m.role == 'owner' ? Icons.verified_user : Icons.person, size: 32),
                                const SizedBox(height: 8),
                                Text(m.name, style: Theme.of(context).textTheme.titleMedium),
                                Text(m.role == 'owner' ? 'Owner' : 'Kasir'),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('PIN ${widget.member.name}'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _maxLength; i++)
                  Container(
                    margin: const EdgeInsets.all(6),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? scheme.primary : scheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 24,
              child: _error == null
                  ? null
                  : Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
              children: [
                for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'OK', '0', '⌫'])
                  FilledButton.tonal(
                    onPressed: _busy ? null : () => k == 'OK' ? _submit() : _press(k),
                    child: Text(k, style: const TextStyle(fontSize: 22)),
                  ),
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

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      );
}
