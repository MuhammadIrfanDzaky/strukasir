import 'package:dio/dio.dart';

/// Error dari API dalam bentuk yang siap ditampilkan ke kasir.
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.fieldErrors = const {}, this.body});

  final String message;
  final int? status;
  final Map<String, List<String>> fieldErrors;

  /// Isi respons JSON (untuk endpoint yang mengirim detail tambahan saat gagal, mis. import).
  final Map<String, dynamic>? body;

  bool get isUnauthorized => status == 401;

  /// Pesan validasi pertama untuk sebuah field (mis. `price`), jika ada.
  String? field(String name) => fieldErrors[name]?.first;

  @override
  String toString() => message;
}

/// Pembungkus Dio untuk API Strukasir (`/api/v1`). Token dipilih per panggilan:
/// token perangkat untuk daftar staf & login PIN, token user untuk sisanya.
class ApiClient {
  ApiClient({required String baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1',
              connectTimeout: const Duration(seconds: 8),
              // Longgar untuk koneksi kedai yang lambat; request order/bayar aman dikirim ulang.
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/json'},
            ));

  final Dio _dio;

  Future<Map<String, dynamic>> get(String path, {String? token}) =>
      _send(() => _dio.get(path, options: _auth(token)));

  Future<Map<String, dynamic>> post(String path,
          {Object? data, String? token}) =>
      _send(() => _dio.post(path, data: data, options: _auth(token)));

  Future<Map<String, dynamic>> put(String path,
          {Object? data, String? token}) =>
      _send(() => _dio.put(path, data: data, options: _auth(token)));

  Future<Map<String, dynamic>> delete(String path, {String? token}) =>
      _send(() => _dio.delete(path, options: _auth(token)));

  Options _auth(String? token) => Options(
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
      );

  Future<Map<String, dynamic>> _send(
      Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  static ApiException _toApiException(DioException e) {
    final response = e.response;
    if (response == null) {
      return ApiException(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout =>
          'Server tidak merespons. Periksa koneksi internet.',
        _ => 'Tidak bisa terhubung ke server. Periksa koneksi internet.',
      });
    }

    final data = response.data;
    final message = data is Map && data['message'] is String
        ? data['message'] as String
        : 'Terjadi kesalahan (${response.statusCode}).';

    final errors = <String, List<String>>{};
    if (data is Map && data['errors'] is Map) {
      (data['errors'] as Map).forEach((key, value) {
        errors['$key'] = (value as List).map((v) => '$v').toList();
      });
    }

    return ApiException(message,
        status: response.statusCode,
        fieldErrors: errors,
        body: data is Map<String, dynamic> ? data : null);
  }
}
