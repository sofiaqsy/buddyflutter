import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../core/auth_service.dart';
import '../../models/models.dart';
import '../chat/chat_screen.dart';

class TravelerDetailScreen extends StatelessWidget {
  final HelpRequest? request;
  final Match? match;
  final VoidCallback? onAccept;

  const TravelerDetailScreen({super.key, this.request, this.match, this.onAccept});

  factory TravelerDetailScreen.fromMatch({required Match match}) =>
      TravelerDetailScreen(match: match, request: match.request);

  BuddyUser? get traveler => request?.traveler ?? match?.traveler;
  HelpRequest? get req     => request ?? match?.request;
  bool get hasMatch        => match != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      body: CustomScrollView(
        slivers: [
          _buildHeroAppBar(context),
          SliverToBoxAdapter(child: _buildContent(context)),
        ],
      ),
      bottomNavigationBar: _buildActions(context),
    );
  }

  Widget _buildHeroAppBar(BuildContext context) {
    final coverUrl = req?.destination?.coverUrl;
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: BuddyColors.canvas,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: coverUrl != null
            ? CachedNetworkImage(imageUrl: coverUrl, fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: BuddyColors.sandLight),
                errorWidget: (_, __, ___) => _gradientFallback)
            : _gradientFallback,
        title: Text(
          req?.destination?.name ?? 'Destino',
          style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        collapseMode: CollapseMode.pin,
      ),
    );
  }

  Widget get _gradientFallback => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [BuddyColors.tealDeep, BuddyColors.teal], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
  );

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Traveler card
        if (traveler != null) Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: BuddyColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: BuddyColors.sandLight,
              backgroundImage: traveler!.avatarUrl != null ? NetworkImage(traveler!.avatarUrl!) : null,
              child: traveler!.avatarUrl == null ? const Icon(Icons.person_rounded, size: 30, color: BuddyColors.inkMuted) : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(traveler!.fullName ?? 'Viajero', style: BT.title3),
              if (traveler!.nationality != null) Text(traveler!.nationality!, style: BT.footnote),
              if (traveler!.bio != null && traveler!.bio!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(traveler!.bio!, style: BT.callout, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ])),
          ]),
        ),

        const SizedBox(height: 20),

        // Trip info
        if (req != null) ...[
          Text('SOBRE EL TRIP', style: BT.eyebrow),
          const SizedBox(height: 12),
          _infoCard([
            if (req!.arrivalAt != null) _infoRow('Llegada', DateFormat('EEEE d MMM yyyy', 'es').format(req!.arrivalAt!.toLocal())),
            _infoRow('Necesita ayuda con', req!.categoryLabel),
            if (req!.description != null && req!.description!.isNotEmpty)
              _infoRow('Descripción', req!.description!),
          ]),
        ],

        // Match status
        if (hasMatch) ...[
          const SizedBox(height: 20),
          Text('CONEXIÓN', style: BT.eyebrow),
          const SizedBox(height: 12),
          _infoCard([
            _infoRow('Estado', _statusBadge(match!.status)),
            _infoRow('Desde', DateFormat('d MMM yyyy').format(match!.createdAt.toLocal())),
          ]),
        ],

        const SizedBox(height: 100),
      ]),
    );
  }

  Widget _infoCard(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: BuddyColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(children: children),
  );

  Widget _infoRow(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130, child: Text(label, style: BT.footnote)),
      Expanded(child: value is Widget ? value : Text(value.toString(), style: BT.callout)),
    ]),
  );

  Widget _statusBadge(String status) {
    final (color, label) = switch (status) {
      'active' => (BuddyColors.success, 'Activo'),
      'completed' => (BuddyColors.inkMuted, 'Completado'),
      _ => (BuddyColors.sand, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: MediaQuery.of(context).viewPadding.bottom + 16),
      decoration: const BoxDecoration(
        color: BuddyColors.surface,
        border: Border(top: BorderSide(color: BuddyColors.border)),
      ),
      child: hasMatch
          ? ElevatedButton.icon(
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(match: match!))),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Abrir chat'),
            )
          : Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    side: const BorderSide(color: BuddyColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                    foregroundColor: BuddyColors.ink,
                  ),
                  child: const Text('Rechazar', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Aceptar solicitud'),
                ),
              ),
            ]),
    );
  }
}
