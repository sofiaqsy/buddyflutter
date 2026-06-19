import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../models/models.dart';
import '../home/home_screen.dart';

class DestinationSetupScreen extends StatefulWidget {
  const DestinationSetupScreen({super.key});
  @override State<DestinationSetupScreen> createState() => _DestinationSetupScreenState();
}

class _DestinationSetupScreenState extends State<DestinationSetupScreen> {
  List<Destination> _destinations = [];
  Destination? _selected;
  bool _loadingDests = true;
  bool _saving       = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final list = await ApiClient.shared.get('/destinations') as List;
      setState(() {
        _destinations = list.map((j) => Destination.fromJson(j)).toList();
        _loadingDests = false;
      });
    } catch (_) {
      setState(() => _loadingDests = false);
    }
  }

  Future<void> _save() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    try {
      await ApiClient.shared.post('/buddy/profile', {
        'destination_id': _selected!.id,
      });
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: BuddyColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Progress
                Row(children: [
                  _dot(false), const SizedBox(width: 6),
                  _dot(true),
                ]),
                const SizedBox(height: 32),

                Text('TU ZONA', style: BT.eyebrow),
                const SizedBox(height: 6),
                Text('¿dónde eres\nbuddy?', style: BT.title1),
                const SizedBox(height: 8),
                Text('Selecciona el destino donde ayudarás a los viajeros.', style: BT.footnote),
                const SizedBox(height: 28),
              ]),
            ),

            Expanded(
              child: _loadingDests
                  ? const Center(child: CircularProgressIndicator(color: BuddyColors.teal))
                  : _destinations.isEmpty
                      ? Center(child: Text('No hay destinos disponibles', style: BT.footnote))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          itemCount: _destinations.length,
                          itemBuilder: (_, i) => _DestCard(
                            destination: _destinations[i],
                            selected: _selected?.id == _destinations[i].id,
                            onTap: () => setState(() => _selected = _destinations[i]),
                          ),
                        ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewPadding.bottom + 24),
              child: ElevatedButton(
                onPressed: (_selected == null || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_selected == null ? 'Selecciona un destino' : 'Empezar como buddy en ${_selected!.name}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(bool active) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    width: active ? 24 : 8, height: 8,
    decoration: BoxDecoration(
      color: active ? BuddyColors.teal : BuddyColors.border,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}

class _DestCard extends StatelessWidget {
  final Destination destination;
  final bool selected;
  final VoidCallback onTap;

  const _DestCard({required this.destination, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? BuddyColors.teal : BuddyColors.border,
            width: selected ? 2 : 1,
          ),
          color: selected ? BuddyColors.teal.withOpacity(0.05) : BuddyColors.surface,
          boxShadow: selected ? [BoxShadow(color: BuddyColors.teal.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(children: [
            // Cover image
            if (destination.coverUrl != null)
              SizedBox(
                height: 110,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: destination.coverUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: BuddyColors.sandLight),
                  errorWidget: (_, __, ___) => Container(color: BuddyColors.sandLight),
                ),
              )
            else
              Container(
                height: 110,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [BuddyColors.tealDeep, BuddyColors.teal],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

            // Gradient overlay
            Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            // Text
            Positioned(
              bottom: 14, left: 16, right: 50,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(destination.name, style: const TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(destination.city, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: Colors.white70)),
              ]),
            ),

            // Checkmark
            if (selected)
              Positioned(
                top: 12, right: 12,
                child: Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(color: BuddyColors.teal, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
