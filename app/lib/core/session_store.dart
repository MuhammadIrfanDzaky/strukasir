import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Penyimpanan sesi di Android Keystore (terenkripsi), bukan SharedPreferences biasa.
///
/// - `serverUrl` + `deviceToken` + `device`: diisi sekali saat owner mendaftarkan tablet.
/// - `userToken` + `user`: diisi setiap login PIN, dihapus saat logout / kedaluwarsa.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _serverUrl = 'server_url';
  static const _deviceToken = 'device_token';
  static const _device = 'device';
  static const _userToken = 'user_token';
  static const _user = 'user';
  static const _installId = 'install_id';

  /// UUID per instalasi, dikirim saat daftar tablet. Daftar ulang (mis. setelah timeout) tidak
  /// membuat tablet ganda di server.
  Future<String> installId() async {
    final existing = await _storage.read(key: _installId);
    if (existing != null) return existing;
    final id = const Uuid().v4();
    await _storage.write(key: _installId, value: id);
    return id;
  }

  Future<String?> serverUrl() => _storage.read(key: _serverUrl);
  Future<String?> deviceToken() => _storage.read(key: _deviceToken);
  Future<String?> userToken() => _storage.read(key: _userToken);

  Future<Map<String, dynamic>?> device() => _readJson(_device);
  Future<Map<String, dynamic>?> user() => _readJson(_user);

  Future<void> saveDevice({
    required String serverUrl,
    required String token,
    required Map<String, dynamic> device,
  }) async {
    await _storage.write(key: _serverUrl, value: serverUrl);
    await _storage.write(key: _deviceToken, value: token);
    await _storage.write(key: _device, value: jsonEncode(device));
  }

  Future<void> saveUser({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    await _storage.write(key: _userToken, value: token);
    await _storage.write(key: _user, value: jsonEncode(user));
  }

  Future<void> clearUser() async {
    await _storage.delete(key: _userToken);
    await _storage.delete(key: _user);
  }

  /// Lepas tablet dari kedai (mis. tablet dicabut owner).
  Future<void> clearAll() => _storage.deleteAll();

  Future<Map<String, dynamic>?> _readJson(String key) async {
    final raw = await _storage.read(key: key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }
}
