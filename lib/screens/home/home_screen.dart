import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/push_service.dart';
import '../../core/auth_service.dart';
import '../../models/models.dart';
import '../../widgets/request_card.dart';
import '../../widgets/match_card.dart';
import '../../widgets/shimmer_box.dart';
import '../../widgets/buddy_avatar.dart';
import '../traveler/traveler_detail_screen.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';
import '../zones/zones_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _tab = 0;
  bool _isAvailable = false;
  bool _loadingRequests = true;
  bool _loadingMatches = true;
  List<HelpRequest> _requests = [];
  List<HelpRequest> _history = [];   // aceptadas + perdidas
  List<Match> _matches = [];
  BuddyUser? _me;

  // Historial: se carga 1 vez + paginado por cursor; las nuevas se añaden local
  String? _historyCursor;
  bool _historyHasMore = true;
  bool _loadingMoreHistory = false;
  final ScrollController _requestsScroll = ScrollController();

  // Animación de transición entre tabs
  late AnimationController _tabCtrl;
  late Animation<double> _tabFade;

  @override
  void initState() {
    super.initState();
    _tabCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _tabFade = CurvedAnimation(parent: _tabCtrl, curve: Curves.easeOut);
    _tabCtrl.forward();
    // Paginado del historial al hacer scroll cerca del final
    _requestsScroll.addListener(() {
      if (_requestsScroll.position.pixels >= _requestsScroll.position.maxScrollExtent - 200) {
        _loadMoreHistory();
      }
    });
    _loadAll();
    _loadHistory();   // historial: una sola vez
    _initPush();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _requestsScroll.dispose();
    super.dispose();
  }

  Future<void> _initPush() async {
    try { await PushService.shared.init(); } catch (_) {}
    // Oferta de ayuda entrante (app abierta) → refresca y muestra Solicitudes
    PushService.shared.offerReceivedStream.listen((_) {
      if (!mounted) return;
      _loadRequests();
      if (_tab != 0) _switchTab(0);
      HapticFeedback.mediumImpact();
    });
    // Tap en la notificación → refresca solicitudes
    PushService.shared.pushNotificationStream.listen((_) {
      if (mounted) { _loadRequests(); if (_tab != 0) _switchTab(0); }
    });
  }

  // El contador de una solicitud llegó a 0 → se ofreció a otro buddy; la quitamos
  void _onRequestExpired(HelpRequest req) {
    if (!mounted) return;
    setState(() => _requests.removeWhere((r) => r.id == req.id));
    _addToHistory(req, 'missed');
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadMe(), _loadMatches()]);
    if (_me != null) await _loadRequests();
  }

  Future<void> _loadMe() async {
    try {
      final data = await ApiClient.shared.get('/users/${AuthService.shared.userId}');
      setState(() => _me = BuddyUser.fromJson(data));
      // Cargar disponibilidad real desde buddy_profile
      final profile = await ApiClient.shared.get('/buddy/profile');
      if (mounted) setState(() => _isAvailable = profile['is_available'] ?? false);
    } catch (_) {}
  }

  Future<void> _loadRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final list = await ApiClient.shared.get('/requests') as List;
      setState(() => _requests = list.map((j) => HelpRequest.fromJson(j)).toList());
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  // Historial: se invoca UNA vez (primera página). Las nuevas se añaden local.
  Future<void> _loadHistory() async {
    try {
      debugPrint('🕓 [history] GET /requests/history');
      final res = await ApiClient.shared.get('/requests/history?limit=20') as Map;
      final items = (res['items'] as List).map((j) => HelpRequest.fromJson(j)).toList();
      debugPrint('🕓 [history] recibidas ${items.length} items');
      if (!mounted) return;
      setState(() {
        _history = items;
        _historyCursor = res['nextCursor'];
        _historyHasMore = res['nextCursor'] != null;
      });
    } catch (e, st) {
      debugPrint('🕓 [history] ERROR: $e');
      debugPrint('$st');
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_loadingMoreHistory || !_historyHasMore || _historyCursor == null) return;
    setState(() => _loadingMoreHistory = true);
    try {
      final res = await ApiClient.shared
          .get('/requests/history?limit=20&before=${Uri.encodeComponent(_historyCursor!)}') as Map;
      final items = (res['items'] as List).map((j) => HelpRequest.fromJson(j)).toList();
      if (!mounted) return;
      setState(() {
        final seen = _history.map((h) => h.id).toSet();
        _history.addAll(items.where((it) => !seen.contains(it.id)));
        _historyCursor = res['nextCursor'];
        _historyHasMore = res['nextCursor'] != null;
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreHistory = false);
    }
  }

  // Añade una solicitud resuelta al historial local (sin recargar todo)
  void _addToHistory(HelpRequest r, String outcome) {
    if (_history.any((h) => h.id == r.id)) return;
    final item = HelpRequest(
      id: r.id, travelerId: r.travelerId, destinationId: r.destinationId,
      category: r.category, description: r.description, status: r.status,
      arrivalAt: r.arrivalAt, createdAt: r.createdAt,
      traveler: r.traveler, destination: r.destination,
      outcome: outcome, when: DateTime.now(),
    );
    setState(() => _history.insert(0, item));
  }

  Future<void> _loadMatches() async {
    setState(() => _loadingMatches = true);
    try {
      final list = await ApiClient.shared.get('/matches/${AuthService.shared.userId}') as List;
      final matches = list.map((j) => Match.fromJson(j)).toList();

      // Fetch last message for each match in parallel
      await Future.wait(matches.map((m) async {
        try {
          final msgs = await ApiClient.shared.get('/messages/${m.id}?preview=1&limit=1') as List;
          if (msgs.isNotEmpty) m.lastMessage = Message.fromJson(msgs.first);
        } catch (_) {}
      }));

      if (mounted) setState(() => _matches = matches);
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMatches = false);
    }
  }

  void _switchTab(int i) {
    if (i == _tab) return;
    HapticFeedback.selectionClick();
    _tabCtrl.forward(from: 0);
    setState(() => _tab = i);
  }

  Future<void> _acceptRequest(HelpRequest req) async {
    try {
      final raw = await ApiClient.shared.post('/matches', {
        'request_id': req.id,
        'buddy_id': AuthService.shared.userId,
      });
      final newMatch = Match.fromJson({
        ...raw,
        'traveler': req.traveler?.toJson(),
        'request': req.toJson(),
      });
      if (!mounted) return;
      _requests.removeWhere((r) => r.id == req.id);
      _addToHistory(req, 'accepted');
      await Navigator.push(context, context.buddyRoute(ChatScreen(match: newMatch)));
      if (!mounted) return;
      _switchTab(1);
      _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Error: $e')),
          ]),
          backgroundColor: BuddyColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      body: KeyboardDismiss(child: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            // Tab 0 — Solicitudes
            Column(children: [
              _buildHeader(),
              Expanded(
                child: FadeTransition(
                  opacity: _tabFade,
                  child: _buildRequestsTab(),
                ),
              ),
            ]),
            // Tab 1 — Ayudas
            Column(children: [
              _buildHeader(),
              Expanded(
                child: FadeTransition(
                  opacity: _tabFade,
                  child: _buildMatchesTab(),
                ),
              ),
            ]),
            // Tab 2 — Suscripciones (se mantiene vivo, no recarga al volver)
            const ZonesScreen(),
          ],
        ),
      )),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BUDDY APP', style: BT.eyebrow),
            const SizedBox(height: 2),
            Text(
              'hola, ${_me?.fullName?.split(' ').first ?? 'buddy'}.',
              style: const TextStyle(
                fontFamily: 'Inter', fontSize: 22,
                fontWeight: FontWeight.w700, color: BuddyColors.ink,
              ),
            ),
          ]),
        ),

        // Toggle disponibilidad
        GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            final next = !_isAvailable;
            setState(() => _isAvailable = next);
            try {
              await ApiClient.shared.patch('/buddy/availability', {'is_available': next});
              // Si se activa, recargar solicitudes
              if (next && mounted) _loadRequests();
            } catch (_) {
              // Revertir si falla
              if (mounted) setState(() => _isAvailable = !next);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _isAvailable
                  ? BuddyColors.teal.withValues(alpha: 0.12)
                  : BuddyColors.border,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isAvailable ? BuddyColors.teal : BuddyColors.border,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _isAvailable ? BuddyColors.teal : BuddyColors.inkMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _isAvailable ? BuddyColors.teal : BuddyColors.inkMuted,
                ),
                child: Text(_isAvailable ? 'disponible' : 'no disponible'),
              ),
            ]),
          ),
        ),

        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(context, context.buddyRoute(const ProfileScreen()));
          },
          child: BuddyAvatar(
            imageUrl: _me?.avatarUrl,
            fallbackName: _me?.fullName ?? '?',
            radius: 20,
            borderColor: BuddyColors.border,
          ),
        ),
      ]),
    );
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────

  Widget _buildRequestsTab() {
    return RefreshIndicator(
      color: BuddyColors.teal,
      displacement: 20,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await _loadRequests();
        if (mounted) HapticFeedback.lightImpact();
      },
      child: _loadingRequests
          ? _buildSkeleton()
          : (_requests.isEmpty && _history.isEmpty)
              ? _buildEmpty(
                  'No hay solicitudes',
                  'Cuando un viajero necesite ayuda en tu zona, aparecerá aquí.',
                  Icons.travel_explore_rounded,
                )
              : ListView(
                  controller: _requestsScroll,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    // Activas — con contador, aceptables
                    for (var i = 0; i < _requests.length; i++)
                      _AnimatedCard(
                        index: i,
                        child: RequestCard(
                          request: _requests[i],
                          onAccept: () => _acceptRequest(_requests[i]),
                          onExpired: () => _onRequestExpired(_requests[i]),
                          onView: () => Navigator.push(
                            context,
                            context.buddyRoute(TravelerDetailScreen(
                              request: _requests[i],
                              onAccept: () => _acceptRequest(_requests[i]),
                            )),
                          ),
                        ),
                      ),

                    // Historial — aceptadas y perdidas
                    if (_history.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 8, left: 4),
                        child: Text('Historial', style: BT.eyebrow),
                      ),
                      for (final h in _history) _HistoryRow(request: h),
                      if (_loadingMoreHistory)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: BuddyColors.teal),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }

  Widget _buildMatchesTab() {
    return RefreshIndicator(
      color: BuddyColors.teal,
      displacement: 20,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await _loadMatches();
        if (mounted) HapticFeedback.lightImpact();
      },
      child: _loadingMatches
          ? _buildMatchesSkeleton()
          : _matches.isEmpty
              ? _buildEmpty(
                  'Aún no tienes ayudas',
                  'Acepta una solicitud y conecta con tu primer viajero.',
                  Icons.handshake_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _matches.length,
                  itemBuilder: (_, i) => _AnimatedCard(
                    index: i,
                    child: MatchCard(
                      match: _matches[i],
                      onChat: () async {
                        final changed = await Navigator.push(
                          context,
                          context.buddyRoute(ChatScreen(match: _matches[i])),
                        );
                        // El chat se cerró por completar/cancelar → recargar Ayudas
                        if (changed == true && mounted) _loadMatches();
                      },
                      onView: () => Navigator.push(
                        context,
                        context.buddyRoute(TravelerDetailScreen.fromMatch(match: _matches[i])),
                      ),
                    ),
                  ),
                ),
    );
  }

  // ── Bottom nav ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    const tabs = [
      (0, Icons.inbox_rounded,          'Solicitudes'),
      (1, Icons.handshake_rounded,      'Ayudas'),
      (2, Icons.subscriptions_rounded,  'Suscripciones'),
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: BuddyColors.border)),
        color: BuddyColors.surface,
      ),
      padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 8),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final (i, icon, label) = tabs[idx];
          return Expanded(
            child: _NavItem(
              index: i,
              activeIndex: _tab,
              icon: icon,
              label: label,
              badge: i == 0 && _requests.isNotEmpty ? _requests.length : 0,
              onTap: () => _switchTab(i),
            ),
          );
        }),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Estado vacío — con ListView para que el RefreshIndicator funcione
  Widget _buildEmpty(String title, String subtitle, IconData icon) =>
    ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 52, color: BuddyColors.inkMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title, style: BT.title3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(subtitle, style: BT.footnote, textAlign: TextAlign.center),
            ),
          ]),
        ),
      ],
    );

  Widget _buildSkeleton() => ListView.builder(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    itemCount: 4,
    itemBuilder: (_, __) => const SkeletonCard(),
  );

  Widget _buildMatchesSkeleton() => ListView.builder(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    itemCount: 4,
    itemBuilder: (_, __) => const SkeletonMatchCard(),
  );
}

