import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthService {
  static final AuthService shared = AuthService._();
  AuthService._();

  String? accessToken;
  String? refreshToken;
  String? userId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken  = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
    userId       = prefs.getString('user_id');
  }

  bool get isLoggedIn => accessToken != null && userId != null;

  // ── OTP Flow ──────────────────────────────────────────────────────────

  Future<void> sendOtp(String phone) async {
    await ApiClient.shared.post('/auth/otp', {'phone': phone});
  }

  /// Returns `null` on failure, or a map with `{ success, hasProfile }` on success.
  Future<Map<String, bool>?> verifyOtp(String phone, String otp) async {
    try {
      final data = await ApiClient.shared.post('/auth/otp/verify', {
        'phone': phone,
        'token': otp,
      });
      await _saveSession(data);
      final hasProfile = data['has_profile'] == true;
      return {'success': true, 'hasProfile': hasProfile};
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(dynamic data) async {
    accessToken  = data['access_token'];
    refreshToken = data['refresh_token'];
    userId       = data['user_id'];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token',  accessToken!);
    await prefs.setString('refresh_token', refreshToken!);
    await prefs.setString('user_id',       userId!);
  }

  Future<bool> tryRefresh() async {
    if (refreshToken == null) return false;
    try {
      final data = await ApiClient.shared.post('/auth/refresh', {
        'refresh_token': refreshToken,
      });
      await _saveSession(data);
      return true;
    } catch (_) {
      // Si el refresh falla (usuario eliminado, token expirado, etc.)
      // limpiamos la sesión para forzar el login
      await logout();
      return false;
    }
  }

  Future<void> logout() async {
    accessToken = refreshToken = userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
