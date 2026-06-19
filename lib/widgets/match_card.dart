import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'buddy_avatar.dart';

String _timeAgo(DateTime dt) {
  final s = DateTime.now().difference(dt).inSeconds;
  if (s < 60)    return 'ahora';
  if (s < 3600)  return '${s ~/ 60} min';
  if (s < 86400) return '${s ~/ 3600} h';
  return '${s ~/ 86400} d';
}

class MatchCard extends StatelessWidget {
  final Match match;
  final VoidCallback onChat;
  final VoidCallback? onView;

  const MatchCard({super.key, required this.match, required this.onChat, this.onView});

  @override
  Widget build(BuildContext context) {
    final t = match.traveler ?? match.request?.traveler;

    final isClosed = match.status == 'completed' || match.status == 'cancelled';

    final (statusColor, statusLabel, statusIcon) = switch (match.status) {
      'accepted' || 'active' => (BuddyColors.success, 'Activo',     Icons.circle),
      'completed'             => (BuddyColors.inkMuted, 'Completado', Icons.check_circle_rounded),
      'cancelled'             => (BuddyColors.error,    'Cancelado',  Icons.cancel_rounded),
      _                       => (BuddyColors.sand,     match.status, Icons.circle),
    };

    return Opacity(
      opacity: isClosed ? 0.55 : 1.0,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: isClosed ? BuddyColors.canvas : BuddyColors.surface,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black.withValues(alpha: isClosed ? 0.02 : 0.07),
        elevation: isClosed ? 0 : 2,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onChat();
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: BuddyColors.teal.withValues(alpha: 0.06),
          highlightColor: BuddyColors.teal.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Stack(children: [
                ColorFiltered(
                  colorFilter: isClosed
                      ? const ColorFilter.matrix([
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0,      0,      0,      1, 0,
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: BuddyAvatar(
                    imageUrl: t?.avatarUrl,
                    fallbackName: t?.fullName ?? 'V',
                    radius: 26,
                  ),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Icon(statusIcon, size: 16, color: statusColor),
                ),
              ]),
              const SizedBox(width: 14),

              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(t?.fullName ?? 'Viajero',
                      style: BT.bodyBold.copyWith(color: isClosed ? BuddyColors.inkMuted : BuddyColors.ink),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (match.lastMessage != null)
                    Text(
                      _timeAgo(match.lastMessage!.createdAt),
                      style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: BuddyColors.inkMuted),
                    ),
                ]),
                const SizedBox(height: 2),
                if (match.lastMessage != null) ...[
                  Text(
                    match.lastMessage!.type == 'audio'
                        ? 'Nota de voz'
                        : match.lastMessage!.content.startsWith('location:')
                            ? 'Ubicación actual'
                            : match.lastMessage!.content,
                    style: BT.caption.copyWith(color: isClosed ? BuddyColors.inkMuted : BuddyColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else ...[
                  Row(children: [
                    if (match.request?.destination?.name != null) ...[
                      Icon(Icons.location_on_rounded, size: 12, color: isClosed ? BuddyColors.inkMuted : BuddyColors.teal),
                      const SizedBox(width: 3),
                      Text(match.request!.destination!.name, style: BT.caption),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(statusLabel,
                        style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                    ),
                  ]),
                  if (match.request?.categoryLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(match.request!.categoryLabel, style: BT.caption),
                  ],
                ],
              ])),

              Icon(Icons.chevron_right_rounded,
                color: isClosed ? BuddyColors.border : BuddyColors.inkMuted, size: 22),
            ]),
          ),
        ),
      ),
    ));
  }
}
