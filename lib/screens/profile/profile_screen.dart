import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/auth_service.dart';
import '../../models/models.dart';
import '../auth/phone_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  BuddyUser? _user;
  Map<String, dynamic>? _buddyProfile;
  List<Destination> _destinations = [];
  bool _loading = true;
  Set<String> _specialties = {};
  bool _savingSpecialties = false;

  // Necesidades que un buddy puede atender (valor = categoría del help_request)
  static const _specialtyOptions = <(String, String, IconData)>[
    ('transport',     'Cómo llegar',  Icons.directions_bus_rounded),
    ('food',          'Comer',        Icons.restaurant_rounded),
    ('translation',   'Traducir',     Icons.translate_rounded),
    ('activities',    'Qué hacer',    Icons.local_activity_rounded),
    ('accommodation', 'Alojamiento',  Icons.hotel_rounded),
    ('emergency',     'Seguridad',    Icons.health_and_safety_rounded),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiClient.shared.get('/users/${AuthService.shared.userId}'),
        ApiClient.shared.get('/destinations'),
      ]);
      final userData = results[0] as Map<String, dynamic>;
      final destList = results[1] as List;
      setState(() {
        _user         = BuddyUser.fromJson(userData);
        _buddyProfile = userData['buddy_profile'] as Map<String, dynamic>?;
        _destinations = destList.map((j) => Destination.fromJson(j)).toList();
        _specialties  = Set<String>.from(
          (_buddyProfile?['specialties'] as List?)?.cast<String>() ?? const <String>[]);
        _loading      = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _toggleSpecialty(String value) async {
    HapticFeedback.selectionClick();
    final previous = Set<String>.from(_specialties);
    setState(() {
      if (_specialties.contains(value)) {
        _specialties.remove(value);
      } else {
        _specialties.add(value);
      }
      _savingSpecialties = true;
    });
    try {
      await ApiClient.shared.patch('/buddy/specialties', {'specialties': _specialties.toList()});
    } catch (e) {
      if (mounted) setState(() => _specialties = previous); // revertir si falla
    } finally {
      if (mounted) setState(() => _savingSpecialties = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.shared.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const PhoneScreen()), (_) => false);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BuddyColors.surface,
        title: const Text('¿Eliminar tu cuenta?', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700)),
        content: const Text(
          'Se eliminarán todos tus datos personales de forma permanente. Esta acción no se puede deshacer.',
          style: TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: BuddyColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiClient.shared.delete('/users/me');
      await AuthService.shared.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const PhoneScreen()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: BuddyColors.error),
      );
    }
  }

  Future<void> _showDestinationPicker() async {
    final current = _buddyProfile?['destination_id'] as String?;

    final picked = await showModalBottomSheet<Destination>(
      context: context,
      backgroundColor: BuddyColors.canvas,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DestinationPicker(destinations: _destinations, currentId: current),
    );

    if (picked == null || !mounted) return;

    try {
      await ApiClient.shared.post('/buddy/profile', {'destination_id': picked.id});
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Zona actualizada a ${picked.name}'), backgroundColor: BuddyColors.success),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: BuddyColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final destName = (_buddyProfile?['destination'] as Map<String, dynamic>?)?['name'] as String?;

    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      appBar: AppBar(title: const Text('Mi perfil'), actions: [
        TextButton(
          onPressed: _logout,
          child: const Text('Salir', style: TextStyle(color: BuddyColors.error, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: BuddyColors.teal))
          : RefreshIndicator(
              color: BuddyColors.teal,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const SizedBox(height: 12),
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: BuddyColors.sandLight,
                    backgroundImage: _user?.avatarUrl != null ? NetworkImage(_user!.avatarUrl!) : null,
                    child: _user?.avatarUrl == null
                        ? const Icon(Icons.person_rounded, size: 44, color: BuddyColors.sand)
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Text(_user?.fullName ?? 'Buddy', style: BT.title2),
                  if (_user?.nationality != null) ...[
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.language_rounded, size: 13, color: BuddyColors.inkMuted),
                      const SizedBox(width: 4),
                      Text(_user!.nationality!, style: BT.footnote),
                    ]),
                  ],
                  const SizedBox(height: 28),

                  // ── Mi zona ──────────────────────────────────────────
                  _sectionCard(
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: BuddyColors.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_on_rounded, color: BuddyColors.teal, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('MI ZONA', style: BT.eyebrow),
                        const SizedBox(height: 2),
                        Text(
                          destName ?? 'Sin zona asignada',
                          style: destName != null ? BT.bodyBold : BT.body.copyWith(color: BuddyColors.inkMuted),
                        ),
                      ])),
                      TextButton(
                        onPressed: _destinations.isEmpty ? null : _showDestinationPicker,
                        child: Text(
                          destName == null ? 'Asignar' : 'Cambiar',
                          style: BT.callout.copyWith(color: BuddyColors.teal, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // ── Mis especialidades ───────────────────────────────
                  _sectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('EN QUÉ AYUDAS', style: BT.eyebrow),
                        const Spacer(),
                        if (_savingSpecialties)
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: BuddyColors.teal)),
                      ]),
                      const SizedBox(height: 4),
                      Text('Elige las necesidades que sabes resolver. Te llegarán solicitudes que coincidan.',
                        style: BT.caption),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _specialtyOptions.map((opt) {
                          final (value, label, icon) = opt;
                          final selected = _specialties.contains(value);
                          return GestureDetector(
                            onTap: () => _toggleSpecialty(value),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: selected ? BuddyColors.teal.withValues(alpha: 0.12) : BuddyColors.canvas,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected ? BuddyColors.teal : BuddyColors.border,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(icon, size: 15, color: selected ? BuddyColors.teal : BuddyColors.inkMuted),
                                const SizedBox(width: 6),
                                Text(label, style: TextStyle(
                                  fontFamily: 'Inter', fontSize: 13,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? BuddyColors.teal : BuddyColors.ink,
                                )),
                                if (selected) ...[
                                  const SizedBox(width: 5),
                                  const Icon(Icons.check_circle_rounded, size: 14, color: BuddyColors.teal),
                                ],
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // ── Documento ────────────────────────────────────────
                  if (_user?.docNumber != null) _sectionCard(
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: BuddyColors.sand.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.badge_outlined, color: BuddyColors.sand, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('DOCUMENTO', style: BT.eyebrow),
                        const SizedBox(height: 2),
                        Text('${_user!.docType ?? 'DNI'} ${_user!.docNumber}', style: BT.bodyBold),
                      ]),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // ── Stats ─────────────────────────────────────────────
                  Row(children: [
                    for (final (label, value) in [
                      ('Total helps', '${(_buddyProfile?['total_helps'] ?? 0)}'),
                      ('Rating', '${(_buddyProfile?['rating_avg'] ?? 5.0)}'),
                    ])
                      Expanded(child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(color: BuddyColors.surface, borderRadius: BorderRadius.circular(12)),
                        child: Column(children: [
                          Text(value, style: BT.title2.copyWith(color: BuddyColors.teal)),
                          const SizedBox(height: 4),
                          Text(label, style: BT.caption),
                        ]),
                      )),
                  ]),

                  const SizedBox(height: 12),

                  // ── Bio ───────────────────────────────────────────────
                  if (_user?.bio != null && _user!.bio!.isNotEmpty)
                    _sectionCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('SOBRE MÍ', style: BT.eyebrow),
                        const SizedBox(height: 8),
                        Text(_user!.bio!, style: BT.body),
                      ]),
                    ),

                  const SizedBox(height: 32),

                  // ── Cuenta ───────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Cerrar sesión'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BuddyColors.inkMuted,
                        side: const BorderSide(color: BuddyColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _deleteAccount,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Eliminar mi cuenta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BuddyColors.error,
                        side: BorderSide(color: BuddyColors.error.withOpacity(0.3)),
                        backgroundColor: BuddyColors.error.withOpacity(0.04),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ]),
              ),
            ),
    );
  }

  Widget _sectionCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: BuddyColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

