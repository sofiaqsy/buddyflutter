import 'dart:async';
import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/auth_service.dart';
import '../../core/audio_service.dart';
import '../../models/models.dart';
import '../../widgets/buddy_avatar.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/audio_player_bubble.dart';


class ChatScreen extends StatefulWidget {
  final Match match;
  const ChatScreen({super.key, required this.match});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final _msgCtrl   = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll    = ScrollController();
  List<Message> _messages = [];
  bool _loading      = true;
  bool _sending      = false;
  bool _hasMore      = true;
  bool _loadingMore  = false;
  late String _matchStatus;
  bool get _isClosed => _matchStatus == 'completed' || _matchStatus == 'cancelled';
  bool _recording  = false;
  bool _cancellingRecord = false; // se deslizó a la izquierda
  bool _uploadingAudio = false;
  http.Client? _sseClient;
  StreamSubscription? _sseSub;
  bool _sseClosedByUs = false;
  DateTime? _recordStart;
  Timer? _recordTimer;
  double _recordDragX = 0; // desplazamiento horizontal durante grabación

  // Session timer
  final _sessionStart = DateTime.now();
  Timer? _sessionTimer;
  int _sessionMinutes = 0;

  // Lugares del destino (para compartir en el chat con un toque)
  List<Map<String, dynamic>> _places = [];

