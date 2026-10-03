import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'session_controller.dart';

/// Pendaftaran tablet oleh owner (sekali saja per tablet).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: 'Tablet Kasir');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _deviceName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).registerDevice(
            serverUrl: _server.text.trim(),
            email: _email.text,
            password: _password.text,
            deviceName: _deviceName.text,
          );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Daftarkan Tablet', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('Dilakukan sekali oleh owner. Setelah itu kasir cukup login dengan PIN.'),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _server,
                    decoration: const InputDecoration(
                      labelText: 'Alamat server',
                      hintText: 'https://pos.contoh.my.id',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      final uri = Uri.tryParse(v?.trim() ?? '');
                      return uri != null && uri.hasScheme && uri.host.isNotEmpty
                          ? null
                          : 'Isi alamat lengkap, mis. https://pos.contoh.my.id';
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email owner', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v?.contains('@') ?? false) ? null : 'Email tidak valid',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password owner', border: OutlineInputBorder()),
                    obscureText: true,
                    validator: (v) => (v?.isNotEmpty ?? false) ? null : 'Wajib diisi',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _deviceName,
                    decoration: const InputDecoration(labelText: 'Nama tablet', border: OutlineInputBorder()),
                    validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Wajib diisi',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: _busy
                        ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Daftarkan'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