// ── Destination bottom sheet picker ──────────────────────────────────────────
class _DestinationPicker extends StatelessWidget {
  final List<Destination> destinations;
  final String? currentId;
  const _DestinationPicker({required this.destinations, this.currentId});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ELIGE TU ZONA', style: BT.eyebrow),
        const SizedBox(height: 4),
        Text('¿Dónde quieres ser buddy?', style: BT.title3),
        const SizedBox(height: 20),
        ...destinations.map((d) {
          final isSelected = d.id == currentId;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? BuddyColors.teal : BuddyColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Material(
              color: isSelected ? BuddyColors.teal.withValues(alpha: 0.08) : BuddyColors.surface,
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context, d);
                },
                borderRadius: BorderRadius.circular(11),
                splashColor: BuddyColors.teal.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    if (d.coverUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(imageUrl: d.coverUrl!, width: 44, height: 44, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _fallback),
                      )
                    else _fallback,
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.name, style: BT.bodyBold),
                      Text(d.city, style: BT.caption),
                    ])),
                    if (isSelected) const Icon(Icons.check_circle_rounded, color: BuddyColors.teal, size: 20),
                  ]),
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget get _fallback => Container(
    width: 44, height: 44,
    decoration: BoxDecoration(color: BuddyColors.sandLight, borderRadius: BorderRadius.circular(8)),
    child: const Icon(Icons.location_on_rounded, color: BuddyColors.sand, size: 22),
  );
}
