/// Alamat server API, ditanam saat build: `flutter build apk --dart-define=API_URL=https://api.strukasir.id`.
/// Kosong (build development) → layar daftar/masuk menampilkan kolom "Alamat server".
const String kApiUrl = String.fromEnvironment('API_URL');
