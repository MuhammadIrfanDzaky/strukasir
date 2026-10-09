import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../session/session_controller.dart';
import 'member_tier.dart';

/// Pelanggan / member dari GET /customers. Untuk kasir: no HP tersamar (0812****7890) dan tanpa
/// total belanja / tanggal lahir; untuk owner semua kolom terisi.
class Customer {
  const Customer({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.note,
    this.visits = 0,
    this.lastVisitAt,
    this.birthDate,
    this.totalSpent,
    this.firstVisitAt,
    this.createdAt,
    this.loyaltyBalance,
    this.loyaltyExpiresAt,
    this.tier,
    this.creditBalance,
    this.creditLimit,
    this.creditLimitCustom = false,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        note: j['note'] as String?,
        visits: j['visits'] as int? ?? 0,
        lastVisitAt: _date(j['last_visit_at']),
        birthDate: j['birth_date'] as String?,
        totalSpent: j['total_spent'] as int?,
        firstVisitAt: _date(j['first_visit_at']),
        createdAt: _date(j['created_at']),
        loyaltyBalance: j['loyalty_balance'] as int?,
        loyaltyExpiresAt: _date(j['loyalty_expires_at']),
        tier: j['tier'] == null ? null : MemberTier.fromJson(j['tier'] as Map<String, dynamic>),
        creditBalance: j['credit_balance'] as int?,
        creditLimit: j['credit_limit'] as int?,
        creditLimitCustom: j['credit_limit_custom'] as bool? ?? false,
      );

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  final String id;
  final String code;
  final String name;
  final String? phone;
  final String? note;
  final int visits;
  final DateTime? lastVisitAt;

  /// YYYY-MM-DD; hanya owner.
  final String? birthDate;
  final int? totalSpent;
  final DateTime? firstVisitAt;
  final DateTime? createdAt;

  /// Saldo stempel / poin (null = program loyalitas tidak berjalan).
  final int? loyaltyBalance;

  /// Saldo hangus bila tidak ada transaksi sampai tanggal ini.
  final DateTime? loyaltyExpiresAt;

  /// Tingkat member sekarang (null = belum mencapai tingkat / fitur mati).
  final MemberTier? tier;

  /// Sisa kasbon (null = fitur kasbon mati).
  final int? creditBalance;

  /// Batas kasbon efektif (null = tanpa batas); [creditLimitCustom] = diatur khusus pelanggan ini.
  final int? creditLimit;
  final bool creditLimitCustom;

  /// Rata-rata belanja per kunjungan (owner).
  int? get average => totalSpent == null || visits == 0 ? null : totalSpent! ~/ visits;
}

/// +6281234567890 → 0812-3456-7890 (nomor luar negeri ditampilkan apa adanya).
String formatPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  if (!phone.startsWith('+62')) return phone;
  final local = '0${phone.substring(3)}';
  if (local.contains('*')) return local; // tersamar untuk kasir
  final parts = <String>[];
  for (var i = 0; i < local.length; i += 4) {
    parts.add(local.substring(i, i + 4 > local.length ? local.length : i + 4));
  }
  return parts.join('-');
}

/// "Hari ini", "Kemarin", "5 hari lalu", "3 bulan lalu".
String sinceLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Belum pernah belanja';
  final today = _dateOnly(now ?? DateTime.now());
  final days = today.difference(_dateOnly(at)).inDays;
  if (days <= 0) return 'Hari ini';
  if (days == 1) return 'Kemarin';
  if (days < 30) return '$days hari lalu';
  if (days < 365) return '${days ~/ 30} bulan lalu';
  return '${days ~/ 365} tahun lalu';
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class CustomerPage {
  const CustomerPage({required this.items, required this.total, required this.lastPage, this.segments, this.phoneRequired = true});

  final List<Customer> items;
  final int total;
  final int lastPage;

  /// Jumlah per kelompok (all, new, loyal, lost); hanya bila diminta (owner).
  final Map<String, int>? segments;
  final bool phoneRequired;
}

final customerApiProvider = Provider((ref) => CustomerApi(ref));

class CustomerApi {
  CustomerApi(this._ref);

  final Ref _ref;

  Future<T> _authed<T>(Future<T> Function(ApiClient api, String token) call) =>
      _ref.read(sessionProvider.notifier).authed(call);

