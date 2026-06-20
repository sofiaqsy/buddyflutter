import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

// ── Modelos ────────────────────────────────────────────────────────────────────
class _Place {
  final String id;
  final String name;
  final String? description;
  final String? address;
  final double lat;
  final double lng;
  final String? placeType;
  final String? coverUrl;
  final String? categoryName;

  _Place.fromJson(Map<String, dynamic> j)
      : id          = j['id'],
        name        = j['name'],
        description = j['description'],
        address     = j['address'],
        lat         = (j['lat'] as num).toDouble(),
        lng         = (j['lng'] as num).toDouble(),
        placeType   = j['place_type'],
        coverUrl    = j['cover_url'],
        categoryName = (j['place_category'] as Map<String, dynamic>?)?['name'];
}

class _Destination {
  final String id;
  final String name;
  final String city;
  final String? country;
  final double lat;
  final double lng;
  final String? coverUrl;
  final List<_Place> places;

  _Destination.fromJson(Map<String, dynamic> j)
      : id      = j['id'],
        name    = j['name'],
        city    = j['city'],
        country = j['country'],
        lat     = (j['lat'] as num).toDouble(),
        lng     = (j['lng'] as num).toDouble(),
        coverUrl = j['cover_url'],
        places  = (j['places'] as List)
            .map((p) => _Place.fromJson(p as Map<String, dynamic>))
            .toList();
}

// ── Pantalla ───────────────────────────────────────────────────────────────────
class ZoneDetailScreen extends StatefulWidget {
  final String destinationId;
  final String destinationName;

  const ZoneDetailScreen({
    super.key,
    required this.destinationId,
    required this.destinationName,
  });

  @override
  State<ZoneDetailScreen> createState() => _ZoneDetailScreenState();
}

class _ZoneDetailScreenState extends State<ZoneDetailScreen> {
  // Cache estático compartido entre todas las instancias de la pantalla
  static final Map<String, _Destination> _cache = {};

  _Destination? _dest;
  bool _loading = true;
  String? _selectedPlaceId;
  String? _error;
  final _mapCtrl = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Si hay cache y no es refresh forzado → mostrar inmediatamente
    final cached = _cache[widget.destinationId];
    if (cached != null && !forceRefresh) {
      setState(() { _dest = cached; _loading = false; });
      // Refresca en background silenciosamente
      _fetchAndCache(silent: true);
      return;
    }

