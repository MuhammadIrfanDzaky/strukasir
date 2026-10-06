import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session_store.dart';

class DeviceInfo {
  const DeviceInfo({required this.id, required this.code, required this.name, required this.tenantName});

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        tenantName: j['tenant_name'] as String? ?? '',
      );

  final String id;
  final String code;
  final String name;
  final String tenantName;

  Map<String, dynamic> toJson() =>
      {'id': id, 'code': code, 'name': name, 'tenant_name': tenantName};
}

class SessionUser {
  const SessionUser({required this.id, required this.name, required this.role, required this.permissions});

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        permissions: (j['permissions'] as List).cast<String>().toSet(),
      );

  final String id;
  final String name;
  final String role;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'role': role, 'permissions': permissions.toList()};
}

class StaffMember {
  const StaffMember(this.id, this.name, this.role);

  final String id;
  final String name;
  final String role;
}

sealed class Session {
  const Session();
}

/// Tablet belum didaftarkan ke kedai mana pun.
class NeedsSetup extends Session {
  const NeedsSetup();
}

/// Tablet terdaftar, belum ada yang login PIN.
class NeedsLogin extends Session {
  const NeedsLogin(this.serverUrl, this.device);

  final String serverUrl;
  final DeviceInfo device;
}

class LoggedIn extends Session {
  const LoggedIn(this.serverUrl, this.device, this.user, this.token);

  final String serverUrl;
  final DeviceInfo device;
  final SessionUser user;
  final String token;
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final sessionProvider =
    AsyncNotifierProvider<SessionController, Session>(SessionController.new);

class SessionController extends AsyncNotifier<Session> {
  SessionStore get _store => ref.read(sessionStoreProvider);

  @override
  Future<Session> build() async {
    final url = await _store.serverUrl();
    final deviceJson = await _store.device();
    if (url == null || deviceJson == null || await _store.deviceToken() == null) {
      return const NeedsSetup();
    }
    final device = DeviceInfo.fromJson(deviceJson);

    final token = await _store.userToken();
    final userJson = await _store.user();
    if (token == null || userJson == null) return NeedsLogin(url, device);

    return LoggedIn(url, device, SessionUser.fromJson(userJson), token);
  }

  /// Owner mendaftarkan tablet ini ke kedainya (sekali saja).
  Future<void> registerDevice({
    required String serverUrl,
    required String email,
    required String password,
    required String deviceName,
    String? otp,
  }) async {
    final api = ApiClient(baseUrl: serverUrl);
    final res = await api.post('/devices/register', data: {
      'email': email.trim(),
      'password': password,
      'device_name': deviceName.trim(),
      if (otp != null && otp.trim().isNotEmpty) 'otp': otp.trim(),
      'device_id': await _store.installId(),
    });

    final device = DeviceInfo.fromJson({
      ...(res['device'] as Map<String, dynamic>),
      'tenant_name': (res['tenant'] as Map<String, dynamic>)['name'],
    });
    await _store.saveDevice(
        serverUrl: serverUrl, token: res['token'] as String, device: device.toJson());
    state = AsyncData(NeedsLogin(serverUrl, device));
  }

  Future<List<StaffMember>> staff() async {
    final s = _requireDevice();
    try {
      final res = await ApiClient(baseUrl: s.serverUrl)
          .get('/auth/staff', token: await _store.deviceToken());
      return (res['data'] as List)
          .cast<Map<String, dynamic>>()
          .map((u) => StaffMember(u['id'] as String, u['name'] as String, u['role'] as String))
          .toList();
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _forgetDevice();
      rethrow;
    }
  }

  Future<void> pinLogin(String userId, String pin) async {
    final s = _requireDevice();
    final res = await ApiClient(baseUrl: s.serverUrl).post('/auth/pin',
        data: {'user_id': userId, 'pin': pin}, token: await _store.deviceToken());

    final user = SessionUser.fromJson(res['user'] as Map<String, dynamic>);
    final token = res['token'] as String;
    await _store.saveUser(token: token, user: user.toJson());
    state = AsyncData(LoggedIn(s.serverUrl, s.device, user, token));
  }

  Future<void> logout() async {
    final s = state.value;
    if (s is LoggedIn) {
      try {
        await ApiClient(baseUrl: s.serverUrl).post('/auth/logout', token: s.token);
      } on ApiException {
        // Tetap logout lokal walau server tidak terjangkau; token kedaluwarsa sendiri.
      }
      await _store.clearUser();
      state = AsyncData(NeedsLogin(s.serverUrl, s.device));
    }
  }

  /// Jalankan panggilan API dengan token user. 401 = sesi habis → kembali ke layar PIN.
  Future<T> authed<T>(Future<T> Function(ApiClient api, String token) call) async {
    final s = state.value;
    if (s is! LoggedIn) throw ApiException('Silakan login terlebih dahulu.', status: 401);
    try {
      return await call(ApiClient(baseUrl: s.serverUrl), s.token);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _store.clearUser();
        state = AsyncData(NeedsLogin(s.serverUrl, s.device));
      }
      rethrow;
    }
  }

  ({String serverUrl, DeviceInfo device}) _requireDevice() => switch (state.value) {
        NeedsLogin(:final serverUrl, :final device) ||
        LoggedIn(:final serverUrl, :final device) =>
          (serverUrl: serverUrl, device: device),
        _ => throw ApiException('Tablet belum didaftarkan.'),
      };

  Future<void> _forgetDevice() async {
    await _store.clearAll();
    state = const AsyncData(NeedsSetup());
  }
}
