import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import 'customer_api.dart';
import 'customer_form.dart';

/// Pilih member untuk order: cari nama / kode / no HP (cukup beberapa angka terakhir), atau
/// daftarkan pelanggan baru tanpa meninggalkan layar kasir. HP → layar penuh; tablet → dialog.
Future<Customer?> pickCustomer(BuildContext context, {required bool phoneRequired, String initialQuery = ''}) {
  final picker = CustomerPicker(phoneRequired: phoneRequired, initialQuery: initialQuery);
  return context.isCompact || context.isShort
      ? showDialog<Customer>(context: context, builder: (_) => Dialog.fullscreen(child: picker))
      : showDialog<Customer>(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640), child: picker),
          ),
        );
}

class CustomerPicker extends ConsumerStatefulWidget {
  const CustomerPicker({super.key, required this.phoneRequired, this.initialQuery = ''});

  final bool phoneRequired;
  final String initialQuery;

  @override
  ConsumerState<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<CustomerPicker> {
  late final _query = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<Customer>? _results;
  String? _error;

  /// Nomor permintaan terakhir: hasil pencarian lama yang datang terlambat diabaikan.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final seq = ++_seq;
    final q = _query.text.trim();
    setState(() => _error = null);
    try {
      // Tanpa kata kunci: yang terakhir datang di atas (biasanya pelanggan yang sedang antre lagi).
      final page = await ref.read(customerApiProvider).list(query: q, sort: q.isEmpty ? 'recent' : 'name', perPage: 30);
      if (mounted && seq == _seq) setState(() => _results = page.items);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    }
  }

  Future<void> _create() async {
    final q = _query.text.trim();
    final looksLikePhone = RegExp(r'^[0-9+\-\s]{4,}$').hasMatch(q);
    final created = await showCustomerForm(
      context,
      initialName: looksLikePhone ? '' : q,
      initialPhone: looksLikePhone ? q : '',
      phoneRequired: widget.phoneRequired,
    );
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s2, AppSpace.s2, AppSpace.s4, 0),
          child: Row(
            children: [
              IconButton(tooltip: 'Tutup', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              const SizedBox(width: AppSpace.s1),
              const Expanded(child: Text('Pilih pelanggan', style: AppType.titleLg)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s4, AppSpace.s2),
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Cari nama, kode member, atau no HP',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus',
                      onPressed: () {
                        _query.clear();
                        _search();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? AppErrorState(message: _error!, onRetry: _search)
              : results == null
                  ? const AppLoading()
                  : results.isEmpty
                      ? AppEmptyState(
                          icon: Icons.person_search_rounded,
                          title: _query.text.trim().isEmpty ? 'Belum ada pelanggan' : 'Tidak ditemukan',
                          message: 'Daftarkan sebagai pelanggan baru.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: AppSpace.s2),
                          itemCount: results.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (_, i) => CustomerTile(
                            results[i],
                            loyaltyUnit: ref.watch(menuProvider).value?.menu.loyalty?.unit,
                            onTap: () => Navigator.pop(context, results[i]),
                          ),
                        ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(AppSpace.s3),
          child: FilledButton.tonalIcon(
            onPressed: _create,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSize.touch)),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Pelanggan baru'),
          ),
        ),
      ],
    );
  }
}

/// Satu baris pelanggan: nama, kode, no HP, kunjungan, catatan.
class CustomerTile extends StatelessWidget {
  const CustomerTile(this.customer, {super.key, this.onTap, this.trailing, this.spent, this.loyaltyUnit});

  final Customer customer;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Total belanja (owner), ditulis di baris kunjungan.
  final String? spent;

  /// "stempel" / "poin" bila program loyalitas berjalan → saldo ikut ditulis.
  final String? loyaltyUnit;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final muted = AppType.caption.copyWith(color: AppColors.inkMuted);
    final id = [c.code, if (c.phone != null) formatPhone(c.phone)].join(' · ');
    final visits = [
      c.visits == 0 ? 'Belum pernah belanja' : '${c.visits}× · ${sinceLabel(c.lastVisitAt).toLowerCase()}',
      ?spent,
      if (loyaltyUnit != null && c.loyaltyBalance != null) '${c.loyaltyBalance} $loyaltyUnit',
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: AppAvatar(c.name, size: 40),
      title: Text(c.name, style: AppType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(id, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(visits, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (c.note != null && c.note!.isNotEmpty)
            Text('Catatan: ${c.note}',
                style: AppType.caption.copyWith(color: AppColors.warning), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: trailing,
    );
  }
}