// ── Fila de historial: solicitud aceptada o perdida ───────────────────────
class _HistoryRow extends StatelessWidget {
  final HelpRequest request;
  const _HistoryRow({required this.request});

  bool get _accepted => request.outcome == 'accepted';

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final color = _accepted ? BuddyColors.teal : BuddyColors.inkMuted;
    final t = request.traveler;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: _accepted ? 1.0 : 0.7,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: BuddyColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BuddyColors.border),
          ),
          child: Row(children: [
            BuddyAvatar(imageUrl: t?.avatarUrl, fallbackName: t?.fullName ?? 'V', radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t?.fullName ?? 'Viajero', style: BT.bodyBold, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${request.categoryLabel}  ·  ${_ago(request.when)}',
                  style: BT.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_accepted ? Icons.check_circle_rounded : Icons.history_rounded, size: 13, color: color),
                const SizedBox(width: 4),
                Text(
                  _accepted ? 'Aceptada' : 'Perdida',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: color),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Card con animación de entrada escalonada ──────────────────────────────
class _AnimatedCard extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedCard({required this.index, required this.child});

  @override
  State<_AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<_AnimatedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    // Delay escalonado por índice
    Future.delayed(Duration(milliseconds: widget.index * 60), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ── Bottom nav item con escala + badge ────────────────────────────────────
class _NavItem extends StatefulWidget {
  final int index;
  final int activeIndex;
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.index,
    required this.activeIndex,
    required this.icon,
    required this.label,
    required this.badge,
    required this.onTap,
  });

  @override State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.82, upperBound: 1.0,
    );
    _ctrl.value = 1.0;
    _scale = _ctrl;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  bool get _active => widget.index == widget.activeIndex;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.reverse(),
      onTapUp: (_) { _ctrl.forward(); widget.onTap(); },
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Indicador activo
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              height: 3,
              width: _active ? 28.0 : 0.0,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: BuddyColors.teal,
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // Icono con badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.icon,
                    key: ValueKey(_active),
                    color: _active ? BuddyColors.teal : BuddyColors.inkMuted,
                    size: 24,
                  ),
                ),
                if (widget.badge > 0)
                  Positioned(
                    right: -6, top: -4,
                    child: AnimatedScale(
                      scale: widget.badge > 0 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.elasticOut,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: BuddyColors.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.badge > 9 ? '9+' : '${widget.badge}',
                          style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 9,
                            fontWeight: FontWeight.w700, color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontFamily: 'Inter', fontSize: 11,
                fontWeight: _active ? FontWeight.w700 : FontWeight.w500,
                color: _active ? BuddyColors.teal : BuddyColors.inkMuted,
              ),
              child: Text(widget.label),
            ),
          ]),
        ),
      ),
    );
  }
}
