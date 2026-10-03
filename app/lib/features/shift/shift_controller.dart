import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_controller.dart';

/// Shift terbuka di tablet ini (null = belum dibuka). Uang hanya bisa bergerak di shift terbuka.
final shiftProvider = AsyncNotifierProvider<ShiftController, Map<String, dynamic>?>(ShiftController.new);

class ShiftController extends AsyncNotifier<Map<String, dynamic>?> {
  SessionController get _session => ref.read(sessionProvider.notifier);

  @override
  Future<Map<String, dynamic>?> build() async {
    final res = await _session.authed((api, token) => api.get('/shifts/current', token: token));
    return res['data'] as Map<String, dynamic>?;
  }

  Future<void> open(int openingCash) async {
    final res = await _session.authed(
        (api, token) => api.post('/shifts/open', token: token, data: {'opening_cash': openingCash}));
    state = AsyncData(res['data'] as Map<String, dynamic>);
  }

  /// Tutup shift; mengembalikan shift tertutup + ringkasan untuk ditampilkan & dicetak.
  Future<Map<String, dynamic>> close(int countedCash, String? note) async {
    final res = await _session.authed((api, token) => api.post('/shifts/close',
        token: token, data: {'counted_cash': countedCash, if (note != null && note.isNotEmpty) 'note': note}));
    state = const AsyncData(null);
    return res['data'] as Map<String, dynamic>;
  }
}
