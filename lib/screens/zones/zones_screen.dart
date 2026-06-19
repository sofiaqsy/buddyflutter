import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import 'zone_detail_screen.dart';

class _ZoneItem {
  final String id;
  final String name;
  final String city;
  final String? coverUrl;
  final bool isLinked;
  bool isActive;

  _ZoneItem({
    required this.id, required this.name, required this.city,
    this.coverUrl, required this.isLinked, required this.isActive,
  });

  factory _ZoneItem.fromJson(Map<String, dynamic> j) => _ZoneItem(
    id:       j['id'],
    name:     j['name'],
    city:     j['city'],
    coverUrl: j['cover_url'],
    isLinked: j['is_linked'] == true,
    isActive: j['is_active'] == true,
  );
}

class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});
  @override State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  List<_ZoneItem> _zones = [];
  bool _loading      = true;
  bool _isAvailable  = false;
  bool _togglingAvailability = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.shared.get('/buddy/zones'),
        ApiClient.shared.get('/buddy/profile'),
      ]);
      if (!mounted) return;
      final list    = results[0] as List;
      final profile = results[1] as Map<String, dynamic>;
      setState(() {
        _zones        = list.map((j) => _ZoneItem.fromJson(j)).toList();
        _isAvailable  = profile['is_available'] ?? false;
        _loading      = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() { _isAvailable = value; _togglingAvailability = true; });
    try {
      await ApiClient.shared.patch('/buddy/availability', {'is_available': value});
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _isAvailable = !value);
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  Future<void> _toggleActive(_ZoneItem zone, bool value) async {
    if (!mounted) return;
    setState(() => zone.isActive = value);
    try {
      await ApiClient.shared.patch('/buddy/zones/${zone.id}/active', {'is_active': value});
    } catch (e) {
      if (!mounted) return;
      setState(() => zone.isActive = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: BuddyColors.error),
      );
    }
  }

  void _openDetail(_ZoneItem zone) {
    HapticFeedback.selectionClick();
    Navigator.push(context, context.buddyRoute(ZoneDetailScreen(
      destinationId: zone.id,
      destinationName: zone.name,
    )));
  }

  Future<void> _addZone(_ZoneItem zone) async {
    try {
      await ApiClient.shared.post('/buddy/zones/${zone.id}', {});
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text('${zone.name} añadida a tus suscripciones'),
        ]),
        backgroundColor: BuddyColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: BuddyColors.error),
      );
    }
  }

  Future<void> _removeZone(_ZoneItem zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: BuddyColors.canvas,
        title: Text('Cancelar suscripción', style: BT.title3),
        content: Text(
          '¿Quieres cancelar tu suscripción a ${zone.name}? Dejarás de recibir solicitudes de esta zona.',
          style: BT.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: BT.callout.copyWith(color: BuddyColors.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: BT.callout.copyWith(color: BuddyColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ApiClient.shared.delete('/buddy/zones/${zone.id}');
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: BuddyColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final linked   = _zones.where((z) => z.isLinked).toList();
    final unlinked = _zones.where((z) => !z.isLinked).toList();

    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CONFIGURACIÓN', style: BT.eyebrow),
              const SizedBox(height: 2),
              const Text(
                'suscripciones.',
                style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: BuddyColors.ink),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: BuddyColors.teal))
                : RefreshIndicator(
                    color: BuddyColors.teal,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      children: [

                        // ── Banner de disponibilidad global ───────────
                        _AvailabilityBanner(
                          isAvailable: _isAvailable,
                          isLoading: _togglingAvailability,
                          linkedCount: linked.length,
                          onToggle: _toggleAvailability,
                        ),
                        const SizedBox(height: 24),

                        // ── Mis suscripciones ─────────────────────────
                        if (linked.isNotEmpty) ...[
                          _sectionLabel('MIS SUSCRIPCIONES'),
                          const SizedBox(height: 10),
                          ...linked.map((z) => _LinkedZoneCard(
                            zone: z,
                            onToggle: (v) => _toggleActive(z, v),
                            onRemove: () => _removeZone(z),
                            onTap: () => _openDetail(z),
                          )),
                          const SizedBox(height: 24),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: BuddyColors.sandLight,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: BuddyColors.border),
                            ),
                            child: Row(children: [
                              const Icon(Icons.map_outlined, size: 28, color: BuddyColors.sand),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Sin suscripciones', style: BT.bodyBold),
                                const SizedBox(height: 2),
                                Text('Añade destinos abajo para empezar a recibir solicitudes.', style: BT.caption),
                              ])),
                            ]),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // ── Otros destinos disponibles ────────────────
                        if (unlinked.isNotEmpty) ...[
                          _sectionLabel('AÑADIR DESTINO'),
                          const SizedBox(height: 10),
                          ...unlinked.map((z) => _UnlinkedZoneCard(
                            zone: z,
                            onAdd: () => _addZone(z),
                            onTap: () => _openDetail(z),
                          )),
                        ],
                      ],
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text, style: BT.eyebrow);
}

// ── Banner de disponibilidad global ───────────────────────────────────────────
class _AvailabilityBanner extends StatelessWidget {
  final bool isAvailable;
  final bool isLoading;
  final int linkedCount;
  final ValueChanged<bool> onToggle;

