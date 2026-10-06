import 'package:flutter/widgets.dart';

/// Kelas lebar layar (mengikuti Material 3): HP portrait → compact, HP landscape / tablet kecil
/// portrait → medium, tablet → expanded.
enum WidthClass { compact, medium, expanded }

extension ScreenSize on BuildContext {
  Size get screen => MediaQuery.sizeOf(this);

  WidthClass get widthClass => widthClassOf(screen.width);

  bool get isCompact => widthClass == WidthClass.compact;

  /// Layar pendek: HP landscape. Kurangi tinggi bar, sembunyikan dekorasi, buat isi bisa di-scroll.
  bool get isShort => screen.height < 500;
}

WidthClass widthClassOf(double width) => width < 600
    ? WidthClass.compact
    : width < 840
    ? WidthClass.medium
    : WidthClass.expanded;

/// Jumlah kolom grid dari lebar tersedia: sebanyak mungkin dengan lebar minimum [minItem].
int columnsFor(double width, {required double minItem, double spacing = 12, int min = 1, int max = 6}) =>
    ((width + spacing) / (minItem + spacing)).floor().clamp(min, max);
