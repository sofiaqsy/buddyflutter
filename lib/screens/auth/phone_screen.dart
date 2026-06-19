import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/auth_service.dart';
import 'otp_screen.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  String _countryCode = '+51';

  Future<void> _sendOtp() async {
    final phone = '$_countryCode${_phoneCtrl.text.trim()}';
    if (phone.length < 8) return;
    setState(() => _loading = true);
    try {
      await AuthService.shared.sendOtp(phone);
      if (!mounted) return;
      Navigator.push(context, context.buddyRoute(OtpScreen(phone: phone)));
    } catch (e) {
      if (!mounted) return;
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
      body: KeyboardDismiss(
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Logo
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: BuddyColors.teal,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text('B', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 32),

              Text('BUDDY PARA', style: BT.eyebrow),
              const SizedBox(height: 4),
              RichText(text: const TextSpan(children: [
                TextSpan(text: 'hola, ', style: BT.title1),
                TextSpan(text: 'buddy.', style: TextStyle(
                  fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w800,
                  color: BuddyColors.sand, fontStyle: FontStyle.italic,
                )),
              ])),
              const SizedBox(height: 8),
              Text('Ingresa tu número para continuar', style: BT.footnote),

              const SizedBox(height: 40),

              // Country + phone
              Row(children: [
                GestureDetector(
                  onTap: _showCountryPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: BuddyColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BuddyColors.border),
                    ),
                    child: Row(children: [
                      Text(_countryCode, style: BT.bodyBold),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, size: 16, color: BuddyColors.inkMuted),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: BT.body,
                    decoration: const InputDecoration(hintText: '999 123 456'),
                    onSubmitted: (_) => _sendOtp(),
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _loading ? null : _sendOtp,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Continuar →'),
              ),

              const Spacer(),
              Center(
                child: Text(
                  'Al continuar aceptas nuestros términos de uso.',
                  style: BT.caption,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      )),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: BuddyColors.canvas,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom;
        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 16),
          children: [
            Text('Código de país', style: BT.title3),
            const SizedBox(height: 16),
            for (final (code, name) in [
              ('+51', '🇵🇪 Perú'),
              ('+1',  '🇺🇸 USA'),
              ('+34', '🇪🇸 España'),
              ('+57', '🇨🇴 Colombia'),
              ('+56', '🇨🇱 Chile'),
              ('+52', '🇲🇽 México'),
              ('+54', '🇦🇷 Argentina'),
            ])
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: Text(name, style: BT.body),
                trailing: Text(code, style: BT.bodyBold),
                selected: code == _countryCode,
                selectedColor: BuddyColors.teal,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _countryCode = code);
                  Navigator.pop(context);
                },
              ),
          ],
        );
      },
    );
  }
}
