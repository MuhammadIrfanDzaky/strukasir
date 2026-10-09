import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/csv_import.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import 'customer_api.dart';
import 'customer_form.dart';
import 'credit_dialogs.dart';
import 'customer_picker.dart';
import 'member_tier.dart';
import 'messaging.dart';

/// Kelompok pelanggan (sama dengan server: CustomerService::SEGMENTS).
const _segments = [
  (key: null, label: 'Semua', countKey: 'all'),
  (key: 'new', label: 'Baru', countKey: 'new'),
  (key: 'loyal', label: 'Setia', countKey: 'loyal'),
  (key: 'lost', label: 'Menghilang', countKey: 'lost'),
  (key: 'debt', label: 'Berkasbon', countKey: 'debt'),
];

const _segmentHelp = {
  'new': 'Terdaftar dalam 30 hari terakhir.',
  'loyal': 'Belanja 5× atau lebih dan masih datang dalam 30 hari terakhir.',
  'lost': 'Pernah belanja, tapi tidak datang lagi lebih dari 30 hari. Saatnya disapa.',
  'debt': 'Masih punya kasbon yang belum dilunasi.',
};

const _sorts = {
  'name': 'Nama (A–Z)',
  'recent': 'Terakhir datang',
  'top': 'Belanja terbanyak',
  'newest': 'Terbaru terdaftar',
  'debt': 'Kasbon terbesar',
};

