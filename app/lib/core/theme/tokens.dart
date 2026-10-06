import 'package:flutter/material.dart';

/// Token Strukasir Design System. Nama & nilai sama persis dengan `tokens.json` di artifact
/// design system; ubah di sana dulu, lalu salin ke sini.
///
/// Nama token = peran (primary, accent, success…), bukan nama warna, supaya ganti merek cukup di file ini.
abstract final class AppColors {
  // Brand: indigo (aksi & seleksi) + amber (aksen merek, hemat)
  static const primary = Color(0xFF3730A3);
  static const primaryStrong = Color(0xFF312E81);
  static const primarySoft = Color(0xFFE0E7FF);
  static const primaryOnDark = Color(0xFFA5B4FC);
  static const onPrimary = Color(0xFFFFFFFF);
  static const accent = Color(0xFFF59E0B);
  static const accentSoft = Color(0xFFFEF3C7);
  static const onAccent = Color(0xFF0F172A);

  // Netral (slate)
  static const ink = Color(0xFF0F172A);
  static const inkMuted = Color(0xFF475569);
  static const inkDisabled = Color(0xFF94A3B8);
  static const onInk = Color(0xFFF8FAFC);
  static const onInkMuted = Color(0xFFCBD5E1);
  static const surfaceApp = Color(0xFFF8FAFC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSunken = Color(0xFFF1F5F9);
  static const line = Color(0xFFE2E8F0);
  static const lineStrong = Color(0xFF7C8BA1);

  // Status
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFDCFCE7);
  static const warning = Color(0xFF92400E);
  static const warningSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEE2E2);

  static const focusRing = primary;
}

abstract final class AppSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 999.0;

  static final smAll = BorderRadius.circular(sm);
  static final mdAll = BorderRadius.circular(md);
  static final lgAll = BorderRadius.circular(lg);
  static final xlAll = BorderRadius.circular(xl);
}

abstract final class AppSize {
  /// Target sentuh minimum.
  static const touch = 48.0;

  /// Tombol aksi utama (Bayar, Daftarkan).
  static const touchLg = 56.0;
  static const topBar = 64.0;
  static const rail = 104.0;
}

abstract final class AppShadow {
  static const raised = [
    BoxShadow(color: Color(0x0F0F172A), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0F0F172A), offset: Offset(0, 2), blurRadius: 8),
  ];
}

/// Skala tipe Plus Jakarta Sans. Semua gaya memakai angka tabular agar nominal rupiah sejajar.
abstract final class AppType {
  static const family = 'PlusJakartaSans';
  static const _tnum = [FontFeature.tabularFigures()];

  static const display = TextStyle(
      fontFamily: family, fontSize: 40, height: 48 / 40, fontWeight: FontWeight.w800, letterSpacing: -0.8, fontFeatures: _tnum);
  static const headline = TextStyle(
      fontFamily: family, fontSize: 28, height: 36 / 28, fontWeight: FontWeight.w800, letterSpacing: -0.3, fontFeatures: _tnum);
  static const titleLg = TextStyle(
      fontFamily: family, fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w700, fontFeatures: _tnum);
  static const title = TextStyle(
      fontFamily: family, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w700, fontFeatures: _tnum);
  static const body = TextStyle(
      fontFamily: family, fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w400, fontFeatures: _tnum);
  static const bodyStrong = TextStyle(
      fontFamily: family, fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w600, fontFeatures: _tnum);
  static const label = TextStyle(
      fontFamily: family, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w700, letterSpacing: 0.1, fontFeatures: _tnum);
  static const caption = TextStyle(
      fontFamily: family, fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w500, fontFeatures: _tnum);
  static const overline = TextStyle(
      fontFamily: family, fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w700, letterSpacing: 0.9, fontFeatures: _tnum);
  static const moneyLg = TextStyle(
      fontFamily: family, fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w800, letterSpacing: -0.2, fontFeatures: _tnum);
}
