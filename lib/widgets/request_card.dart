import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'buddy_avatar.dart';

class RequestCard extends StatelessWidget {
  final HelpRequest request;
  final VoidCallback onAccept;
  final VoidCallback onView;
  final VoidCallback? onExpired;

  const RequestCard({super.key, required this.request, required this.onAccept, required this.onView, this.onExpired});

  @override
  Widget build(BuildContext context) {
    final t = request.traveler;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: BuddyColors.surface,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: 0.07),
        elevation: 2,
        child: InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(16),
          splashColor: BuddyColors.teal.withValues(alpha: 0.06),
          highlightColor: BuddyColors.teal.withValues(alpha: 0.03),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Barra de urgencia (contador) — solo si la oferta tiene tiempo límite
            if (request.secondsRemaining != null)
              _UrgencyBar(seconds: request.secondsRemaining!, onExpired: onExpired),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                BuddyAvatar(
                  imageUrl: t?.avatarUrl,
                  fallbackName: t?.fullName ?? 'V',
                  radius: 26,
                ),
                const SizedBox(width: 14),

                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t?.fullName ?? 'Viajero', style: BT.bodyBold),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 12, color: BuddyColors.teal),
                    const SizedBox(width: 3),
                    Text(request.destination?.name ?? 'Destino', style: BT.caption),
                    if (t?.nationality != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.language_rounded, size: 11, color: BuddyColors.inkMuted),
                      const SizedBox(width: 2),
                      Text(t!.nationality!, style: BT.caption),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: BuddyColors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(request.categoryLabel,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: BuddyColors.teal)),
                    ),
                    if (request.arrivalAt != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.calendar_today_rounded, size: 11, color: BuddyColors.inkMuted),
                      const SizedBox(width: 2),
                      Text(DateFormat('d MMM', 'es').format(request.arrivalAt!.toLocal()), style: BT.caption),
                    ],
                  ]),
                ])),

                const SizedBox(width: 10),

                // Accept button con feedback háptico
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onAccept();
                  },
                  child: Container(
                    width: 42, height: 42,
                    decoration: const BoxDecoration(color: BuddyColors.teal, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Barra de urgencia con cuenta regresiva ───────────────────────────────────
class _UrgencyBar extends StatefulWidget {
  final int seconds;
  final VoidCallback? onExpired;
  const _UrgencyBar({required this.seconds, this.onExpired});
  @override State<_UrgencyBar> createState() => _UrgencyBarState();
}

class _UrgencyBarState extends State<_UrgencyBar> {
  late int _remaining;
  late int _total;
  Timer? _timer;
  bool _firedExpired = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _total = widget.seconds > 0 ? widget.seconds : 30;
    _start();
  }

  @override
  void didUpdateWidget(covariant _UrgencyBar old) {
    super.didUpdateWidget(old);
    // Si el servidor manda un nuevo tiempo (refresh), resincroniza
    if (widget.seconds != old.seconds) {
      _remaining = widget.seconds;
      _total = widget.seconds > _total ? widget.seconds : _total;
      _firedExpired = false;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining = (_remaining - 1).clamp(0, 999));
      if (_remaining <= 0 && !_firedExpired) {
        _firedExpired = true;
        _timer?.cancel();
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final urgent = _remaining <= 10;
    final color = urgent ? BuddyColors.error : BuddyColors.teal;
    final progress = (_remaining / _total).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        color: color.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [
          Row(children: [
            Icon(urgent ? Icons.warning_amber_rounded : Icons.bolt_rounded, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _remaining > 0 ? 'Un viajero necesita tu ayuda ahora' : 'Esta ayuda ya fue atendida',
                style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            Text(
              _remaining > 0 ? '${_remaining}s' : '—',
              style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w800, color: color),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ]),
      ),
    );
  }
}