/// Pelanggan / member (owner): cari, kelompok, urutkan, tambah, import, lalu detail per pelanggan.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  String? _segment;
  String _sort = 'name';

  /// Filter tingkat member (null = semua).
  String? _tierId;
  final List<Customer> _items = [];
  Map<String, int>? _counts;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  bool get _phoneRequired => ref.read(menuProvider).value?.menu.customerPhoneRequired ?? true;

  Future<void> _load({bool more = false}) async {
    final seq = ++_seq;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await ref.read(customerApiProvider).list(
            query: _query.text,
            segment: _segment,
            sort: _sort,
            page: more ? _page + 1 : 1,
            perPage: 30,
            withCounts: !more,
            tierId: _tierId,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(page.items);
        _page = more ? _page + 1 : 1;
        _lastPage = page.lastPage;
        _total = page.total;
        _counts = page.segments ?? _counts;
      });
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _add() async {
    final created = await showCustomerForm(context, phoneRequired: _phoneRequired, full: true);
    if (created != null) {
      _load();
      if (mounted) _open(created);
    }
  }

  Future<void> _open(Customer c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id, phoneRequired: _phoneRequired)),
    );
    if (changed == true) _load();
  }

  Future<void> _import() async {
    final api = ref.read(customerApiProvider);
    await importCsv(
      context,
      CsvImportSpec(
        title: 'Import pelanggan dari CSV',
        columns: [
          ('Nama', 'wajib'),
          ('No HP', _phoneRequired ? 'wajib (bisa diubah di Pengaturan → Fitur)' : 'opsional, mis. 0812-3456-7890'),
          ('Tanggal Lahir', 'opsional, mis. 31/12/1990'),
          ('Catatan', 'opsional'),
        ],
        example: 'Nama,No HP,Tanggal Lahir,Catatan\nAndi Saputra,081234567890,31/12/1990,Suka less sugar',
        note: 'Pelanggan dengan no HP sama diperbarui, sisanya ditambahkan dengan kode member baru.',
        run: (csv, dryRun) => api.import(csv, dryRun: dryRun),
        summary: (r) => [
          AppSummaryRow('Pelanggan baru', '${r['created']}'),
          AppSummaryRow('Pelanggan diperbarui', '${r['updated']}'),
        ],
        doneMessage: (r) => 'Import selesai: ${r['created']} pelanggan baru, ${r['updated']} diperbarui.',
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final pad = compact ? AppSpace.s3 : AppSpace.s5;

    final search = TextField(
      controller: _query,
      onChanged: _onQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Cari nama, kode, atau no HP',
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
        suffixIcon: _query.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Hapus',
                onPressed: () {
                  _query.clear();
                  _load();
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
    final sortMenu = PopupMenuButton<String>(
      tooltip: 'Urutkan',
      initialValue: _sort,
      onSelected: (v) {
        setState(() => _sort = v);
        _load();
      },
      itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      icon: const Icon(Icons.sort_rounded),
    );
    final messagingOn = ref.watch(menuProvider).value?.menu.feature('customer_messaging') ?? false;
    void openMessaging() => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => MessagingScreen(creditOn: ref.read(menuProvider).value?.menu.feature('customer_credit') ?? false),
        ));
    // HP: urutkan & import digabung di satu menu supaya kolom cari tetap lega.
    final actions = compact
        ? [
            IconButton.filled(tooltip: 'Tambah pelanggan', onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded)),
            PopupMenuButton<String>(
              tooltip: 'Lainnya',
              onSelected: (v) {
                if (v == 'import') {
                  _import();
                } else if (v == 'messages') {
                  openMessaging();
                } else {
                  setState(() => _sort = v);
                  _load();
                }
              },
              itemBuilder: (_) => [
                for (final e in _sorts.entries)
                  CheckedPopupMenuItem(value: e.key, checked: _sort == e.key, child: Text(e.value)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(leading: Icon(Icons.upload_file_rounded), title: Text('Import CSV')),
                ),
                if (messagingOn)
                  const PopupMenuItem(
                    value: 'messages',
                    child: ListTile(leading: Icon(Icons.chat_rounded), title: Text('Kirim pesan WA')),
                  ),
              ],
            ),
          ]
        : [
            sortMenu,
            IconButton(tooltip: 'Import CSV', onPressed: _import, icon: const Icon(Icons.upload_file_rounded)),
            if (messagingOn) IconButton(tooltip: 'Kirim pesan WA', onPressed: openMessaging, icon: const Icon(Icons.chat_rounded)),
            FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Tambah')),
          ];

    final tiers = ref.watch(menuProvider).value?.menu.memberTiers ?? const <MemberTier>[];
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: pad),
      child: Row(
        children: [
          if (tiers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.s2),
              child: PopupMenuButton<String>(
                tooltip: 'Filter tingkat',
                onSelected: (v) {
                  setState(() => _tierId = v.isEmpty ? null : v);
                  _load();
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(value: '', checked: _tierId == null, child: const Text('Semua tingkat')),
                  for (final t in tiers) CheckedPopupMenuItem(value: t.id, checked: _tierId == t.id, child: Text(t.name)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.workspace_premium_rounded, size: 18),
                  label: Text(tiers.where((t) => t.id == _tierId).firstOrNull?.name ?? 'Tingkat'),
                  backgroundColor: _tierId == null ? null : AppColors.primarySoft,
                ),
              ),
            ),
          for (final s in _segments)
            if (s.key != 'debt' || (ref.watch(menuProvider).value?.menu.feature('customer_credit') ?? false))
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.s2),
              child: ChoiceChip(
                label: Text(_counts == null ? s.label : '${s.label} ${_counts![s.countKey] ?? 0}'),
                selected: _segment == s.key,
                showCheckmark: false,
                onSelected: (_) {
                  setState(() => _segment = s.key);
                  _load();
                },
              ),
            ),
        ],
      ),
    );

    Widget body;
    if (_error != null) {
      body = AppErrorState(message: _error!, onRetry: _load);
    } else if (_loading && _items.isEmpty) {
      body = const AppLoading();
    } else if (_items.isEmpty) {
      final filtered = _query.text.trim().isNotEmpty || _segment != null;
      body = AppEmptyState(
        icon: Icons.groups_rounded,
        title: filtered ? 'Tidak ada pelanggan yang cocok' : 'Belum ada pelanggan',
        message: filtered
            ? (_segment != null ? _segmentHelp[_segment] : null)
            : 'Daftarkan pelanggan dari layar kasir (ikon cari di kolom nama), tambah di sini, atau import CSV.',
        action: filtered ? null : FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Tambah pelanggan')),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(0, 0, 0, AppSpace.s6),
          itemCount: _items.length + 1,
          separatorBuilder: (_, i) => i >= _items.length - 1 ? const SizedBox.shrink() : const Divider(height: 1, indent: 72),
          itemBuilder: (_, i) {
            if (i == _items.length) {
              return Padding(
                padding: const EdgeInsets.all(AppSpace.s4),
                child: Center(
                  child: _page < _lastPage
                      ? OutlinedButton(
                          onPressed: _loadingMore ? null : () => _load(more: true),
                          child: Text(_loadingMore ? 'Memuat…' : 'Muat lagi (${_items.length} dari $_total)'),
                        )
                      : Text('$_total pelanggan', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                ),
              );
            }
            final c = _items[i];
            final spent = (c.creditBalance ?? 0) > 0
                ? 'kasbon ${rp(c.creditBalance!)}'
                : (c.totalSpent == null || c.totalSpent == 0 ? null : rp(c.totalSpent!));
            // Layar lebar: total belanja di kanan; HP: di baris kunjungan.
            return CustomerTile(
              c,
              loyaltyUnit: ref.watch(menuProvider).value?.menu.loyalty?.unit,
              onTap: () => _open(c),
              spent: compact ? spent : null,
              trailing: compact || spent == null
                  ? null
                  : Text(spent, style: AppType.bodyStrong.copyWith(color: (c.creditBalance ?? 0) > 0 ? AppColors.warning : null)),
            );
          },
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad - AppSpace.s1, AppSpace.s2),
              child: Row(children: [Expanded(child: search), const SizedBox(width: AppSpace.s1), ...actions]),
            ),
            chips,
            if (_segment != null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, AppSpace.s2, pad, 0),
                child: Text(_segmentHelp[_segment]!, style: AppType.caption.copyWith(color: AppColors.inkMuted)),
              ),
            const SizedBox(height: AppSpace.s2),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Detail pelanggan (owner): data, statistik belanja, produk favorit, order terakhir, ubah, hapus data.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId, required this.phoneRequired});

  final String customerId;
  final bool phoneRequired;

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await ref.read(customerApiProvider).detail(widget.customerId);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit(Customer c) async {
    final saved = await showCustomerForm(context, customer: c, phoneRequired: widget.phoneRequired, full: true);
    if (saved != null) {
      _changed = true;
      _load();
    }
  }

  Future<void> _repay(Customer c) async {
    final left = await showRepayDialog(context, customerId: c.id, name: c.name, balance: c.creditBalance ?? 0);
    if (left != null) {
      _changed = true;
      _load();
    }
  }

  Future<void> _editLimit(Customer c) async {
    final r = await showCreditLimitDialog(context, current: c.creditLimit, custom: c.creditLimitCustom);
    if (r == null || !mounted) return;
    try {
      await ref.read(customerApiProvider).setCreditLimit(c.id, r.$2);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reverse(Customer c, Map<String, dynamic> entry) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan pelunasan?'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Pelunasan ${rp(entry['amount'] as int)} dibatalkan dan kasbon bertambah lagi. '
                '${entry['method'] == 'cash' ? 'Uang tunainya keluar dari laci shift ini.' : ''}'),
            const SizedBox(height: AppSpace.s3),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Alasan', hintText: 'mis. salah pelanggan')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Batalkan pelunasan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(customerApiProvider).reverseRepayment(c.id, entry['id'] as String, reason.text.trim().isEmpty ? 'Salah catat' : reason.text.trim());
      _changed = true;
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.fieldErrors.values.expand((v) => v).firstOrNull ?? e.message)));
    }
  }

  /// Kunci tingkat manual, atau kembali otomatis (null).
  Future<void> _lockTier(Customer c, List<MemberTier> tiers) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tingkat member'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const ListTile(
              leading: Icon(Icons.autorenew_rounded),
              title: Text('Otomatis dari belanja'),
              subtitle: Text('Naik / turun sendiri'),
            ),
          ),
          for (final t in tiers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t.id),
              child: ListTile(leading: TierBadge(t), title: Text('Kunci di ${t.name}'), subtitle: t.benefits.isEmpty ? null : Text(t.benefits)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await ref.read(customerApiProvider).setTier(c.id, picked.isEmpty ? null : picked);
      _changed = true;
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Tambah / kurangi saldo dengan alasan (mis. pindahan kartu stempel kertas).
  Future<void> _adjust(Customer c, String unit) async {
    final result = await showDialog<(int, String)>(context: context, builder: (_) => _AdjustDialog(unit: unit, balance: c.loyaltyBalance ?? 0));
    if (result == null || !mounted) return;
    try {
      await ref.read(customerApiProvider).adjustLoyalty(c.id, result.$1, result.$2);
      _changed = true;
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _anonymize(Customer c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
        title: Text('Hapus data ${c.name}?'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'Nama, no HP, tanggal lahir, dan catatan dihapus permanen, termasuk nama di riwayat order. '
            'Angka penjualan tetap ada di laporan. Gunakan bila pelanggan meminta datanya dihapus.\n\n'
            'Tindakan ini tidak bisa dibatalkan.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus data'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(customerApiProvider).anonymize(c.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data pribadi pelanggan sudah dihapus.')));
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final c = data == null ? null : Customer.fromJson(data);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceApp,
        appBar: AppBar(
          title: Text(c?.name ?? 'Pelanggan'),
          actions: [
            if (c != null) ...[
              IconButton(tooltip: 'Ubah', onPressed: () => _edit(c), icon: const Icon(Icons.edit_rounded)),
              if (c.phone != null && (ref.watch(menuProvider).value?.menu.feature('customer_messaging') ?? false))
                PopupMenuButton<String>(
                  tooltip: 'Kirim WA',
                  icon: const Icon(Icons.chat_rounded),
                  onSelected: (t) => openWhatsApp(context, ref, c.id, t),
                  itemBuilder: (_) => [
                    for (final (key, label, icon) in ownerTemplates)
                      if (key != 'credit_reminder' || (c.creditBalance ?? 0) > 0)
                        PopupMenuItem(value: key, child: ListTile(leading: Icon(icon), title: Text(label))),
                  ],
                ),
              PopupMenuButton<String>(
                tooltip: 'Lainnya',
                onSelected: (_) => _anonymize(c),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'anonymize',
                    child: ListTile(
                      leading: Icon(Icons.person_off_rounded, color: AppColors.danger),
                      title: Text('Hapus data pelanggan'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: _error != null
            ? AppErrorState(message: _error!, onRetry: _load)
            : c == null
                ? const AppLoading()
                : _body(c, data!),
      ),
    );
  }

  Widget _body(Customer c, Map<String, dynamic> data) {
    final favorites = ((data['favorites'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final orders = ((data['recent_orders'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final entries = ((data['loyalty_entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final compact = context.isCompact;
    final program = ref.watch(menuProvider).value?.menu.loyalty;
    final tiers = ref.watch(menuProvider).value?.menu.memberTiers ?? const <MemberTier>[];
    final progress = data['tier_progress'] as Map<String, dynamic>?;

    final info = AppSectionCard(
      title: 'Data pelanggan',
      children: [
        Row(
          children: [
            AppAvatar(c.name, size: 48),
            const SizedBox(width: AppSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: AppType.title),
                  Text('Member ${c.code}', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s3),
        _InfoRow(Icons.phone_rounded, c.phone == null ? 'Tanpa no HP' : formatPhone(c.phone)),
        _InfoRow(Icons.cake_outlined, c.birthDate == null ? 'Tanggal lahir belum diisi' : formatDate(c.birthDate!)),
        if (c.note != null && c.note!.isNotEmpty) _InfoRow(Icons.sticky_note_2_outlined, c.note!, color: AppColors.warning),
        if (c.createdAt != null)
          _InfoRow(Icons.event_rounded, 'Terdaftar ${formatDate(c.createdAt!.toIso8601String().substring(0, 10))}'),
      ],
    );

    final stats = LayoutBuilder(
      builder: (context, box) {
        final cols = columnsFor(box.maxWidth, minItem: 150, max: 4);
        final w = (box.maxWidth - AppSpace.s3 * (cols - 1)) / cols;
        return Wrap(
          spacing: AppSpace.s3,
          runSpacing: AppSpace.s3,
          children: [
            AppStatCard('Total belanja', rp(c.totalSpent ?? 0), emphasis: true, width: w),
            AppStatCard('Kunjungan', '${c.visits}×', width: w),
            AppStatCard('Rata-rata', c.average == null ? '–' : rp(c.average!), width: w),
            AppStatCard('Terakhir datang', sinceLabel(c.lastVisitAt), width: w),
            if (program != null && c.loyaltyBalance != null)
              AppStatCard('Saldo ${program.unit}', '${c.loyaltyBalance}', width: w),
          ],
        );
      },
    );

    final favCard = AppSectionCard(
      title: 'Produk favorit',
      empty: 'Belum ada pembelian.',
      children: [
        for (final (i, f) in favorites.indexed)
          AppSummaryRow('${i + 1}. ${f['name']}', '${f['qty']}×'),
      ],
    );

    String measure(int v) => progress?['basis'] == 'visits' ? '$v kunjungan' : rp(v);
    final next = progress?['next'] as Map<String, dynamic>?;
    final tierCard = tiers.isEmpty
        ? null
        : AppSectionCard(
            title: 'Tingkat member',
            trailing: TextButton.icon(
              onPressed: () => _lockTier(c, tiers),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Ubah'),
            ),
            children: [
              Row(children: [
                if (c.tier != null) TierBadge(c.tier!) else const AppBadge('Belum bertingkat'),
                const SizedBox(width: AppSpace.s2),
                Expanded(
                  child: Text(
                    c.tier == null ? '' : (c.tier!.manual ? 'Dikunci owner' : (c.tier!.benefits.isEmpty ? 'Otomatis' : c.tier!.benefits)),
                    style: AppType.caption.copyWith(color: AppColors.inkMuted),
                  ),
                ),
              ]),
              if (progress != null) ...[
                const SizedBox(height: AppSpace.s3),
                Text(
                  '${progress['basis'] == 'visits' ? 'Kunjungan' : 'Belanja'} '
                  '${progress['window_months'] == null ? 'sepanjang waktu' : '${progress['window_months']} bulan terakhir'}: '
                  '${measure(progress['metric'] as int)}',
                  style: AppType.body,
                ),
                if (next != null) ...[
                  const SizedBox(height: AppSpace.s2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: (next['threshold'] as int) == 0 ? 1 : ((progress['metric'] as int) / (next['threshold'] as int)).clamp(0, 1).toDouble(),
                      backgroundColor: AppColors.surfaceSunken,
                    ),
                  ),
                  const SizedBox(height: AppSpace.s1),
                  Text('Kurang ${measure(next['remaining'] as int)} lagi untuk ${next['name']}',
                      style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                ],
              ],
            ],
          );

    final creditHistory = ((data['credit_history'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final creditCard = c.creditBalance == null
        ? null
        : AppSectionCard(
            title: 'Kasbon',
            trailing: TextButton.icon(
              onPressed: () => _editLimit(c),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Batas'),
            ),
            empty: 'Belum pernah kasbon.',
            children: [
              AppSummaryRow('Sisa kasbon', rp(c.creditBalance!), emphasis: true,
                  valueColor: c.creditBalance! > 0 ? AppColors.warning : AppColors.success),
              AppSummaryRow('Batas', '${c.creditLimit == null ? 'Tanpa batas' : rp(c.creditLimit!)}${c.creditLimitCustom ? '' : ' (default kedai)'}'),
              if (c.creditBalance! > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s2),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _repay(c),
                    icon: const Icon(Icons.payments_rounded),
                    label: const Text('Catat pelunasan'),
                  ),
                ),
              for (final e in creditHistory)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          switch (e['kind']) {
                            'charge' => 'Kasbon',
                            'charge_void' => 'Kasbon dibatalkan (void)',
                            'repayment' => (e['reversed'] as bool) ? 'Pelunasan (dibatalkan)' : 'Pelunasan',
                            _ => 'Pembatalan pelunasan',
                          },
                          style: AppType.bodyStrong,
                        ),
                        Text(
                          [
                            formatDate((e['created_at'] as String).substring(0, 10)),
                            if (e['label'] != null) e['label'] as String,
                            if (e['method'] != null) const {'cash': 'Tunai', 'debit': 'Debit', 'qris': 'QRIS'}[e['method']] ?? '',
                          ].join(' · '),
                          style: AppType.caption.copyWith(color: AppColors.inkMuted),
                        ),
                      ]),
                    ),
                    Text(
                      '${e['kind'] == 'charge' || e['kind'] == 'reversal' ? '+' : '−'}${rupiah(e['amount'] as int)}',
                      style: AppType.bodyStrong,
                    ),
                    if (e['kind'] == 'repayment' && !(e['reversed'] as bool))
                      IconButton(
                        tooltip: 'Batalkan pelunasan',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _reverse(c, e),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                      ),
                  ]),
                ),
            ],
          );

    final loyaltyCard = program == null
        ? null
        : AppSectionCard(
            title: 'Riwayat ${program.unit} · ${program.name}',
            trailing: TextButton.icon(
              onPressed: () => _adjust(c, program.unit),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Sesuaikan'),
            ),
            empty: 'Belum ada ${program.unit}.',
            children: [
              if (c.loyaltyExpiresAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.s2),
                  child: Text('Saldo hangus ${formatDate(c.loyaltyExpiresAt!.toIso8601String().substring(0, 10))} bila tidak belanja lagi.',
                      style: AppType.caption.copyWith(color: AppColors.warning)),
                ),
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_entryLabel(e['kind'] as String), style: AppType.bodyStrong),
                            Text(
                              [
                                formatDate((e['created_at'] as String).substring(0, 10)),
                                if (e['order_number'] != null) e['order_number'] as String,
                                if (e['note'] != null) e['note'] as String,
                              ].join(' · '),
                              style: AppType.caption.copyWith(color: AppColors.inkMuted),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(e['units'] as int) > 0 ? '+' : ''}${e['units']}',
                        style: AppType.bodyStrong.copyWith(color: (e['units'] as int) > 0 ? AppColors.success : AppColors.ink),
                      ),
                    ],
                  ),
                ),
            ],
          );

    final orderCard = AppSectionCard(
      title: 'Order terakhir',
      empty: 'Belum ada order.',
      children: [
        for (final o in orders)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o['number'] as String, style: AppType.bodyStrong),
                      Text(formatDate(o['business_date'] as String), style: AppType.caption.copyWith(color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                if (o['status'] != 'paid') ...[AppBadge.orderStatus(o['status'] as String), const SizedBox(width: AppSpace.s2)],
                Text(
                  rp(o['grand_total'] as int),
                  style: AppType.bodyStrong.copyWith(
                    color: o['status'] == 'paid' ? AppColors.ink : AppColors.inkDisabled,
                    decoration: o['status'] == 'void' ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(compact ? AppSpace.s3 : AppSpace.s5),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stats,
                  const SizedBox(height: AppSpace.s4),
                  if (compact) ...[
                    info,
                    const SizedBox(height: AppSpace.s3),
                    if (creditCard != null) ...[creditCard, const SizedBox(height: AppSpace.s3)],
                    if (tierCard != null) ...[tierCard, const SizedBox(height: AppSpace.s3)],
                    if (loyaltyCard != null) ...[loyaltyCard, const SizedBox(height: AppSpace.s3)],
                    favCard,
                    const SizedBox(height: AppSpace.s3),
                    orderCard,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(children: [
                            info,
                            if (tierCard != null) ...[const SizedBox(height: AppSpace.s3), tierCard],
                            const SizedBox(height: AppSpace.s3),
                            favCard,
                          ]),
                        ),
                        const SizedBox(width: AppSpace.s3),
                        Expanded(
                          child: Column(children: [
                            if (creditCard != null) ...[creditCard, const SizedBox(height: AppSpace.s3)],
                            if (loyaltyCard != null) ...[loyaltyCard, const SizedBox(height: AppSpace.s3)],
                            orderCard,
                          ]),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _entryLabel(String kind) => switch (kind) {
      'earn' => 'Dapat dari belanja',
      'redeem' => 'Tukar hadiah',
      'reverse' => 'Dibatalkan (void)',
      'expire' => 'Hangus',
      _ => 'Penyesuaian',
    };

/// Tambah / kurangi saldo stempel/poin + alasan (wajib, tercatat).
class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.unit, required this.balance});

  final String unit;
  final int balance;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  bool _add = true;
  final _units = TextEditingController();
  final _note = TextEditingController();
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _units.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_units.text.trim());
    final errors = <String, String>{
      if (n == null || n < 1) 'units': 'Isi jumlah',
      if (n != null && !_add && n > widget.balance) 'units': 'Saldo hanya ${widget.balance}',
      if (_note.text.trim().isEmpty) 'note': 'Tulis alasannya',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    Navigator.pop(context, (_add ? n! : -n!, _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text('Sesuaikan ${widget.unit}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Saldo sekarang: ${widget.balance} ${widget.unit}', style: AppType.body.copyWith(color: AppColors.inkMuted)),
              const SizedBox(height: AppSpace.s3),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('Tambah'), icon: Icon(Icons.add_rounded)),
                  ButtonSegment(value: false, label: Text('Kurangi'), icon: Icon(Icons.remove_rounded)),
                ],
                selected: {_add},
                onSelectionChanged: (v) => setState(() => _add = v.first),
              ),
              const SizedBox(height: AppSpace.s3),
              TextField(
                controller: _units,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Jumlah', suffixText: widget.unit, errorText: _errors['units']),
              ),
              const SizedBox(height: AppSpace.s3),
              TextField(
                controller: _note,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: 'Alasan',
                  hintText: 'mis. pindahan kartu stempel kertas',
                  errorText: _errors['note'],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: _submit, child: const Text('Simpan')),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text, {this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color ?? AppColors.inkMuted),
            const SizedBox(width: AppSpace.s3),
            Expanded(child: Text(text, style: AppType.body.copyWith(color: color ?? AppColors.ink))),
          ],
        ),
      );
}
