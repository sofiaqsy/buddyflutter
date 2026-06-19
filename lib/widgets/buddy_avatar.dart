import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import 'shimmer_box.dart';

/// Avatar optimizado con caché, shimmer de carga y fallback a iniciales
class BuddyAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackName;
  final double radius;
  final Color? borderColor;

  const BuddyAvatar({
    super.key,
    this.imageUrl,
    required this.fallbackName,
    this.radius = 26,
    this.borderColor,
  });

  String get _initials => fallbackName
      .split(' ')
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    Widget avatar;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      avatar = CachedNetworkImage(
        imageUrl: imageUrl!,
        imageBuilder: (_, img) => CircleAvatar(
          radius: radius,
          backgroundImage: img,
        ),
        placeholder: (_, __) => ShimmerBox.circle(size: size),
        errorWidget: (_, __, ___) => _fallback(size),
        memCacheWidth: (size * 3).toInt(),  // 3x for retina
        fadeInDuration: const Duration(milliseconds: 200),
      );
    } else {
      avatar = _fallback(size);
    }

    if (borderColor != null) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor!, width: 2),
        ),
        child: avatar,
      );
    }
    return avatar;
  }

  Widget _fallback(double size) => CircleAvatar(
    radius: size / 2,
    backgroundColor: BuddyColors.sandLight,
    child: Text(
      _initials,
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: size * 0.28,
        color: BuddyColors.sand,
      ),
    ),
  );
}