  @override
  void initState() {
    super.initState();
    _matchStatus = widget.match.status;
    _msgCtrl.addListener(() => setState(() {}));
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus) {
        // Espera que la animación del teclado termine (~300ms iOS) y salta directo al final
        Future.delayed(const Duration(milliseconds: 350), () {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
    _loadMessages().then((_) => _subscribeRealtime());
    _loadPlaces();
    _scroll.addListener(_onScroll);
    _sessionTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _sessionMinutes = DateTime.now().difference(_sessionStart).inMinutes);
    });
  }

  // Tiempo real vía SSE de buddy-admin (el servidor hace de puente a Supabase).
  // La app NUNCA se conecta directo a Supabase Realtime.
  void _subscribeRealtime() => _connectSSE();

  Future<void> _connectSSE() async {
    if (_sseClosedByUs) return;
    final token = AuthService.shared.accessToken;
    if (token == null) { debugPrint('💬 [SSE] sin token'); return; }
    final uri = Uri.parse('${ApiClient.baseUrl}/messages/${widget.match.id}/stream');
    debugPrint('💬 [SSE] conectando $uri');
    try {
      _sseClient = http.Client();
      final req = http.Request('GET', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'text/event-stream';
      final resp = await _sseClient!.send(req);
      if (resp.statusCode == 401) {
        debugPrint('💬 [SSE] 401 → refrescando token');
        await AuthService.shared.tryRefresh();
        return _scheduleReconnect();
      }
      if (resp.statusCode != 200) {
        debugPrint('💬 [SSE] status ${resp.statusCode}');
        return _scheduleReconnect();
      }
      debugPrint('💬 [SSE] conectado');

      String event = 'message';
      final buffer = StringBuffer();
      _sseSub = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith(':')) return;                    // heartbeat/comentario
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          buffer.write(line.substring(5).trim());
        } else if (line.isEmpty) {                           // fin del frame
          final data = buffer.toString();
          buffer.clear();
          final ev = event;
          event = 'message';
          if (data.isEmpty) return;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (ev == 'match') {
              _handleMatchUpdate(json);
            } else {
              _handleIncomingMessage(json);
            }
          } catch (_) {}
        }
      },
      onError: (e) { debugPrint('💬 [SSE] error: $e'); _scheduleReconnect(); },
      onDone:  ()  { debugPrint('💬 [SSE] cerrado');    _scheduleReconnect(); });
    } catch (e) {
      debugPrint('💬 [SSE] excepción: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_sseClosedByUs || !mounted) return;
    _sseSub?.cancel(); _sseClient?.close();
    _sseSub = null; _sseClient = null;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_sseClosedByUs) _connectSSE();
    });
  }

  void _handleIncomingMessage(Map<String, dynamic> json) {
    final newMsg = Message.fromJson(json);
    if (_messages.any((m) => m.id == newMsg.id)) return;
    debugPrint('💬 [SSE] mensaje ${newMsg.id}');
    setState(() {
      List<Message> updated = List.of(_messages);
      if (newMsg.senderId == AuthService.shared.userId) {
        final placeholderIdx = updated.indexWhere(
          (m) => (m.id.startsWith('temp_') || m.id.startsWith('sent_'))
              && m.senderId == newMsg.senderId
              && m.content == newMsg.content,
        );
        if (placeholderIdx != -1) {
          updated[placeholderIdx] = newMsg;
          _messages = updated;
          return;
        }
      }
      updated.add(newMsg);
      _messages = updated;
    });
    _scrollToBottom();
  }

  void _handleMatchUpdate(Map<String, dynamic> json) {
    final newStatus = json['status'] as String?;
    if (newStatus != null && newStatus != _matchStatus && mounted) {
      setState(() => _matchStatus = newStatus);
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels <= 80 && _hasMore && !_loadingMore) {
      _loadMoreMessages();
    }
  }

  @override
  void dispose() {
    _sseClosedByUs = true;
    _sseSub?.cancel();
    _sseClient?.close();
    _recordTimer?.cancel();
    _sessionTimer?.cancel();
    _scroll.dispose();
    _msgCtrl.dispose();
    _inputFocus.dispose();
    AudioService.shared.cancelRecording();
    super.dispose();
  }

  // Carga los lugares del destino consultado por el viajero
  Future<void> _loadPlaces() async {
    final destId = widget.match.request?.destinationId;
    if (destId == null) return;
    try {
      final data = await ApiClient.shared.get('/buddy/zones/$destId');
      final list = (data is Map ? data['places'] : null) as List? ?? [];
      if (mounted) setState(() => _places = list.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  // Envía un lugar como tarjeta: place:lat|lng|nombre|dirección
  void _sendPlace(Map<String, dynamic> p) {
    final lat  = p['lat'];
    final lng  = p['lng'];
    final name = (p['name'] ?? 'Lugar').toString().replaceAll('|', ' ').trim();
    final addr = (p['address'] ?? '').toString().replaceAll('|', ' ').trim();
    _send('place:$lat|$lng|$name|$addr');
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await ApiClient.shared.get('/messages/${widget.match.id}?limit=30') as List;
      final msgs = list.map((j) => Message.fromJson(j)).toList();
      setState(() {
        _messages = msgs;
        _loading = false;
        _hasMore = msgs.length == 30;
      });
      _scrollToBottom();
    } catch (_) {
      if (!silent) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!_hasMore || _loadingMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    final oldest = _messages.first.createdAt.toUtc().toIso8601String();
    final before = Uri.encodeQueryComponent(oldest);
    try {
      final list = await ApiClient.shared.get(
        '/messages/${widget.match.id}?limit=30&before=$before',
      ) as List;
      final older = list.map((j) => Message.fromJson(j)).toList();
      final prevOffset = _scroll.position.maxScrollExtent;
      setState(() {
        _messages = [...older, ..._messages];
        _hasMore = older.length == 30;
      });
      // Keep scroll position so the user stays at the same message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          final newOffset = _scroll.position.maxScrollExtent - prevOffset;
          _scroll.jumpTo(newOffset.clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _msgCtrl.text).trim();
    if (text.isEmpty || _sending) return;
    if (preset == null) _msgCtrl.clear();

    // ── UI Optimista ────────────────────────────────────────────────────────
    // Insertamos el mensaje localmente ANTES de llamar al servidor.
    // El ID temporal empieza con "temp_" para identificarlo después.
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = Message(
      id: tempId,
      matchId: widget.match.id,
      senderId: AuthService.shared.userId ?? '',
      content: text,
      type: 'text',
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, tempMsg];
      _sending = true;
    });
    // Scroll inmediato — la lista ya tiene el ítem nuevo
    _scrollToBottom();

    try {
      final response = await ApiClient.shared.post('/messages/${widget.match.id}', {
        'sender_id': AuthService.shared.userId,
        'content': text,
        'type': 'text',
      });

      // Reemplazar el mensaje temporal con el mensaje real del servidor
      if (mounted) {
        setState(() {
          Message confirmed;
          try {
            // Si el servidor devuelve el mensaje creado, usarlo
            confirmed = Message.fromJson(response as Map<String, dynamic>);
          } catch (_) {
            // Si no devuelve JSON del mensaje, crear uno "confirmado"
            // sin el prefijo temp_ para que muestre opacidad completa
            confirmed = Message(
              id: 'sent_${DateTime.now().millisecondsSinceEpoch}',
              matchId: widget.match.id,
              senderId: AuthService.shared.userId ?? '',
              content: text,
              type: 'text',
              createdAt: DateTime.now(),
            );
          }
          _messages = _messages
              .map((m) => m.id == tempId ? confirmed : m)
              .toList();
        });
      }

    } catch (e) {
      // Revertir mensaje optimista en caso de error
      if (mounted) {
        setState(() => _messages = _messages.where((m) => m.id != tempId).toList());
        if (preset == null) _msgCtrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e'), backgroundColor: BuddyColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Audio recording ──────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    final ok = await AudioService.shared.startRecording();
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permiso de micrófono denegado'), backgroundColor: BuddyColors.error),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _cancellingRecord = false;
      _recordDragX = 0;
      _recordStart = DateTime.now();
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recording) setState(() {});
    });
  }

  Future<void> _stopAndSendAudio() async {
    if (!_recording) return;
    if (_cancellingRecord) { await _cancelRecording(); return; }

    final elapsed = DateTime.now().difference(_recordStart ?? DateTime.now()).inSeconds;
    final path = await AudioService.shared.stopRecording();
    _recordTimer?.cancel();
    setState(() { _recording = false; _cancellingRecord = false; _recordDragX = 0; });
    HapticFeedback.lightImpact();

    if (path == null || elapsed < 1) return; // audio demasiado corto

    setState(() => _uploadingAudio = true);
    try {
      final audioUrl = await AudioService.shared.uploadAudio(path, widget.match.id);

      // Mensaje optimista de audio
      final tempId = 'temp_audio_${DateTime.now().millisecondsSinceEpoch}';
      if (mounted) {
        setState(() => _messages = [..._messages, Message(
          id: tempId,
          matchId: widget.match.id,
          senderId: AuthService.shared.userId ?? '',
          content: 'Nota de voz',
          type: 'audio',
          audioUrl: audioUrl,
          createdAt: DateTime.now(),
        )]);
        _scrollToBottom();
      }

      await ApiClient.shared.post('/messages/${widget.match.id}', {
        'sender_id': AuthService.shared.userId,
        'content': 'Nota de voz',
        'type': 'audio',
        'audio_url': audioUrl,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar audio: $e'), backgroundColor: BuddyColors.error),
      );
    } finally {
      if (mounted) setState(() => _uploadingAudio = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await AudioService.shared.cancelRecording();
    HapticFeedback.heavyImpact();
    setState(() { _recording = false; _cancellingRecord = false; _recordDragX = 0; _recordStart = null; });
  }

  Future<void> _closeMatch(String status) async {
    final label = status == 'completed' ? 'completada' : 'cancelada';
    final color = status == 'completed' ? BuddyColors.success : BuddyColors.error;
    final icon  = status == 'completed' ? Icons.check_circle_rounded : Icons.cancel_rounded;

    // Confirmación
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text('Ayuda $label'),
        ]),
        content: Text(
          status == 'completed'
              ? '¿Confirmas que la ayuda fue completada exitosamente?'
              : '¿Seguro que quieres cancelar esta ayuda?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await ApiClient.shared.patch('/matches/${widget.match.id}/status', {'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('Ayuda $label'),
        ]),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
      // Cierra el chat y avisa a la lista que debe recargar (true)
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: BuddyColors.error,
      ));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardHeight = mq.viewInsets.bottom;
    final bottomPad = keyboardHeight > 0 ? keyboardHeight + 10 : mq.viewPadding.bottom + 10;


    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: BuddyColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _buildHeader(),
          _buildContextStrip(),
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: _loading
                  ? _buildChatSkeleton()
                  : _messages.isEmpty
                      ? _buildEmptyChat()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _messages.length + (_loadingMore || _hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == 0 && (_loadingMore || _hasMore)) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: BuddyColors.teal),
                                )),
                              );
                            }
                            final msgIndex = (_loadingMore || _hasMore) ? i - 1 : i;
                            return _buildBubble(_messages[msgIndex]);
                          },
                        ),
            ),
          ),
          _isClosed ? _buildClosedBar(bottomPad) : _buildInput(bottomPad),
        ]),
      ),
    );
  }

  // ── Header: viajero + destino ────────────────────────────────────────────
  Widget _buildHeader() {
    final t = widget.match.traveler;
    final req = widget.match.request;
    final travelerName = t?.fullName ?? 'Viajero';

    return Container(
      decoration: const BoxDecoration(
        color: BuddyColors.surface,
        border: Border(bottom: BorderSide(color: BuddyColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: BuddyColors.inkMuted),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 12),
        BuddyAvatar(
          imageUrl: t?.avatarUrl,
          fallbackName: t?.fullName ?? 'V',
          radius: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(travelerName, style: BT.bodyBold),
            if (req?.destination?.name != null)
              Row(children: [
                const Icon(Icons.location_on_rounded, size: 11, color: BuddyColors.teal),
                const SizedBox(width: 2),
                Text(req!.destination!.name, style: BT.caption),
              ]),
          ]),
        ),
        _buildSessionTimer(),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: BuddyColors.inkMuted, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) => _closeMatch(value),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'completed',
              child: Row(children: [
                Icon(Icons.check_circle_rounded, color: BuddyColors.success, size: 20),
                SizedBox(width: 10),
                Text('Ayuda completada'),
              ]),
            ),
            const PopupMenuItem(
              value: 'cancelled',
              child: Row(children: [
                Icon(Icons.cancel_rounded, color: BuddyColors.error, size: 20),
                SizedBox(width: 10),
                Text('Cancelar ayuda'),
              ]),
            ),
          ],
        ),
      ]),
    );
  }

  // ── Session timer chip ───────────────────────────────────────────────────
  Widget _buildSessionTimer() {
    final isOver = _sessionMinutes >= 10;
    final color  = isOver ? BuddyColors.error : BuddyColors.inkMuted;
    final bg     = isOver
        ? BuddyColors.error.withValues(alpha: 0.1)
        : BuddyColors.border.withValues(alpha: 0.6);
    final label  = '${_sessionMinutes} min';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(
          fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: color,
        )),
      ]),
    );
  }

  // ── Bubbles ──────────────────────────────────────────────────────────────
  Widget _buildBubble(Message msg) {
    final isMe       = msg.senderId == AuthService.shared.userId;
    final time       = DateFormat('HH:mm').format(msg.createdAt.toLocal());
    final isAudio    = msg.type == 'audio' && msg.audioUrl != null;
    final isLocation = msg.content.startsWith('location:');
    final isPlace    = msg.content.startsWith('place:');
    final isTemp     = msg.id.startsWith('temp_');

    if (isPlace) {
      return Opacity(
        opacity: isTemp ? 0.65 : 1.0,
        child: _buildPlaceBubble(msg, isMe, time),
      );
    }

    if (isLocation) {
      return Opacity(
        opacity: isTemp ? 0.65 : 1.0,
        child: _buildLocationBubble(msg, isMe, time, isTemp),
      );
    }

    return Opacity(
      opacity: isTemp ? 0.65 : 1.0,
      child: _buildBubbleContent(msg, isMe, time, isAudio, isTemp),
    );
  }

  // Tarjeta de lugar: place:lat|lng|nombre|dirección
  Widget _buildPlaceBubble(Message msg, bool isMe, String time) {
    final parts = msg.content.replaceFirst('place:', '').split('|');
    final lat   = double.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final lng   = double.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final name  = parts.length > 2 ? parts[2] : 'Lugar';
    final addr  = parts.length > 3 ? parts.sublist(3).join('|') : '';
    final mapsUrl = 'https://maps.apple.com/?ll=$lat,$lng&q=${Uri.encodeComponent(name)}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        width: 250,
        decoration: BoxDecoration(
          color: BuddyColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(color: BuddyColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: GestureDetector(
          onTap: () => _launchUrl(mapsUrl),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: BuddyColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.place_rounded, color: BuddyColors.teal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: BT.bodyBold, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (addr.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(addr, style: BT.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.map_rounded, size: 13, color: BuddyColors.teal),
                    const SizedBox(width: 4),
                    Text('Ver en el mapa', style: BT.caption.copyWith(color: BuddyColors.teal, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(time, style: BT.caption.copyWith(fontSize: 10)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBubble(Message msg, bool isMe, String time, bool isTemp) {
    final parts = msg.content.replaceFirst('location:', '').split(',');
    final lat   = double.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final lng   = double.tryParse(parts.length > 1  ? parts[1] : '') ?? 0;
    final mapsUrl = 'https://maps.apple.com/?ll=$lat,$lng&q=Ubicación';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        width: 230,
        decoration: BoxDecoration(
          color: BuddyColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(color: BuddyColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: GestureDetector(
          onTap: () => _launchUrl(mapsUrl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Live map using flutter_map + OpenStreetMap tiles
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 130,
                child: Stack(children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(lat, lng),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none, // disable scroll/zoom inside bubble
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.buddyapp.flutter',
                      ),
                      MarkerLayer(markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 32,
                          height: 32,
                          child: Stack(alignment: Alignment.center, children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: BuddyColors.teal,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.5),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4)],
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ],
                  ),
                  Positioned(
                    left: 4, bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 9, color: Colors.black87),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            // Footer row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                const Icon(Icons.location_on_rounded, size: 13, color: BuddyColors.teal),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('Ubicación actual',
                    style: BT.bodyBold.copyWith(fontSize: 13, color: BuddyColors.ink)),
                ),
                const Icon(Icons.open_in_new_rounded, size: 12, color: BuddyColors.inkMuted),
              ]),
            ),
            // Time
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 6),
              child: Text(time,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 10, color: BuddyColors.inkMuted)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBubbleContent(Message msg, bool isMe, String time, bool isAudio, bool isTemp) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: EdgeInsets.fromLTRB(
          isAudio ? 10 : 14, 10,
          isAudio ? 10 : 14, 8,
        ),
        decoration: BoxDecoration(
          color: isMe ? BuddyColors.teal : BuddyColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (isAudio)
            AudioPlayerBubble(audioUrl: msg.audioUrl!, isMe: isMe)
          else
            _buildMessageText(msg.content, isMe),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (isTemp)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Icon(Icons.access_time_rounded, size: 10, color: isMe ? Colors.white54 : BuddyColors.inkMuted),
              ),
            Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white60 : BuddyColors.inkMuted)),
          ]),
        ]),
      ),
    );
  }

  // ── Context strip ────────────────────────────────────────────────────────
  Widget _buildContextStrip() {
    final req  = widget.match.request;
    final t    = widget.match.traveler;
    final dest = req?.destination?.name;
    if (dest == null && t == null) return const SizedBox.shrink();

    final tags = <(IconData, String)>[];
    if (dest != null)          tags.add((Icons.location_on_rounded, dest));
    if (t?.nationality != null) tags.add((Icons.flag_rounded, t!.nationality!));
    if (req?.arrivalAt != null) {
      final diff = req!.arrivalAt!.difference(DateTime.now());
      if (diff.inDays >= 0)
        tags.add((Icons.flight_land_rounded, diff.inDays == 0 ? 'Llega hoy' : 'Día ${diff.inDays + 1}'));
    }
    tags.add((Icons.person_rounded, 'Viajando solo/a'));

    return Container(
      width: double.infinity,
      color: BuddyColors.teal.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tags.map((tag) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(tag.$1, size: 11, color: BuddyColors.teal),
              const SizedBox(width: 4),
              Text(tag.$2, style: const TextStyle(
                fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500,
                color: BuddyColors.teal,
              )),
            ]),
          )).toList(),
        ),
      ),
    );
  }

  // ── Share bottom sheet: lugares del destino ───────────────────────────────
  void _showShareSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: const BoxDecoration(
          color: BuddyColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: BuddyColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Enviar un lugar', style: BT.bodyBold),
          const SizedBox(height: 4),
          Text('Toca un lugar para enviárselo al viajero', style: BT.caption),
          const SizedBox(height: 12),
          if (_places.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('No hay lugares para este destino.', style: BT.caption)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _places.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = _places[i];
                  final cat = (p['place_category'] as Map<String, dynamic>?)?['name'] as String?;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      HapticFeedback.selectionClick();
                      _sendPlace(p);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: BuddyColors.canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BuddyColors.border),
                      ),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: BuddyColors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.place_rounded, color: BuddyColors.teal, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['name']?.toString() ?? 'Lugar',
                              style: BT.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              p['address']?.toString() ?? (cat ?? 'Punto de interés'),
                              style: BT.caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                        const Icon(Icons.send_rounded, size: 16, color: BuddyColors.inkMuted),
                      ]),
                    ),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }

  // ── Link-aware message text ──────────────────────────────────────────────
  static final _urlRegex = RegExp(
    r'https?://[^\s]+|www\.[^\s]+',
    caseSensitive: false,
  );

  Future<void> _launchUrl(String raw) async {
    final url = raw.startsWith('http') ? raw : 'https://$raw';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildMessageText(String content, bool isMe) {
    final textColor = isMe ? Colors.white : BuddyColors.ink;
    final linkColor = isMe ? Colors.white : BuddyColors.teal;
    final matches = _urlRegex.allMatches(content).toList();
    if (matches.isEmpty) {
      return Text(content, style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor));
    }

    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, m.start)));
      }
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(url),
      ));
      cursor = m.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textColor),
        children: spans,
      ),
    );
  }

  // ── Input ────────────────────────────────────────────────────────────────
  Widget _buildInput(double bottomPad) {
    final hasText = _msgCtrl.text.trim().isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: BuddyColors.surface,
        border: Border(top: BorderSide(color: BuddyColors.border)),
      ),
      child: _recording
          ? _buildRecordingContent(bottomPad)
          : _buildNormalContent(bottomPad, hasText),
    );
  }

  // Contenido normal (sin grabar)
  Widget _buildNormalContent(double bottomPad, bool hasText) {
    return Padding(
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: bottomPad),
      child: Row(children: [
        // + share button
        GestureDetector(
          onTap: _showShareSheet,
          child: Container(
            width: 36, height: 36,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: BuddyColors.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: BuddyColors.border),
            ),
            child: const Icon(Icons.add_rounded, size: 18, color: BuddyColors.inkMuted),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            focusNode: _inputFocus,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: BT.body,
            decoration: InputDecoration(
              hintText: 'Escribe un mensaje...',
              hintStyle: BT.footnote,
              filled: true,
              fillColor: BuddyColors.canvas,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: BuddyColors.teal, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),

        // Botón derecho
        if (_uploadingAudio)
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(color: BuddyColors.border, shape: BoxShape.circle),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          )
        else if (hasText)
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: BuddyColors.teal, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          )
        else
          // Micrófono — long-press solo en el botón (no afecta el TextField)
          RawGestureDetector(
            gestures: {
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 200)),
                (instance) {
                  instance
                    ..onLongPressStart = (_) {
                        if (!_uploadingAudio && !_recording) _startRecording();
                      }
                    ..onLongPressEnd = (_) {
                        if (_recording) _stopAndSendAudio();
                      }
                    ..onLongPressMoveUpdate = (details) {
                        if (_recording) {
                          setState(() {
                            _recordDragX = details.offsetFromOrigin.dx;
                            _cancellingRecord = details.offsetFromOrigin.dx < -60;
                          });
                        }
                      };
                },
              ),
            },
            child: Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(color: BuddyColors.teal, shape: BoxShape.circle),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 22),
            ),
          ),
      ]),
    );
  }

  // Contenido mientras graba — estilo WhatsApp
  Widget _buildRecordingContent(double bottomPad) {
    final elapsed = _recordStart != null
        ? DateTime.now().difference(_recordStart!).inSeconds
        : 0;
    final mins = (elapsed ~/ 60).toString().padLeft(2, '0');
    final secs = (elapsed % 60).toString().padLeft(2, '0');
    final cancelOpacity = (_cancellingRecord
        ? 0.3
        : (1.0 + _recordDragX / 80).clamp(0.3, 1.0));

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 8, top: 10, bottom: bottomPad),
      child: Row(children: [
        // Punto pulsante + timer
        const _PulsingDot(),
        const SizedBox(width: 8),
        Text(
          '$mins:$secs',
          style: const TextStyle(
            fontFamily: 'Inter', fontSize: 15,
            fontWeight: FontWeight.w600, color: Colors.red,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 12),

        // "← Desliza para cancelar"
        Expanded(
          child: Opacity(
            opacity: cancelOpacity,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.chevron_left_rounded, color: BuddyColors.inkMuted, size: 18),
              Text(
                _cancellingRecord ? 'Suelta para cancelar' : 'Desliza para cancelar',
                style: BT.caption.copyWith(
                  color: _cancellingRecord ? Colors.red : BuddyColors.inkMuted,
                  fontWeight: _cancellingRecord ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ]),
          ),
        ),

        const SizedBox(width: 8),

        // Botón mic rojo — tappable para enviar sin soltar long press
        GestureDetector(
          onTap: _stopAndSendAudio,
          child: AnimatedScale(
            scale: _cancellingRecord ? 0.75 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _cancellingRecord ? Colors.red.shade300 : Colors.red,
                shape: BoxShape.circle,
                boxShadow: _cancellingRecord ? [] : [
                  BoxShadow(color: Colors.red.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildClosedBar(double bottomPad) {
    final isCompleted = _matchStatus == 'completed';
    return Container(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottomPad),
      decoration: BoxDecoration(
        color: BuddyColors.surface,
        border: const Border(top: BorderSide(color: BuddyColors.border)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          isCompleted ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 16,
          color: isCompleted ? BuddyColors.success : BuddyColors.error,
        ),
        const SizedBox(width: 8),
        Text(
          isCompleted ? 'Esta ayuda fue completada' : 'Esta ayuda fue cancelada',
          style: BT.caption.copyWith(
            color: isCompleted ? BuddyColors.success : BuddyColors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]),
    );
  }

  Widget _buildChatSkeleton() => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    children: const [
      SkeletonBubble(isRight: false),
      SkeletonBubble(isRight: true),
      SkeletonBubble(isRight: false),
      SkeletonBubble(isRight: true),
      SkeletonBubble(isRight: false),
    ],
  );

  Widget _buildEmptyChat() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 48, color: BuddyColors.inkMuted),
        const SizedBox(height: 16),
        Text('Momento de dar alivio', style: BT.title3, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'El viajero acaba de llegar.\nUsa las sugerencias de abajo para romper el hielo.',
          style: BT.footnote,
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );
}

// ── Punto pulsante rojo para indicar grabación ────────────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _ctrl,
    child: Container(
      width: 10, height: 10,
      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
    ),
  );
}