  Future<CustomerPage> list({
    String query = '',
    String? segment,
    String sort = 'name',
    int page = 1,
    int perPage = 20,
    bool withCounts = false,
    String? tierId,
  }) async {
    final params = {
      if (query.trim().isNotEmpty) 'q': query.trim(),
      'segment': ?segment,
      'sort': sort,
      'page': '$page',
      'per_page': '$perPage',
      if (withCounts) 'with_counts': '1',
      'tier_id': ?tierId,
    };
    final res = await _authed((api, token) => api.get('/customers?${Uri(queryParameters: params).query}', token: token));
    final meta = res['meta'] as Map<String, dynamic>;
    return CustomerPage(
      items: (res['data'] as List).cast<Map<String, dynamic>>().map(Customer.fromJson).toList(),
      total: meta['total'] as int,
      lastPage: meta['last_page'] as int,
      phoneRequired: meta['phone_required'] as bool? ?? true,
      segments: (meta['segments'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as int)),
    );
  }

  /// Daftar baru (kasir & owner) atau ubah data (owner, [id] diisi).
  Future<Customer> save({String? id, required String name, String? phone, String? birthDate, String? note}) async {
    final data = {
      'name': name.trim(),
      'phone': phone?.trim() ?? '',
      'birth_date': birthDate ?? '',
      'note': note?.trim() ?? '',
    };
    final res = await _authed((api, token) => id == null
        ? api.post('/customers', data: data, token: token)
        : api.put('/customers/$id', data: data, token: token));
    return Customer.fromJson(res['data'] as Map<String, dynamic>);
  }

  /// Detail owner: data + `favorites` [{name, qty}] + `recent_orders` [{number, status, grand_total, …}].
  Future<Map<String, dynamic>> detail(String id) async {
    final res = await _authed((api, token) => api.get('/customers/$id', token: token));
    return res['data'] as Map<String, dynamic>;
  }

  /// Penyesuaian saldo stempel/poin oleh owner. Mengembalikan saldo baru.
  Future<int> adjustLoyalty(String id, int units, String note) async {
    final res = await _authed((api, token) =>
        api.post('/customers/$id/loyalty-adjust', token: token, data: {'units': units, 'note': note.trim()}));
    return (res['data'] as Map<String, dynamic>)['balance'] as int;
  }

  /// Catat pelunasan kasbon. Mengembalikan data pelunasan + `balance` (sisa kasbon).
  Future<Map<String, dynamic>> repayCredit(String customerId,
      {required String id, String? note, required String method, required int amount, int? tendered}) async {
    final res = await _authed((api, token) => api.post('/customers/$customerId/credit-repayments', token: token, data: {
          'id': id,
          'method': method,
          'amount': amount,
          'tendered': ?tendered,
          'note': ?note,
        }));
    return res['data'] as Map<String, dynamic>;
  }

  Future<int> reverseRepayment(String customerId, String repaymentId, String reason) async {
    final res = await _authed((api, token) =>
        api.post('/customers/$customerId/credit-repayments/$repaymentId/reverse', token: token, data: {'reason': reason}));
    return (res['data'] as Map<String, dynamic>)['balance'] as int;
  }

  /// Batas kasbon pelanggan (owner); null = ikut default kedai.
  Future<void> setCreditLimit(String id, int? limit) =>
      _authed((api, token) => api.put('/customers/$id/credit-limit', token: token, data: {'credit_limit': limit}));

  /// Kunci tingkat manual (owner); null = kembali otomatis dari belanja.
  Future<Customer> setTier(String id, String? tierId) async {
    final res = await _authed((api, token) => api.put('/customers/$id/tier', token: token, data: {'tier_id': tierId}));
    return Customer.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> anonymize(String id) => _authed((api, token) => api.post('/customers/$id/anonymize', token: token));

  /// Ringkasan server: created, updated, errors[{row, message}], saved.
  Future<Map<String, dynamic>> import(String csv, {required bool dryRun}) async {
    try {
      final res = await _authed((api, token) => api.post('/customers/import', token: token, data: {'csv': csv, 'dry_run': dryRun}));
      return res['data'] as Map<String, dynamic>;
    } on ApiException catch (e) {
      final data = e.body?['data'];
      if (data is Map<String, dynamic>) return data;
      rethrow;
    }
  }
}
