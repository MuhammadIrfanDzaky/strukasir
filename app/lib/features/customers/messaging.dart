import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../session/session_controller.dart';
import 'customer_api.dart';
import 'customer_form.dart' show formatDate;

final messagingApiProvider = Provider((ref) => MessagingApi(ref));

/// Pesan WhatsApp (fitur `customer_messaging`): server menyusun teks & tautan wa.me, tablet membukanya.
class MessagingApi {
  MessagingApi(this._ref);

  final Ref _ref;

  Future<T> _authed<T>(Future<T> Function(ApiClient api, String token) call) =>
      _ref.read(sessionProvider.notifier).authed(call);

  /// {url, text}
  Future<Map<String, dynamic>> prepare(String customerId, String template, {String? orderId}) async {
    final res = await _authed((api, token) => api.post('/customers/$customerId/messages',
        token: token, data: {'template': template, 'order_id': ?orderId}));
    return res['data'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> audience(String template) async {
    final res = await _authed((api, token) => api.get('/messages/audience?template=$template', token: token));
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> templates() async =>
      (await _authed((api, token) => api.get('/settings/messages', token: token)))['data'] as Map<String, dynamic>;

  Future<Map<String, dynamic>> saveTemplates(Map<String, String> bodies) async =>
      (await _authed((api, token) => api.put('/settings/messages', token: token, data: {'templates': bodies})))['data']
          as Map<String, dynamic>;
}

/// Siapkan pesan lalu buka WhatsApp; kasir/owner tinggal menekan kirim. True bila WhatsApp terbuka.
Future<bool> openWhatsApp(BuildContext context, WidgetRef ref, String customerId, String template, {String? orderId}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final msg = await ref.read(messagingApiProvider).prepare(customerId, template, orderId: orderId);
    final ok = await launchUrl(Uri.parse(msg['url'] as String), mode: LaunchMode.externalApplication);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('WhatsApp tidak bisa dibuka di perangkat ini.')));
    return ok;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message)));
    return false;
  }
}

/// Pilihan template untuk owner (dari detail pelanggan).
const ownerTemplates = [
  ('greeting', 'Sapaan umum', Icons.waving_hand_rounded),
  ('birthday', 'Ucapan ulang tahun', Icons.cake_rounded),
  ('winback', 'Sapa pelanggan lama', Icons.favorite_rounded),
  ('credit_reminder', 'Pengingat kasbon', Icons.menu_book_rounded),
];

/// Owner: daftar siap-kirim — ulang tahun 7 hari ke depan, pelanggan menghilang, berkasbon.
class MessagingScreen extends ConsumerStatefulWidget {
  const MessagingScreen({super.key, this.creditOn = false});

  final bool creditOn;

  @override
  ConsumerState<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends ConsumerState<MessagingScreen> {
  late final _tabs = [
    ('birthday', 'Ulang tahun', 'Ulang tahun hari ini sampai 7 hari ke depan (yang punya no HP & tanggal lahir).'),
    ('winback', 'Menghilang', 'Pernah belanja, tapi tidak datang lebih dari 30 hari.'),
    if (widget.creditOn) ('credit_reminder', 'Berkasbon', 'Masih punya kasbon. Kirim pengingat dengan sopan.'),
  ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          backgroundColor: AppColors.surfaceApp,
          appBar: AppBar(
            title: const Text('Kirim pesan WhatsApp'),
            bottom: TabBar(isScrollable: context.isCompact, tabs: [for (final t in _tabs) Tab(text: t.$2)]),
          ),
          body: TabBarView(children: [for (final t in _tabs) _AudienceList(template: t.$1, help: t.$3)]),
        ),
      );
}

class _AudienceList extends ConsumerStatefulWidget {
  const _AudienceList({required this.template, required this.help});

  final String template;
  final String help;

  @override
  ConsumerState<_AudienceList> createState() => _AudienceListState();
}

