import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Shimmer animado reutilizable — úsalo como placeholder de cualquier tamaño
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
    this.circle = false,
  });

  const ShimmerBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = size / 2,
        circle = true;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circle ? null : BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [Color(0xFFECE6DC), Color(0xFFF5F0E8), Color(0xFFECE6DC)],
            stops: [0.0, _anim.value.clamp(0.1, 0.9), 1.0],
          ),
        ),
      ),
    );
  }
}

// ── Skeleton card para solicitudes/ayudas ─────────────────────────────────
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BuddyColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        const ShimmerBox.circle(size: 52),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ShimmerBox(width: 140, height: 14),
          const SizedBox(height: 8),
          const ShimmerBox(width: 100, height: 11),
          const SizedBox(height: 8),
          const ShimmerBox(width: 80, height: 22, radius: 8),
        ])),
        const ShimmerBox.circle(size: 40),
      ]),
    );
  }
}

// ── Skeleton tarjeta de Ayuda (MatchCard) ─────────────────────────────────
class SkeletonMatchCard extends StatelessWidget {
  const SkeletonMatchCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BuddyColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // Avatar con punto de estado
        Stack(children: [
          const ShimmerBox.circle(size: 52),
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                color: BuddyColors.border,
                shape: BoxShape.circle,
                border: Border.all(color: BuddyColors.surface, width: 2),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Nombre
            const ShimmerBox(width: 130, height: 14),
            const SizedBox(height: 8),
            // Destino + badge status
            Row(children: [
              const ShimmerBox(width: 90, height: 11),
              const SizedBox(width: 8),
              const ShimmerBox(width: 60, height: 18, radius: 6),
            ]),
            const SizedBox(height: 8),
            // Categoría
            const ShimmerBox(width: 80, height: 11),
          ]),
        ),
        const SizedBox(width: 8),
        const ShimmerBox(width: 18, height: 18, radius: 4),
      ]),
    );
  }
}

// ── Skeleton para el header del chat ──────────────────────────────────────
class SkeletonChatHeader extends StatelessWidget {
  const SkeletonChatHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BuddyColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        const ShimmerBox.circle(size: 40),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          ShimmerBox(width: 120, height: 14),
          SizedBox(height: 6),
          ShimmerBox(width: 80, height: 11),
        ]),
      ]),
    );
  }
}

// ── Skeleton burbuja de chat ───────────────────────────────────────────────
class SkeletonBubble extends StatelessWidget {
  final bool isRight;
  const SkeletonBubble({super.key, this.isRight = false});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerBox(
          width: isRight ? 180 : 220,
          height: 42,
          radius: 16,
        ),
      ),
    );
  }
}