    setState(() { _loading = _dest == null; _error = null; });
    await _fetchAndCache(silent: false);
  }

  Future<void> _fetchAndCache({required bool silent}) async {
    try {
      final data = await ApiClient.shared.get('/buddy/zones/${widget.destinationId}');
      if (!mounted) return;
      final dest = _Destination.fromJson(data as Map<String, dynamic>);
      _cache[widget.destinationId] = dest;
      setState(() { _dest = dest; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // Icono/emoji según tipo de lugar
  String _placeEmoji(String? type) {
    switch (type) {
      case 'restaurant':  return '🍽️';
      case 'hotel':       return '🏨';
      case 'attraction':  return '🏛️';
      case 'transport':   return '🚌';
      case 'shop':        return '🛍️';
      case 'coffee':      return '☕';
      case 'bar':         return '🍺';
      case 'park':        return '🌿';
      case 'beach':       return '🏖️';
      case 'museum':      return '🖼️';
      default:            return '📍';
    }
  }

  Color _placeColor(String? type) {
    switch (type) {
      case 'restaurant':  return const Color(0xFFFF6B35);
      case 'hotel':       return const Color(0xFF6C63FF);
      case 'attraction':  return BuddyColors.teal;
      case 'transport':   return const Color(0xFF2196F3);
      case 'shop':        return const Color(0xFFE91E8C);
      case 'coffee':      return const Color(0xFF795548);
      case 'bar':         return const Color(0xFFFF9800);
      case 'park':        return const Color(0xFF4CAF50);
      case 'beach':       return const Color(0xFF00BCD4);
      case 'museum':      return const Color(0xFF9C27B0);
      default:            return BuddyColors.inkMuted;
    }
  }

  void _focusPlace(_Place p) {
    HapticFeedback.selectionClick();
    setState(() => _selectedPlaceId = _selectedPlaceId == p.id ? null : p.id);
    if (_selectedPlaceId == p.id) {
      _mapCtrl.move(LatLng(p.lat, p.lng), 15.0);
    } else {
      // Deseleccionar: volver a encuadrar todos
      final d = _dest!;
      _mapCtrl.fitCamera(CameraFit.coordinates(
        coordinates: [LatLng(d.lat, d.lng), ...d.places.map((p) => LatLng(p.lat, p.lng))],
        maxZoom: 15,
        padding: const EdgeInsets.fromLTRB(48, 80, 48, 100),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BuddyColors.teal))
          : _dest == null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('😕', style: TextStyle(fontSize: 40)),
        const SizedBox(height: 12),
        Text('No se pudo cargar', style: BT.body),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: BT.caption.copyWith(color: BuddyColors.error), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        TextButton(onPressed: _load, child: const Text('Reintentar')),
      ]),
    ),
  );

  Widget _buildContent() {
    final d = _dest!;
    return CustomScrollView(
      slivers: [
        // ── AppBar compacto solo con botón back ────────────────────────────
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: Colors.black45,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(child: Column(children: [

          // ── Mapa con imagen de fondo ──────────────────────────────────────
          _buildMap(d),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Icon(Icons.touch_app_rounded, size: 14, color: BuddyColors.inkMuted),
              const SizedBox(width: 4),
              Text('Toca un marcador para ver detalles', style: BT.caption),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BuddyColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${d.places.length} puntos de interés',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: BuddyColors.teal),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          // ── Lista de lugares ──────────────────────────────────────────────
          if (d.places.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('PUNTOS DE INTERÉS', style: BT.eyebrow),
              ]),
            ),
            const SizedBox(height: 12),
            ...d.places.asMap().entries.map((e) => _buildPlaceCard(e.value, e.key)),
          ] else
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(children: [
                  const Text('🗺️', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 8),
                  Text('Sin puntos de interés registrados', style: BT.caption),
                ]),
              ),
            ),

          const SizedBox(height: 40),
        ])),
      ],
    );
  }

  Widget _buildMap(_Destination d) {
    final center = LatLng(d.lat, d.lng);
    final screenH = MediaQuery.of(context).size.height;

    return SizedBox(
      height: screenH * 0.48,
      child: Stack(children: [
        // ── Imagen de fondo del destino ──────────────────────────────────
        if (d.coverUrl != null)
          Positioned.fill(
            child: CachedNetworkImage(imageUrl: d.coverUrl!, fit: BoxFit.cover),
          ),

        // ── Mapa encima con opacidad para que se vea la foto debajo ──────
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCameraFit: d.places.isEmpty
                  ? CameraFit.coordinates(
                      coordinates: [center],
                      maxZoom: 14,
                      padding: const EdgeInsets.all(60),
                    )
                  : CameraFit.coordinates(
                      coordinates: [
                        center,
                        ...d.places.map((p) => LatLng(p.lat, p.lng)),
                      ],
                      maxZoom: 15,
                      padding: const EdgeInsets.fromLTRB(48, 80, 48, 100),
                    ),
              minZoom: 8,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
                pinchZoomThreshold: 0.1,
                pinchMoveThreshold: 10,
                scrollWheelVelocity: 0.005,
              ),
            ),
            children: [
              // Tiles con ligera transparencia
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.buddy.app',
                tileBuilder: (context, child, tile) => Opacity(opacity: 0.88, child: child),
              ),

              // Pins de lugares
              MarkerLayer(
                markers: d.places.map((p) => Marker(
                  point: LatLng(p.lat, p.lng),
                  width: 28, height: 36,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => _focusPlace(p),
                    child: _PlacePin(
                      emoji: _placeEmoji(p.placeType),
                      color: _placeColor(p.placeType),
                      isSelected: _selectedPlaceId == p.id,
                    ),
                  ),
                )).toList(),
              ),

              // Popup del lugar seleccionado
              if (_selectedPlaceId != null)
                MarkerLayer(
                  markers: d.places
                      .where((p) => p.id == _selectedPlaceId)
                      .map((p) => Marker(
                        point: LatLng(p.lat, p.lng),
                        width: 190,
                        height: 60,
                        alignment: const Alignment(0, -2.8),
                        child: _PlacePopup(place: p),
                      ))
                      .toList(),
                ),
            ],
          ),
        ),

        // ── Atribución OSM (requerida por licencia ODbL) ─────────────────
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

        // ── Botones de zoom ───────────────────────────────────────────────
        Positioned(
          right: 12, bottom: 60,
          child: Column(children: [
            _ZoomButton(
              icon: Icons.add_rounded,
              onTap: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom + 1),
            ),
            const SizedBox(height: 6),
            _ZoomButton(
              icon: Icons.remove_rounded,
              onTap: () => _mapCtrl.move(_mapCtrl.camera.center, _mapCtrl.camera.zoom - 1),
            ),
          ]),
        ),

        // ── Header con nombre del destino (abajo del mapa) ───────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black54],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 6)]),
              ),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.location_on_rounded, size: 13, color: Colors.white70),
                const SizedBox(width: 3),
                Text('${d.city}${d.country != null ? ', ${d.country}' : ''}',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70)),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildPlaceCard(_Place place, int index) {
    final isSelected = _selectedPlaceId == place.id;
    final color = _placeColor(place.placeType);

    return GestureDetector(
      onTap: () => _focusPlace(place),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.06) : BuddyColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.4) : BuddyColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          // Sticker / cover
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15), bottomLeft: Radius.circular(15),
            ),
            child: place.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: place.coverUrl!,
                    width: 72, height: 80, fit: BoxFit.cover,
                    placeholder: (_, __) => _emojiBox(place, color),
                    errorWidget: (_, __, ___) => _emojiBox(place, color),
                  )
                : _emojiBox(place, color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Nombre + badge tipo
                Row(children: [
                  Expanded(
                    child: Text(place.name,
                        style: BT.bodyBold, overflow: TextOverflow.ellipsis),
                  ),
                  if (place.categoryName != null)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(place.categoryName!,
                          style: TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w700, color: color)),
                    ),
                ]),
                if (place.description != null && place.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(place.description!,
                      style: BT.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                if (place.address != null && place.address!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.pin_drop_rounded, size: 11, color: color),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(place.address!,
                          style: BT.caption.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              isSelected ? Icons.location_on_rounded : Icons.chevron_right_rounded,
              color: isSelected ? color : BuddyColors.border,
              size: 20,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _emojiBox(_Place place, Color color) {
    // Genera un color de fondo único basado en el nombre del lugar
    final hue = (place.name.codeUnits.fold(0, (a, b) => a + b) % 360).toDouble();
    final bg = HSLColor.fromAHSL(1, hue, 0.35, 0.88).toColor();
    return Container(
      width: 72, height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bg, color.withValues(alpha: 0.18)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_placeEmoji(place.placeType), style: const TextStyle(fontSize: 26)),
      ]),
    );
  }
}

// ── Widgets del mapa ───────────────────────────────────────────────────────────

/// Pin tipo gota: burbuja + aguja. El vértice inferior = posición exacta del lugar.
class _PlacePin extends StatelessWidget {
  final String emoji;
  final Color color;
  final bool isSelected;

  const _PlacePin({
    required this.emoji,
    required this.color,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isSelected ? 1.25 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Burbuja con emoji
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 5, offset: const Offset(0, 2))],
          ),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 13)),
          ),
        ),
        // Aguja que apunta al punto exacto
        CustomPaint(
          size: const Size(10, 8),
          painter: _PinNeedlePainter(color: color),
        ),
      ]),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: BuddyColors.ink),
      ),
    );
  }
}

class _PinNeedlePainter extends CustomPainter {
  final Color color;
  const _PinNeedlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PinNeedlePainter old) => old.color != color;
}

class _PlacePopup extends StatelessWidget {
  final _Place place;
  const _PlacePopup({required this.place});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(place.name,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: BuddyColors.ink),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (place.address != null && place.address!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(place.address!,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: BuddyColors.inkMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
