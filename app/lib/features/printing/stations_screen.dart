import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';
import '../menu/menu_controller.dart';
import 'printer_service.dart';
import 'stations.dart';
import '../../core/ui/toast.dart';

/// Pengaturan → Tiket bar / dapur (per tablet): stasiun, printernya, dan kategori yang dicetak.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stations = ref.watch(stationsProvider).value ?? const <TicketStation>[];
    final menu = ref.watch(menuProvider).value?.menu;
    Future<void> save(List<TicketStation> list) => ref.read(stationsProvider.notifier).save(list);

    Future<void> edit([int? index]) async {
      final result = await showDialog<TicketStation>(
        context: context,
        builder: (_) => _StationForm(station: index == null ? null : stations[index]),
      );
      if (result == null) return;
      final list = [...stations];
      index == null ? list.add(result) : list[index] = result;
      await save(list);
    }

    Future<void> test(TicketStation s) async {
      final messenger = AppToast.of(context);
      try {
        await ref.read(printerProvider.notifier).printTo(
              s.printerMac,
              kitchenTicket(
                station: s.name,
                number: 'TES-0001',
                label: 'Tes tiket',
                items: const [TicketItem(qty: 1, name: 'Contoh minuman', categoryId: '', options: 'Cold, Less sugar')],
                at: DateTime.now(),
              ),
            );
        messenger.showSnackBar(SnackBar(content: Text('Tes tiket ${s.name} terkirim.')));
      } on PrintException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceApp,
      appBar: AppBar(title: const Text('Tiket bar / dapur')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah stasiun'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(context.isCompact ? AppSpace.s3 : AppSpace.s5, AppSpace.s4,
            context.isCompact ? AppSpace.s3 : AppSpace.s5, 96),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  'Saat order disimpan (Open Bill) atau dibayar, item baru langsung tercetak sebagai tiket di stasiun ini '
                  '(tanpa harga). Tambahan pesanan di Open Bill bertanda "TAMBAHAN". Pengaturan ini khusus tablet ini.',
                  style: AppType.body.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpace.s4),
                if (stations.isEmpty)
                  const AppEmptyState(
                    icon: Icons.local_cafe_rounded,
                    title: 'Belum ada stasiun',
                    message: 'Contoh: "Bar" untuk minuman di printer struk yang sama, "Dapur" untuk makanan di printer kedua.',
                  ),
                for (final (i, s) in stations.indexed)
                  Card(
                    child: ListTile(
                      title: Text(s.name, style: AppType.bodyStrong),
                      subtitle: Text(
                        [
                          s.printerMac == null ? 'Printer struk' : (s.printerName ?? s.printerMac!),
                          s.categoryIds.isEmpty
                              ? 'Semua produk'
                              : s.categoryIds.map((id) => menu?.category(id)?.name ?? '?').join(', '),
                          if (s.copies > 1) '${s.copies} lembar',
                        ].join(' · '),
                        style: AppType.caption.copyWith(color: AppColors.inkMuted),
                      ),
                      onTap: () => edit(i),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(tooltip: 'Tes cetak', onPressed: () => test(s), icon: const Icon(Icons.print_rounded)),
                        IconButton(
                          tooltip: 'Hapus',
                          onPressed: () => save([...stations]..removeAt(i)),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationForm extends ConsumerStatefulWidget {
  const _StationForm({this.station});

  final TicketStation? station;

  @override
  ConsumerState<_StationForm> createState() => _StationFormState();
}

class _StationFormState extends ConsumerState<_StationForm> {
  late final _name = TextEditingController(text: widget.station?.name ?? '');
  late String? _mac = widget.station?.printerMac;
  late String? _printerName = widget.station?.printerName;
  late final Set<String> _categories = {...?widget.station?.categoryIds};
  late int _copies = widget.station?.copies ?? 1;
  List<BluetoothInfo>? _paired;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(printerProvider.notifier).pairedPrinters().then((p) {
      if (mounted) setState(() => _paired = p);
    }).catchError((Object e) {
      if (mounted) setState(() => _paired = const []);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(menuProvider).value?.menu.activeCategories ?? const [];
    final receiptMac = ref.watch(printerProvider).value?.mac;
    final others = (_paired ?? const <BluetoothInfo>[]).where((p) => p.macAdress != receiptMac).toList();
    return AlertDialog(
      scrollable: true,
      title: Text(widget.station == null ? 'Tambah stasiun' : 'Ubah stasiun'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            maxLength: 20,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Nama stasiun', hintText: 'mis. Bar, Dapur', errorText: _error, counterText: ''),
          ),
          const SizedBox(height: AppSpace.s3),
          DropdownButtonFormField<String>(
            initialValue: _mac ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Printer'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Printer struk (sama)')),
              if (_mac != null && others.every((p) => p.macAdress != _mac))
                DropdownMenuItem(value: _mac!, child: Text(_printerName ?? _mac!)),
              for (final p in others) DropdownMenuItem(value: p.macAdress, child: Text(p.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _mac = v == null || v.isEmpty ? null : v;
              _printerName = others.where((p) => p.macAdress == v).firstOrNull?.name ?? _printerName;
            }),
          ),
          if (_paired != null && others.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.s1),
              child: Text('Printer kedua belum di-pair di Bluetooth tablet.', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
            ),
          const SizedBox(height: AppSpace.s3),
          Text('Kategori yang dicetak (kosong = semua produk)', style: AppType.caption.copyWith(color: AppColors.inkMuted)),
          const SizedBox(height: AppSpace.s2),
          Wrap(spacing: AppSpace.s2, runSpacing: AppSpace.s2, children: [
            for (final c in categories)
              FilterChip(
                label: Text(c.name),
                selected: _categories.contains(c.id),
                onSelected: (v) => setState(() => v ? _categories.add(c.id) : _categories.remove(c.id)),
              ),
          ]),
          const SizedBox(height: AppSpace.s3),
          Row(children: [
            Expanded(child: Text('Jumlah lembar', style: AppType.body)),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2'))],
              selected: {_copies},
              onSelectionChanged: (v) => setState(() => _copies = v.first),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return setState(() => _error = 'Isi nama stasiun');
            Navigator.pop(
              context,
              TicketStation(
                name: _name.text.trim(),
                printerMac: _mac,
                printerName: _mac == null ? null : _printerName,
                categoryIds: _categories.toList(),
                copies: _copies,
              ),
            );
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
