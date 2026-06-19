import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';
import '../../core/theme.dart';
import '../../core/auth_service.dart';
import '../home/home_screen.dart';
import '../onboarding/profile_setup_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  bool _loading = false;
  String _otp = '';

  Future<void> _verify(String otp) async {
    if (otp.length < 6) return;
    setState(() => _loading = true);
    final result = await AuthService.shared.verifyOtp(widget.phone, otp);
    if (!mounted) return;
    if (result != null) {
      final needsOnboarding = !(result['hasProfile'] ?? false);
      Navigator.pushAndRemoveUntil(
        context,
        context.buddyRoute(needsOnboarding ? const ProfileSetupScreen() : const HomeScreen()),
        (_) => false,
      );
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código incorrecto. Intenta de nuevo.'), backgroundColor: BuddyColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 52, height: 56,
      textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: BuddyColors.ink),
      decoration: BoxDecoration(
        color: BuddyColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BuddyColors.border),
      ),
    );

    return Scaffold(
      body: KeyboardDismiss(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                color: BuddyColors.ink,
              ),
              const SizedBox(height: 32),

              Text('VERIFICACIÓN', style: BT.eyebrow),
              const SizedBox(height: 4),
              Text('revisa tu\nteléfono.', style: BT.title1),
              const SizedBox(height: 12),
              RichText(text: TextSpan(children: [
                const TextSpan(text: 'Enviamos un código a ', style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: BuddyColors.inkMuted)),
                TextSpan(text: widget.phone, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: BuddyColors.ink)),
              ])),

              const SizedBox(height: 40),

              Center(
                child: Pinput(
                  length: 6,
                  defaultPinTheme: pinTheme,
                  focusedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      border: Border.all(color: BuddyColors.teal, width: 1.5),
                    ),
                  ),
                  onCompleted: _verify,
                  onChanged: (v) => setState(() => _otp = v),
                ),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: (_loading || _otp.length < 6) ? null : () => _verify(_otp),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verificar'),
              ),

              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () async {
                    await AuthService.shared.sendOtp(widget.phone);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Código reenviado')),
                    );
                  },
                  child: Text('Reenviar código', style: BT.callout.copyWith(color: BuddyColors.teal)),
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
