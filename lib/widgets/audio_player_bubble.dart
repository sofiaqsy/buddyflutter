import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../core/theme.dart';
import '../core/audio_service.dart';
import '../core/auth_service.dart';

/// Burbuja de audio estilo WhatsApp: play/pause + barra de progreso + duración
class AudioPlayerBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;

  const AudioPlayerBubble({super.key, required this.audioUrl, required this.isMe});

  @override
  State<AudioPlayerBubble> createState() => _AudioPlayerBubbleState();
}

class _AudioPlayerBubbleState extends State<AudioPlayerBubble> {
  final _player = AudioPlayer();
  bool _loading  = true;
  bool _playing  = false;
  bool _error    = false;
  Duration _pos  = Duration.zero;
  Duration _dur  = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init({String? overrideUrl}) async {
    final url = overrideUrl ?? widget.audioUrl;
    try {
      final token = AuthService.shared.accessToken;
      // Token en la URL (no en header): los reproductores nativos no reenvían
      // headers en las peticiones de rango/seek → daban 401. Solo para el proxy.
      var playUrl = url;
      if (token != null && url.contains('/messages/audio-file')) {
        playUrl = '$url&token=${Uri.encodeQueryComponent(token)}';
      }
      await _player.setUrl(playUrl);
      if (!mounted) return;
      setState(() => _loading = false);

      _player.durationStream.listen((d) {
        if (mounted && d != null) setState(() => _dur = d);
      });
      _player.positionStream.listen((p) {
        if (mounted) setState(() => _pos = p);
      });
      _player.playerStateStream.listen((s) {
        if (mounted) setState(() => _playing = s.playing);
        if (s.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
    } catch (_) {
      // URL expirada — intentar refrescar la firma
      if (overrideUrl == null) {
        final fresh = await AudioService.shared.refreshSignedUrl(widget.audioUrl);
        if (fresh != null && mounted) {
          await _init(overrideUrl: fresh);
          return;
        }
      }
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg     = widget.isMe ? Colors.white : BuddyColors.ink;
    final fgMuted= widget.isMe ? Colors.white60 : BuddyColors.inkMuted;
    final accent = widget.isMe ? Colors.white : BuddyColors.teal;
    final trackBg= widget.isMe ? Colors.white24 : BuddyColors.border;

    if (_error) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.mic_off_rounded, color: fgMuted, size: 16),
        const SizedBox(width: 6),
        Text('Audio no disponible', style: TextStyle(color: fgMuted, fontSize: 12)),
      ]);
    }

    final progress = _dur.inMilliseconds > 0
        ? (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 200,
      child: Row(children: [
        // Play / pause button
        GestureDetector(
          onTap: () => _playing ? _player.pause() : _player.play(),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: widget.isMe ? 0.25 : 0.12),
              shape: BoxShape.circle,
            ),
            child: _loading
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                : Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: accent, size: 22,
                  ),
          ),
        ),
        const SizedBox(width: 10),

        // Waveform + timer
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(children: [
                  Container(height: 3, color: trackBg),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(height: 3, color: accent),
                  ),
                ]),
              ),
              const SizedBox(height: 5),
              // Fake waveform bars
              _WaveformBars(progress: progress, isMe: widget.isMe),
              const SizedBox(height: 3),
              Text(
                _playing ? _fmt(_pos) : _fmt(_dur),
                style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: fgMuted),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// Barras decorativas tipo waveform
class _WaveformBars extends StatelessWidget {
  final double progress;
  final bool isMe;

  const _WaveformBars({required this.progress, required this.isMe});

  static const _heights = [4.0, 7.0, 10.0, 6.0, 12.0, 8.0, 14.0, 9.0, 6.0, 11.0,
                            8.0, 13.0, 5.0, 10.0, 7.0, 12.0, 9.0, 6.0, 11.0, 8.0];

  @override
  Widget build(BuildContext context) {
    final total  = _heights.length;
    final active = (progress * total).round();
    final accent = isMe ? Colors.white : BuddyColors.teal;
    final muted  = isMe ? Colors.white30 : BuddyColors.border;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(total, (i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Container(
          width: 2.5,
          height: _heights[i % _heights.length],
          decoration: BoxDecoration(
            color: i < active ? accent : muted,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    );
  }
}
