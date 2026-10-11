import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/responsive.dart';

/// Satu jenis usaha (kode = enum `BusinessSector` di server).
class SectorOption {
  const SectorOption(this.code, this.label, {required this.group, required this.asksSalesMode});

  final String code;
  final String label;

  /// Judul kelompok, mis. "Makanan & minuman".
  final String group;

  /// Hanya usaha makanan & minuman yang ditanya cara berjualan.
  final bool asksSalesMode;
}

class RegionOption {
  const RegionOption(this.code, this.name, [this.children = const []]);

  final String code;
  final String name;

  /// Kota/kabupaten (untuk provinsi).
  final List<RegionOption> children;
}

/// Pilihan form "Daftar usaha baru" dari GET /signup/options.
class SignupOptions {
  const SignupOptions({required this.sectors, required this.salesModes, required this.provinces});

  factory SignupOptions.fromJson(Map<String, dynamic> j) => SignupOptions(
        sectors: [
          for (final g in (j['sectors'] as List).cast<Map<String, dynamic>>())
            for (final s in (g['items'] as List).cast<Map<String, dynamic>>())
              SectorOption(s['code'] as String, s['label'] as String,
                  group: g['label'] as String, asksSalesMode: s['asks_sales_mode'] as bool),
        ],
        salesModes: [
          for (final m in (j['sales_modes'] as List).cast<Map<String, dynamic>>())
            (m['code'] as String, m['label'] as String),
        ],
        provinces: [
          for (final p in (j['regions'] as List).cast<Map<String, dynamic>>())
            RegionOption(p['code'] as String, p['name'] as String, [
              for (final r in (p['regencies'] as List).cast<Map<String, dynamic>>())
                RegionOption(r['code'] as String, r['name'] as String),
            ]),
        ],
      );

  final List<SectorOption> sectors;
  final List<(String code, String label)> salesModes;
  final List<RegionOption> provinces;

  SectorOption? sector(String? code) => sectors.where((s) => s.code == code).firstOrNull;
  RegionOption? province(String? code) => provinces.where((p) => p.code == code).firstOrNull;
}

/// Pemuat pilihan (bisa diganti di tes). Kunci = alamat server.
final signupOptionsLoaderProvider = Provider<Future<SignupOptions> Function(String serverUrl)>(
  (ref) => (serverUrl) async => SignupOptions.fromJson(await ApiClient(baseUrl: serverUrl).get('/signup/options')),
);

/// Satu baris pilihan di [showOptionPicker].
class PickerItem<T> {
  const PickerItem(this.value, this.label, {this.group});

  final T value;
  final String label;

  /// Judul kelompok; item berurutan dengan judul sama dikelompokkan.
  final String? group;
}

/// Daftar pilihan dengan kotak cari & judul kelompok: lembar bawah di HP, dialog di layar lebar.
Future<T?> showOptionPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerItem<T>> items,
  T? selected,
  String searchHint = 'Cari',
}) {
  final body = _OptionPicker<T>(title: title, items: items, selected: selected, searchHint: searchHint);
  if (context.isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Layar pendek (HP landscape): tanpa pegangan & lebih tinggi supaya daftar tetap terlihat.
      showDragHandle: !context.isShort,
      builder: (_) => FractionallySizedBox(heightFactor: context.isShort ? 0.95 : 0.85, child: body),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640), child: body),
    ),
  );
}

class _OptionPicker<T> extends StatefulWidget {
  const _OptionPicker({required this.title, required this.items, required this.selected, required this.searchHint});

  final String title;
  final List<PickerItem<T>> items;
  final T? selected;
  final String searchHint;

  @override
  State<_OptionPicker<T>> createState() => _OptionPickerState<T>();
}

class _OptionPickerState<T> extends State<_OptionPicker<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    // Cocokkan nama item atau nama kelompoknya (mis. ketik "kesehatan").
    final items = q.isEmpty
        ? widget.items
        : widget.items
            .where((i) => i.label.toLowerCase().contains(q) || (i.group?.toLowerCase().contains(q) ?? false))
            .toList();

    final rows = <Widget>[];
    String? group;
    for (final item in items) {
      if (item.group != null && item.group != group) {
        group = item.group;
        rows.add(Container(
          color: AppColors.surfaceSunken,
          padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s4, AppSpace.s2),
          child: Text(group!, style: AppType.bodyStrong),
        ));
      }
      final selected = item.value == widget.selected;
      rows.add(ListTile(
        title: Text(item.label,
            style: AppType.body.copyWith(
                color: selected ? AppColors.primary : AppColors.ink, fontWeight: selected ? FontWeight.w700 : null)),
        trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
        selected: selected,
        selectedTileColor: AppColors.primarySoft,
        onTap: () => Navigator.of(context).pop(item.value),
      ));
    }

    final search = TextField(
      decoration: InputDecoration(hintText: widget.searchHint, prefixIcon: const Icon(Icons.search_rounded), isDense: true),
      onChanged: (v) => setState(() => _query = v),
    );
    final close =
        IconButton(tooltip: 'Tutup', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Layar pendek: judul disembunyikan, kotak cari + tutup dalam satu baris (hemat tinggi).
        if (context.isShort)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s2, AppSpace.s2, AppSpace.s2),
            child: Row(children: [Expanded(child: search), close]),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s3, AppSpace.s2, 0),
            child: Row(children: [Expanded(child: Text(widget.title, style: AppType.title)), close]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s3),
            child: search,
          ),
        ],
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text('Tidak ditemukan', style: AppType.body.copyWith(color: AppColors.inkMuted)))
              : ListView(children: rows),
        ),
      ],
    );
  }
}

/// Kolom form yang membuka [showOptionPicker] saat diketuk (tampilan seperti TextField biasa).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.errorText,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final IconData? icon;
  final String? errorText;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled && !loading ? onTap : null,
      borderRadius: AppRadius.mdAll,
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(labelText: label, suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(Icons.expand_more_rounded), errorText: errorText, enabled: enabled, ),
        child: value == null ? null : Text(value!, style: AppType.body, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
