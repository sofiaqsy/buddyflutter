import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'core/theme.dart';
import 'core/auth_service.dart';
import 'core/api_client.dart';
import 'core/push_service.dart';
import 'screens/auth/phone_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/profile_setup_screen.dart';

Widget _startScreen = const PhoneScreen();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.dark,
  ));
  await initializeDateFormatting('es', null);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AuthService.shared.init();
  await AuthService.shared.tryRefresh();

  if (AuthService.shared.isLoggedIn) {
    _startScreen = await _resolveHome();
    await PushService.shared.init();
  }

  runApp(const BuddyApp());
}

Future<Widget> _resolveHome() async {
  try {
    final data = await ApiClient.shared.get('/users/${AuthService.shared.userId}');
    final hasName = data['full_name'] != null && (data['full_name'] as String).isNotEmpty;
    if (!hasName) return const ProfileSetupScreen();
    return const HomeScreen();
  } catch (_) {
    return const HomeScreen();
  }
}

class BuddyApp extends StatelessWidget {
  const BuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BuddyGuide',
      debugShowCheckedModeBanner: false,
      theme: BuddyTheme.theme,
      scrollBehavior: BuddyScrollBehavior(),
      home: _startScreen,
    );
  }
}
