import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'api_client.dart';
import 'auth_service.dart';

class AudioService {
  static final AudioService shared = AudioService._();
  AudioService._();

  final _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentPath;

  bool get isRecording => _isRecording;

  /// Inicia la grabación.
  /// El paquete `record` pide el permiso de micrófono automáticamente en iOS/Android.
  /// Devuelve false si no se concede el permiso.
  Future<bool> startRecording() async {
    // record v6 maneja el permiso internamente
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    final dir = await getTemporaryDirectory();
    _currentPath = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: _currentPath!,
    );
    _isRecording = true;
    return true;
  }

  /// Detiene la grabación y devuelve el path del archivo.
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    return path;
  }

  /// Cancela la grabación sin guardar.
  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder.cancel();
      _isRecording = false;
      if (_currentPath != null) {
        final f = File(_currentPath!);
        if (await f.exists()) await f.delete();
      }
    }
  }

  /// Obsoleto: las URLs ahora son del proxy de buddy-admin (no expiran).
  /// Se mantiene por compatibilidad con audios viejos (devuelve null).
  Future<String?> refreshSignedUrl(String oldUrl) async => null;

  /// Sube el audio a buddy-admin (que lo guarda en el storage) y devuelve la
  /// URL del proxy autenticado. La app NO sube directo a Supabase.
  Future<String> uploadAudio(String localPath, String matchId) async {
    final file  = File(localPath);
    final bytes = await file.readAsBytes();
    final token = AuthService.shared.accessToken;

    final resp = await http.post(
      Uri.parse('${ApiClient.baseUrl}/messages/$matchId/audio'),
      headers: {
        'Authorization': 'Bearer ${token ?? ''}',
        'Content-Type': 'audio/mp4',
      },
      body: bytes,
    );
    if (resp.statusCode != 200) {
      throw Exception('No se pudo subir el audio (${resp.statusCode})');
    }
    final path = jsonDecode(resp.body)['path'] as String;

    try { await file.delete(); } catch (_) {}

    // URL estable del proxy (no expira); se reproduce con el token en el header.
    return '${ApiClient.baseUrl}/messages/audio-file?path=${Uri.encodeQueryComponent(path)}';
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
