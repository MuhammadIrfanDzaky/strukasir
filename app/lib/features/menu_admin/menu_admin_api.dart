import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../menu/menu_controller.dart';
import '../session/session_controller.dart';

final menuAdminApiProvider = Provider((ref) => MenuAdminApi(ref));

/// Operasi kelola menu (khusus izin `menu.manage`). Setiap perubahan memuat ulang menu,
/// sehingga layar kasir di tablet ini langsung ikut berubah.
class MenuAdminApi {
  MenuAdminApi(this._ref);

  final Ref _ref;

  Future<void> saveCategory({String? id, required String name, required bool active, required int sort}) =>
      _write((api, token) {
        final data = {'name': name.trim(), 'active': active, 'sort': sort};
        return id == null
            ? api.post('/categories', data: data, token: token)
            : api.put('/categories/$id', data: data, token: token);
      });

  Future<void> deleteCategory(String id) => _write((api, token) => api.delete('/categories/$id', token: token));

  Future<void> saveProduct({
    String? id,
    required String categoryId,
    required String name,
    required int price,
    required bool active,
    required bool soldOut,
    required List<String> modifierGroupIds,
    String? code,
    int? cost,
    bool favorite = false,
  }) =>
      _write((api, token) {
        final data = {
          'category_id': categoryId,
          'code': code?.trim() ?? '',
          'name': name.trim(),
          'price': price,
          'cost': cost,
          'favorite': favorite,
          'active': active,
          'sold_out': soldOut,
          'modifier_group_ids': modifierGroupIds,
        };
        return id == null
            ? api.post('/products', data: data, token: token)
            : api.put('/products/$id', data: data, token: token);
      });

  Future<void> saveModifierGroup({
    String? id,
    required String name,
    required int minSelect,
    required int maxSelect,
    required List<Map<String, dynamic>> modifiers,
  }) =>
      _write((api, token) {
        final data = {'name': name.trim(), 'min_select': minSelect, 'max_select': maxSelect, 'modifiers': modifiers};
        return id == null
            ? api.post('/modifier-groups', data: data, token: token)
            : api.put('/modifier-groups/$id', data: data, token: token);
      });

  Future<void> deleteModifierGroup(String id) =>
      _write((api, token) => api.delete('/modifier-groups/$id', token: token));

  /// Import produk dari teks CSV. `dryRun` = hanya periksa & hitung (pratinjau), tidak menyimpan.
  /// Mengembalikan ringkasan server: created, updated, categories_created, errors[{row, message}].
  Future<Map<String, dynamic>> importProducts(String csv, {required bool dryRun}) async {
    try {
      final res = await _ref.read(sessionProvider.notifier).authed(
            (api, token) => api.post('/products/import', token: token, data: {'csv': csv, 'dry_run': dryRun}),
          );
      if (!dryRun) await _ref.read(menuProvider.notifier).refresh();
      return res['data'] as Map<String, dynamic>;
    } on ApiException catch (e) {
      // 422 dengan daftar kesalahan per baris tetap dikembalikan sebagai hasil pratinjau.
      final data = e.body?['data'];
      if (data is Map<String, dynamic>) return data;
      rethrow;
    }
  }

  Future<void> _write(Future<Object?> Function(ApiClient api, String token) call) async {
    await _ref.read(sessionProvider.notifier).authed((api, token) => call(api, token));
    await _ref.read(menuProvider.notifier).refresh();
  }
}
