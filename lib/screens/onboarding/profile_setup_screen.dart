import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';
import '../../core/auth_service.dart';
import '../home/home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _docCtrl    = TextEditingController();
  String _docType   = 'DNI';
  bool _loading     = false;
  bool _accepted    = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _docCtrl.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar los Términos y Condiciones para continuar.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiClient.shared.patch('/users/${AuthService.shared.userId}', {
        'full_name':  _nameCtrl.text.trim(),
        'doc_type':   _docType,
        'doc_number': _docCtrl.text.trim(),
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuddyColors.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),

                // Progress
                Row(children: [
                  _dot(true), const SizedBox(width: 6),
                  _dot(false),
                ]),
                const SizedBox(height: 32),

                Text('DATOS PERSONALES', style: BT.eyebrow),
                const SizedBox(height: 6),
                Text('cuéntanos\nquién eres.', style: BT.title1),
                const SizedBox(height: 8),
                Text('Esta información es necesaria para verificar tu identidad como buddy.', style: BT.footnote),

                const SizedBox(height: 36),

                // Full name
                Text('NOMBRE COMPLETO', style: BT.eyebrow),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: BT.body,
                  decoration: _inputDecoration('Ej. María García López'),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Ingresa tu nombre completo' : null,
                ),

                const SizedBox(height: 20),

                // Doc type
                Text('TIPO DE DOCUMENTO', style: BT.eyebrow),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: BuddyColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BuddyColors.border),
                  ),
                  child: DropdownButtonFormField<String>(
                    value: _docType,
                    style: BT.body,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: InputBorder.none,
                    ),
                    items: ['DNI', 'Pasaporte', 'CE'].map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)),
                    ).toList(),
                    onChanged: (v) => setState(() => _docType = v!),
                  ),
                ),

                const SizedBox(height: 20),

                // Doc number
                Text('NÚMERO DE DOCUMENTO', style: BT.eyebrow),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _docCtrl,
                  keyboardType: TextInputType.number,
                  style: BT.body,
                  decoration: _inputDecoration('Ej. 12345678'),
                  validator: (v) => (v == null || v.trim().length < 6) ? 'Ingresa tu número de documento' : null,
                ),

                const SizedBox(height: 28),

                // T&C + Privacy acceptance
                GestureDetector(
                  onTap: () => setState(() => _accepted = !_accepted),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _accepted ? BuddyColors.teal.withOpacity(0.06) : BuddyColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accepted ? BuddyColors.teal : BuddyColors.border,
                        width: _accepted ? 1.5 : 1,
                      ),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: _accepted ? BuddyColors.teal : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _accepted ? BuddyColors.teal : BuddyColors.border, width: 2,
                          ),
                        ),
                        child: _accepted
                            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: BT.callout.copyWith(color: BuddyColors.ink),
                            children: const [
                              TextSpan(text: 'He leído y acepto los '),
                              TextSpan(text: 'Términos y Condiciones', style: TextStyle(color: BuddyColors.teal, fontWeight: FontWeight.w600)),
                              TextSpan(text: ', la '),
                              TextSpan(text: 'Política de Privacidad', style: TextStyle(color: BuddyColors.teal, fontWeight: FontWeight.w600)),
                              TextSpan(text: ' y el '),
                              TextSpan(text: 'Código de Conducta', style: TextStyle(color: BuddyColors.teal, fontWeight: FontWeight.w600)),
                              TextSpan(text: ' de Buddy. Confirmo que tengo 18 años o más.'),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: (_loading || !_accepted) ? null : _next,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Continuar →'),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
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

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: BT.footnote,
    filled: true,
    fillColor: BuddyColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: BuddyColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: BuddyColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: BuddyColors.teal, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: BuddyColors.error)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: BuddyColors.error, width: 1.5)),
  );
}
