import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
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
  const SessionUser({
    required this.id,
    required this.name,
    required this.role,
    required this.permissions,
    this.email,
    this.emailVerified = true,
  });

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        id: j['id'] as String,
        name: j['name'] as String,
        role: j['role'] as String,
        permissions: (j['permissions'] as List).cast<String>().toSet(),
        email: j['email'] as String?,
        // Sesi lama (sebelum ada verifikasi email) dianggap terverifikasi agar tidak mengganggu.
        emailVerified: j['email_verified'] as bool? ?? true,
      );

  final String id;
  final String name;
  final String role;
  final Set<String> permissions;

  /// Hanya owner yang punya email.
  final String? email;
  final bool emailVerified;

  bool can(String permission) => permissions.contains(permission);

  SessionUser copyWith({bool? emailVerified}) => SessionUser(
      id: id, name: name, role: role, permissions: permissions, email: email,
      emailVerified: emailVerified ?? this.emailVerified);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'permissions': permissions.toList(),
        'email': email,
        'email_verified': emailVerified,
      };
}

/// Isian form "Daftar usaha baru".
class SignupData {
  const SignupData({
    required this.businessName,
    required this.sector,
    this.sectorOther,
    this.salesMode,
    required this.provinceCode,
    required this.regencyCode,
    required this.ownerName,
    required this.email,
    required this.password,
    required this.pin,
    required this.emailCode,
    this.phone,
    this.address,
    this.plan,
    this.period,
    this.referralCode,
  });

  final String businessName;
  final String sector;

  /// Isian "Lainnya, sebutkan".
  final String? sectorOther;

  /// Null untuk usaha non makanan (tidak ditanya).
  final String? salesMode;
  final String provinceCode;
  final String regencyCode;
  final String ownerName;
  final String email;
  final String password;
  final String pin;

  /// Kode verifikasi dari email (POST /signup/email-code).
  final String emailCode;
  final String? phone;
  final String? address;

  /// Kode paket (gratis/mulai/tumbuh/juragan) & periode bayar (month/year).
  final String? plan;
  final String? period;

  /// Kode referral usaha pengajak (opsional).
  final String? referralCode;

  Map<String, dynamic> toJson() => {
        'business_name': businessName.trim(),
        'sector': sector,
        if (sectorOther != null && sectorOther!.trim().isNotEmpty) 'sector_other': sectorOther!.trim(),
        if (salesMode != null) 'sales_mode': salesMode,
        'province_code': provinceCode,
        'regency_code': regencyCode,
        'owner_name': ownerName.trim(),
        'email': email.trim(),
        'password': password,
        'pin': pin,
        'email_code': emailCode.trim(),
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
        if (address != null && address!.trim().isNotEmpty) 'address': address!.trim(),
        if (plan != null) 'plan': plan,
        if (period != null) 'period': period,
        if (referralCode != null && referralCode!.trim().isNotEmpty) 'referral_code': referralCode!.trim(),
        'terms': true,
      };
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
    // Alamat tertanam saat build (API_URL) selalu menang atas alamat yang tersimpan, supaya tablet
    // yang dulu didaftarkan ke alamat lain (mis. IP laptop) ikut pindah tanpa daftar ulang.
    final stored = await _store.serverUrl();
    final url = kApiUrl.isNotEmpty && stored != null ? kApiUrl : stored;
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

  /// Owner mendaftarkan tablet ini ke kedainya (sekali saja). Nama tablet kosong → server memberi "Tablet N".
  Future<void> registerDevice({
    required String serverUrl,
    required String email,
    required String password,
    String? deviceName,
    String? otp,
    String? outletId,
  }) async {
    final res = await ApiClient(baseUrl: serverUrl).post('/devices/register', data: {
      'outlet_id': ?outletId,
      'email': email.trim(),
      'password': password,
      if (deviceName != null && deviceName.trim().isNotEmpty) 'device_name': deviceName.trim(),
      if (otp != null && otp.trim().isNotEmpty) 'otp': otp.trim(),
      'device_id': await _store.installId(),
    });
    await _saveRegistration(serverUrl, res);
  }

