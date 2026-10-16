import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'receipt_format.dart';

/// Pratinjau struk di layar: kertas putih selebar 32 karakter, logo di atas, baris tebal ikut tebal.
/// Di layar sempit diperkecil utuh (tidak dibungkus ulang) supaya sama dengan hasil cetak.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.lines, this.logoBase64});

  final List<PrintLine> lines;
  final String? logoBase64;

  static const _style = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.35, color: AppColors.ink);

  @override
  Widget build(BuildContext context) {
    final logo = logoBase64 == null || logoBase64!.isEmpty ? null : base64Decode(logoBase64!);
    // Lebar kertas = lebar nyata 32 karakter (tebal bisa lebih lebar di sebagian font monospace),
    // supaya angka di kanan tidak terpotong. Logo diskalakan sama (384 titik → lebar kertas).
    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style.merge(_style);
    double measure(FontWeight? w) => (TextPainter(
          text: TextSpan(text: 'W' * kLineWidth, style: base.copyWith(fontWeight: w)),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout())
            .width;
    final paperWidth = [measure(null), measure(FontWeight.w800)].reduce((a, b) => a > b ? a : b).ceilToDouble() + 2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4, vertical: AppSpace.s5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: AppColors.line),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: paperWidth,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (logo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                child: Image.memory(logo, width: paperWidth * 0.8, fit: BoxFit.contain, gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            Text.rich(
              TextSpan(children: [
                for (final (i, l) in lines.indexed)
                  TextSpan(
                    text: i == lines.length - 1 ? l.text : '${l.text}\n',
                    style: l.bold ? const TextStyle(fontWeight: FontWeight.w800) : null,
                  ),
              ]),
              softWrap: false,
              style: _style,
            ),
          ]),
        ),
      ),
    );
  }
}
