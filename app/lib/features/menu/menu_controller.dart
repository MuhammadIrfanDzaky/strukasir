import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';
import '../session/session_controller.dart';
import 'menu_models.dart';

/// Status menu: data yang sedang dipakai + apakah itu salinan cache (server tidak terjangkau).
class MenuState {
  const MenuState(this.menu, {this.fromCache = false, this.refreshError});

  final Menu menu;
  final bool fromCache;
  final String? refreshError;
}

final menuProvider = AsyncNotifierProvider<MenuController, MenuState>(MenuController.new);

/// Menu di-cache sebagai file JSON di tablet. Saat dibuka: tampilkan cache dulu (cepat & tetap
/// jalan tanpa internet), lalu segarkan dari server di belakang layar.
class MenuController extends AsyncNotifier<MenuState> {
  @override
  Future<MenuState> build() async {
    final cached = await _readCache();
    if (cached != null) {
      Future.microtask(refresh);
      return MenuState(cached, fromCache: true);
    }
    return MenuState(await _fetchAndCache());
  }

  /// Ambil menu terbaru dari server. Jika gagal, tetap pakai menu yang ada.
  Future<void> refresh() async {
    try {
      final menu = await _fetchAndCache();
      state = AsyncData(MenuState(menu));
    } on ApiException catch (e) {
      final current = state.value;
      if (current != null) {
        state = AsyncData(MenuState(current.menu, fromCache: true, refreshError: e.message));
      } else {
        state = AsyncError(e, StackTrace.current);
      }
    }
  }

  Future<Menu> _fetchAndCache() async {
    final json = await ref.read(sessionProvider.notifier).authed((api, token) => api.get('/menu', token: token));
    final menu = Menu.fromJson(json);
    await (await _cacheFile()).writeAsString(jsonEncode(json));
    return menu;
  }

  Future<Menu?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      return Menu.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null; // cache rusak / format lama → abaikan, ambil ulang dari server
    }
  }

  /// Satu file per tablet terdaftar, supaya menu kedai lain tidak pernah ikut tampil.
  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    final deviceId = switch (ref.read(sessionProvider).value) {
      LoggedIn(:final device) || NeedsLogin(:final device) => device.id,
      _ => 'none',
    };
    return File('${dir.path}/menu_cache_$deviceId.json');
  }
}
