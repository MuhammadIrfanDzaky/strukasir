/// Jam kedai untuk menilai jadwal promo, sama dengan server: jam server (bukan jam tablet yang bisa
/// meleset) dalam zona waktu kedai (bukan zona tablet). Hasilnya "jam dinding" kedai: jam, menit,
/// tanggal & hari pada DateTime ini = waktu setempat kedai.
abstract final class ShopClock {
  static Duration _skew = Duration.zero;

  /// Dipanggil saat menu diambil dari server (`clock.now`): catat selisih jam tablet dengan server.
  static void sync(String? serverNow) {
    final server = serverNow == null ? null : DateTime.tryParse(serverNow);
    if (server != null) _skew = server.toUtc().difference(DateTime.now().toUtc());
  }

  /// Jam dinding kedai untuk [utc] (mis. jam order dibuat) atau sekarang. [utcOffsetMinutes] null
  /// (cache menu dari server lama) → jam tablet apa adanya.
  static DateTime wall(int? utcOffsetMinutes, [DateTime? utc]) {
    if (utcOffsetMinutes == null) return (utc ?? DateTime.now()).toLocal();
    final u = utc?.toUtc() ?? DateTime.now().toUtc().add(_skew);
    return u.add(Duration(minutes: utcOffsetMinutes));
  }
}