class _AudienceListState extends ConsumerState<_AudienceList> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await ref.read(messagingApiProvider).audience(widget.template);
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _detail(Map<String, dynamic> r) => switch (widget.template) {
        'birthday' => 'Ulang tahun ${formatDate(r['birth_date'] as String).replaceAll(RegExp(r' \d{4}$'), '')}',
        'winback' => 'Terakhir datang ${sinceLabel(r['last_visit_at'] == null ? null : DateTime.parse(r['last_visit_at'] as String).toLocal()).toLowerCase()}',
        _ => 'Kasbon ${rp(r['credit_balance'] as int)}',
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _rows;
    if (_error != null) return AppErrorState(message: _error!, onRetry: _load);
    if (rows == null) return const AppLoading();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.s6),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s4, AppSpace.s2),
            child: Text(widget.help, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          ),
          if (rows.isEmpty)
            const SizedBox(height: 320, child: AppEmptyState(icon: Icons.mark_chat_read_rounded, title: 'Tidak ada yang perlu dikirimi saat ini'))
          else
            for (final r in rows) ...[
              ListTile(
                leading: AppAvatar(r['name'] as String, size: 40),
                title: Text(r['name'] as String, style: AppType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    '${r['code']} · ${_detail(r)}',
                    if (r['last_sent_at'] != null)
                      'Terkirim ${sinceLabel(DateTime.parse(r['last_sent_at'] as String).toLocal()).toLowerCase()}',
                  ].join('\n'),
                  style: AppType.caption.copyWith(color: AppColors.inkMuted),
                ),
                trailing: r['last_sent_at'] != null
                    ? OutlinedButton(
                        onPressed: () => _send(r),
                        child: const Text('Kirim lagi'),
                      )
                    : FilledButton(onPressed: () => _send(r), child: const Text('WA'), ),
              ),
              const Divider(height: 1, indent: 72),
            ],
        ],
      ),
    );
  }

  Future<void> _send(Map<String, dynamic> r) async {
    if (await openWhatsApp(context, ref, r['id'] as String, widget.template)) _load();
  }
}

/// Pengaturan → Pesan WhatsApp: ubah teks template (kosongkan = teks bawaan).
class MessageTemplatesScreen extends ConsumerStatefulWidget {
  const MessageTemplatesScreen({super.key});

  @override
  ConsumerState<MessageTemplatesScreen> createState() => _MessageTemplatesScreenState();
}

class _MessageTemplatesScreenState extends ConsumerState<MessageTemplatesScreen> {
  List<Map<String, dynamic>>? _templates;
  List<String> _placeholders = const [];
  final Map<String, TextEditingController> _controllers = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(Map<String, dynamic> data) => setState(() {
        _templates = (data['templates'] as List).cast<Map<String, dynamic>>();
        _placeholders = (data['placeholders'] as List).cast<String>();
        for (final t in _templates!) {
          (_controllers[t['key'] as String] ??= TextEditingController()).text = t['body'] as String;
        }
      });

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      _apply(await ref.read(messagingApiProvider).templates());
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      _apply(await ref.read(messagingApiProvider).saveTemplates({for (final e in _controllers.entries) e.key: e.value.text}));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template pesan disimpan.')));
      Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = _templates;
    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Pesan WhatsApp')),
      body: templates == null
          ? (_error == null ? const AppLoading() : AppErrorState(message: _error!, onRetry: _load))
          : ListView(
              padding: EdgeInsets.all(context.isCompact ? AppSpace.s3 : AppSpace.s5),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(
                        'Pesan dikirim lewat WhatsApp di tablet/HP ini (gratis): app membuka WhatsApp dengan pesan siap kirim, '
                        'tinggal tekan kirim. Isian otomatis: ${_placeholders.join(' ')}',
                        style: AppType.body.copyWith(color: AppColors.inkMuted),
                      ),
                      const SizedBox(height: AppSpace.s3),
                      for (final t in templates) ...[
                        AppSectionCard(
                          title: t['title'] as String,
                          trailing: TextButton(
                            onPressed: _busy ? null : () => setState(() => _controllers[t['key']]!.text = t['default'] as String),
                            child: const Text('Teks bawaan'),
                          ),
                          children: [
                            TextField(
                              controller: _controllers[t['key']],
                              minLines: 2,
                              maxLines: 6,
                              maxLength: 1000,
                              decoration: const InputDecoration(isDense: true),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.s3),
                      ],
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touchLg)),
                        child: _busy
                            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Text('Simpan'),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}
