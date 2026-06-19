import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  static const baseUrl = 'https://buddy-admin-cdc141eaaf6f.herokuapp.com/api';
  static final ApiClient shared = ApiClient._();
  ApiClient._();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${AuthService.shared.accessToken ?? ''}',
  };

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, Map<String, dynamic> body) => _send('POST', path, body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Envía la petición y, ante un 401 (token expirado), intenta refrescar la
  /// sesión UNA vez y reintentar. Evita loop en el propio endpoint de refresh.
  Future<dynamic> _send(String method, String path,
      [Map<String, dynamic>? body, bool isRetry = false]) async {
    final uri = Uri.parse('$baseUrl$path');
    final encoded = body != null ? jsonEncode(body) : null;

    http.Response res;
    switch (method) {
      case 'POST':   res = await http.post(uri, headers: _headers, body: encoded); break;
      case 'PATCH':  res = await http.patch(uri, headers: _headers, body: encoded); break;
      case 'DELETE': res = await http.delete(uri, headers: _headers); break;
      default:       res = await http.get(uri, headers: _headers);
    }

    // Auto-refresh en 401 (sesión expirada) y reintento único.
    // No se aplica al propio endpoint de auth para evitar recursión.
    if (res.statusCode == 401 && !isRetry && !path.startsWith('/auth/')) {
      final refreshed = await AuthService.shared.tryRefresh();
      if (refreshed) {
        return _send(method, path, body, true);
      }
    }

    return _handle(res);
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String msg = 'Error';
    try { msg = jsonDecode(res.body)['error'] ?? msg; } catch (_) {}
    throw ApiException(res.statusCode, msg);
  }
}