  const _AvailabilityBanner({
    required this.isAvailable,
    required this.isLoading,
    required this.linkedCount,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isAvailable ? BuddyColors.teal : BuddyColors.inkMuted;
    final activeBg    = isAvailable
        ? BuddyColors.teal.withValues(alpha: 0.08)
        : BuddyColors.border.withValues(alpha: 0.4);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: activeBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAvailable
              ? BuddyColors.teal.withValues(alpha: 0.35)
              : BuddyColors.border,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Título + switch
        Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isAvailable
                  ? BuddyColors.teal.withValues(alpha: 0.15)
                  : BuddyColors.border,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAvailable ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
              color: activeColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700,
                  color: activeColor,
                ),
                child: Text(isAvailable ? 'Disponible' : 'No disponible'),
              ),
              const SizedBox(height: 2),
              Text(
                isAvailable
                    ? 'Recibes solicitudes de tus suscripciones'
                    : 'No recibes solicitudes de ninguna suscripción',
                style: BT.caption,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          isLoading
              ? const SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: BuddyColors.teal),
                )
              : Switch.adaptive(
                  value: isAvailable,
                  onChanged: onToggle,
                  activeColor: BuddyColors.teal,
                ),
        ]),

        const SizedBox(height: 14),
        const Divider(height: 1, color: BuddyColors.border),
        const SizedBox(height: 14),

        // Explicación clara con ícono
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isAvailable
                  ? BuddyColors.success.withValues(alpha: 0.12)
                  : BuddyColors.border,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.info_outline_rounded,
              size: 13,
              color: isAvailable ? BuddyColors.success : BuddyColors.inkMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAvailable
                  ? linkedCount > 0
                      ? 'Estás recibiendo solicitudes de $linkedCount ${linkedCount == 1 ? 'suscripción' : 'suscripciones'}. Si te desactivas, dejarás de recibir solicitudes de todas al instante.'
                      : 'Estás disponible pero sin suscripciones activas. Añade un destino abajo para empezar.'
                  : 'Mientras estés desactivado, no recibirás solicitudes de ninguna suscripción, sin importar cuántas tengas.',
              style: BT.caption.copyWith(height: 1.5),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Linked zone card ──────────────────────────────────────────────────────────
class _LinkedZoneCard extends StatelessWidget {
  final _ZoneItem zone;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  const _LinkedZoneCard({required this.zone, required this.onToggle, required this.onRemove, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: BuddyColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            _cover(zone.coverUrl, height: 140),
            Positioned(
              top: 12, left: 14,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: zone.isActive
                      ? BuddyColors.success.withValues(alpha: 0.92)
                      : Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(
                    zone.isActive ? 'suscrito' : 'pausado',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ]),
              ),
            ),
            Positioned(
              top: 10, right: 10,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
            Positioned(
              bottom: 12, left: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(zone.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(zone.city, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70)),
              ]),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  zone.isActive ? 'Suscripción activa' : 'Suscripción pausada',
                  style: BT.callout,
                ),
                Text(
                  zone.isActive
                      ? 'Recibirás solicitudes de esta zona'
                      : 'No recibirás solicitudes de esta zona',
                  style: BT.caption,
                ),
              ])),
              Switch.adaptive(
                value: zone.isActive,
                onChanged: onToggle,
                activeColor: BuddyColors.teal,
              ),
            ]),
          ),
          // Hint ver detalles
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: BuddyColors.teal.withValues(alpha: 0.05),
              border: const Border(top: BorderSide(color: BuddyColors.border)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.map_rounded, size: 13, color: BuddyColors.teal),
              const SizedBox(width: 5),
              Text('Ver mapa y puntos de interés',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: BuddyColors.teal)),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: BuddyColors.teal),
            ]),
          ),
        ]),
        ),
      ),
    );
  }
}

// ── Unlinked zone card ────────────────────────────────────────────────────────
class _UnlinkedZoneCard extends StatelessWidget {
  final _ZoneItem zone;
  final VoidCallback onAdd;
  final VoidCallback onTap;
  const _UnlinkedZoneCard({required this.zone, required this.onAdd, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BuddyColors.border),
      ),
      child: Material(
        color: BuddyColors.surface,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.12),
          highlightColor: Colors.white.withValues(alpha: 0.06),
          child: Stack(children: [
            _cover(zone.coverUrl, height: 110),
            Positioned(
              bottom: 12, left: 14,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(zone.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(zone.city, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: Colors.white70)),
              ]),
            ),
            Positioned(
              top: 10, right: 10,
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onAdd();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: BuddyColors.teal, borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 15),
                    SizedBox(width: 4),
                    Text('Suscribirse', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _cover(String? url, {required double height}) {
  return SizedBox(
    height: height, width: double.infinity,
    child: Stack(fit: StackFit.expand, children: [
      url != null
          ? CachedNetworkImage(
              imageUrl: url, fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: BuddyColors.sandLight),
              errorWidget: (_, __, ___) => _gradientFallback,
            )
          : _gradientFallback,
      const DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, Colors.black54],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ),
      )),
    ]),
  );
}

const Widget _gradientFallback = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [BuddyColors.tealDeep, BuddyColors.teal],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ),
  ),
);