  /// Daftar usaha baru: server membuat usaha + akun owner + tablet ini (tablet pertama),
  /// lalu owner langsung masuk dengan PIN yang baru dibuat.
  Future<void> signup({required String serverUrl, required SignupData data}) async {
    final res = await ApiClient(baseUrl: serverUrl).post('/signup', data: {
      ...data.toJson(),
      'device_id': await _store.installId(),
    });
    await _saveRegistration(serverUrl, res);
    await pinLogin(res['owner_id'] as String, data.pin);
  }

  /// Kirim kode verifikasi ke email calon owner (sebelum usaha dibuat). Mengembalikan pesan.
  Future<String> sendSignupCode({required String serverUrl, required String email, String? ownerName}) async {
    final res = await ApiClient(baseUrl: serverUrl).post('/signup/email-code', data: {
      'email': email.trim(),
      if (ownerName != null && ownerName.trim().isNotEmpty) 'owner_name': ownerName.trim(),
    });
    return res['message'] as String? ?? 'Kode dikirim.';
  }

  Future<void> _saveRegistration(String serverUrl, Map<String, dynamic> res) async {
    final device = DeviceInfo.fromJson({
      ...(res['device'] as Map<String, dynamic>),
      'tenant_name': (res['tenant'] as Map<String, dynamic>)['name'],
    });
    await _store.saveDevice(serverUrl: serverUrl, token: res['token'] as String, device: device.toJson());
    state = AsyncData(NeedsLogin(serverUrl, device));
  }

  /// Lupa password owner: kirim kode ke email. Respons sama walau email tidak terdaftar.
  Future<String> forgotPassword({required String serverUrl, required String email}) async {
    final res = await ApiClient(baseUrl: serverUrl).post('/auth/password/forgot', data: {'email': email.trim()});
    return res['message'] as String? ?? 'Kode dikirim bila email terdaftar.';
  }

  Future<void> resetPassword({
    required String serverUrl,
    required String email,
    required String code,
    required String password,
  }) =>
      ApiClient(baseUrl: serverUrl).post('/auth/password/reset',
          data: {'email': email.trim(), 'code': code.trim(), 'password': password});

  /// Owner yang login meminta kode verifikasi email. Mengembalikan pesan untuk ditampilkan.
  Future<String> sendEmailCode() async {
    final res = await authed((api, token) => api.post('/auth/email/send', token: token));
    return res['message'] as String? ?? 'Kode dikirim.';
  }

  Future<void> verifyEmail(String code) async {
    await authed((api, token) => api.post('/auth/email/verify', data: {'code': code.trim()}, token: token));
    final s = state.value;
    if (s is LoggedIn) {
      final user = s.user.copyWith(emailVerified: true);
      await _store.saveUser(token: s.token, user: user.toJson());
      state = AsyncData(LoggedIn(s.serverUrl, s.device, user, s.token));
    }
  }

  /// Owner mengeluarkan tablet ini dari usahanya: server mencabut tablet & semua sesinya,
  /// lalu data lokal dihapus dan app kembali ke layar Selamat datang (Daftar / Masuk).
  Future<void> unregisterDevice() async {
    await authed((api, token) => api.post('/devices/current/unregister', token: token));
    await _forgetDevice();
  }

  /// Dari layar pilih nama (belum login): owner memasukkan PIN untuk mengeluarkan tablet dari
  /// usaha dan kembali ke layar Selamat datang. Sesi owner tidak disimpan di tablet.
  Future<void> unregisterWithOwnerPin(String ownerId, String pin) async {
    final s = _requireDevice();
    final api = ApiClient(baseUrl: s.serverUrl);
    final res =
        await api.post('/auth/pin', data: {'user_id': ownerId, 'pin': pin}, token: await _store.deviceToken());
    await api.post('/devices/current/unregister', token: res['token'] as String);
    await _forgetDevice();
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
