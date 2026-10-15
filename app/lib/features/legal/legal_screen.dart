import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import '../../core/ui/components.dart';
import '../../core/ui/responsive.dart';

/// Dokumen legal yang dibundel di app (salinan `docs/legal/*.md`, dicek sama oleh tes).
enum LegalDoc {
  terms('Syarat & Ketentuan', 'assets/legal/syarat-ketentuan.md'),
  privacy('Kebijakan Privasi', 'assets/legal/kebijakan-privasi.md');

  const LegalDoc(this.title, this.asset);

  final String title;
  final String asset;

  static final _cache = <LegalDoc, Future<String>>{};

  /// Isi dokumen (dimuat sekali, lalu dari cache).
  Future<String> load() => _cache[this] ??= rootBundle.loadString(asset);
}

/// Halaman Syarat & Ketentuan dan Kebijakan Privasi (dua tab).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.initial = LegalDoc.terms, this.texts});

  final LegalDoc initial;

  /// Isi dokumen yang sudah tersedia (tes); null = dimuat dari aset.
  final Map<LegalDoc, String>? texts;

  static Future<void> open(BuildContext context, [LegalDoc initial = LegalDoc.terms]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LegalScreen(initial: initial)));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: LegalDoc.values.length,
      initialIndex: initial.index,
      child: Scaffold(
        backgroundColor: AppColors.surfaceApp,
        appBar: AppBar(
          title: const Text('Syarat & kebijakan privasi'),
          bottom: TabBar(tabs: [for (final d in LegalDoc.values) Tab(text: d.title)]),
        ),
        body: TabBarView(children: [for (final d in LegalDoc.values) _LegalDocView(doc: d, text: texts?[d])]),
      ),
    );
  }
}

class _LegalDocView extends StatelessWidget {
  const _LegalDocView({required this.doc, this.text});

  final LegalDoc doc;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final pad = context.isCompact ? AppSpace.s4 : AppSpace.s6;
    return FutureBuilder<String>(
      future: text != null ? null : doc.load(),
      initialData: text,
      builder: (context, snap) {
        if (!snap.hasData) return const AppLoading();
        return SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: SimpleMarkdown.render(snap.data!),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Penampil markdown sederhana untuk dokumen legal: judul (#, ##), paragraf, daftar (- / 1.), tabel, garis (---),
/// **tebal**, `kode`, dan [tautan](url) (ditampilkan sebagai teks).
abstract final class SimpleMarkdown {
  static List<Widget> render(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final out = <Widget>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();
      if (t.isEmpty) {
        i++;
        continue;
      }
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(t);
      if (heading != null) {
        final level = heading.group(1)!.length;
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : (level == 1 ? AppSpace.s2 : AppSpace.s6), bottom: AppSpace.s2),
          child: Text.rich(_inline(heading.group(2)!),
              style: level == 1 ? AppType.headline : (level == 2 ? AppType.title : AppType.bodyStrong)),
        ));
        i++;
        continue;
      }
      if (t == '---') {
        out.add(const Padding(padding: EdgeInsets.symmetric(vertical: AppSpace.s3), child: Divider(height: 1)));
        i++;
        continue;
      }
      if (t.startsWith('|')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final cells = lines[i].trim().replaceAll(RegExp(r'^\||\|$'), '').split('|').map((c) => c.trim()).toList();
          if (!cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) rows.add(cells);
          i++;
        }
        out.add(Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.s2), child: _table(rows)));
        continue;
      }
      final item = RegExp(r'^(-|\d+\.)\s+(.*)$').firstMatch(t);
      if (item != null) {
        final items = <(String, String)>[];
        while (i < lines.length) {
          final m = RegExp(r'^(-|\d+\.)\s+(.*)$').firstMatch(lines[i].trim());
          if (m != null) {
            items.add((m.group(1)!, m.group(2)!));
          } else if (lines[i].startsWith('  ') && lines[i].trim().isNotEmpty && items.isNotEmpty) {
            items.last = (items.last.$1, '${items.last.$2} ${lines[i].trim()}'); // baris lanjutan
          } else {
            break;
          }
          i++;
        }
        for (final (marker, text) in items) {
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 28, child: Text(marker == '-' ? '•' : marker, style: AppType.body.copyWith(color: AppColors.inkMuted))),
              Expanded(child: Text.rich(_inline(text), style: AppType.body.copyWith(height: 1.5))),
            ]),
          ));
        }
        continue;
      }
      // Paragraf: gabungkan baris berturut-turut.
      final buf = <String>[];
      while (i < lines.length) {
        final l = lines[i].trim();
        if (l.isEmpty || l.startsWith('#') || l.startsWith('|') || l == '---' || RegExp(r'^(-|\d+\.)\s+').hasMatch(l)) break;
        buf.add(l);
        i++;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.s3),
        child: Text.rich(_inline(buf.join(' ')), style: AppType.body.copyWith(height: 1.55)),
      ));
    }
    return out;
  }

  static Widget _table(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return Table(
      border: TableBorder.all(color: AppColors.line),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (var r = 0; r < rows.length; r++)
          TableRow(
            decoration: BoxDecoration(color: r == 0 ? AppColors.surfaceSunken : AppColors.surface),
            children: [
              for (var c = 0; c < columns; c++)
                Padding(
                  padding: const EdgeInsets.all(AppSpace.s2),
                  child: Text.rich(
                    _inline(c < rows[r].length ? rows[r][c] : ''),
                    style: (r == 0 ? AppType.label : AppType.caption).copyWith(color: AppColors.ink, height: 1.4),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// **tebal**, `kode`, [teks](url) → teks.
  static TextSpan _inline(String text) {
    final cleaned = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!).replaceAll('`', '');
    final spans = <TextSpan>[];
    final parts = cleaned.split('**');
    for (var k = 0; k < parts.length; k++) {
      if (parts[k].isEmpty) continue;
      spans.add(TextSpan(text: parts[k], style: k.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null));
    }
    return TextSpan(children: spans);
  }
}
