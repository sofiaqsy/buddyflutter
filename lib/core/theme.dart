import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// ── Buddy Design System ────────────────────────────────────────────────────

class BuddyColors {
  static const canvas  = Color(0xFFF5F0E8);
  static const ink     = Color(0xFF1A1A1A);
  static const inkMuted = Color(0xFF6B6B6B);
  static const surface = Color(0xFFFFFFFF);
  static const border  = Color(0xFFE5E0D8);
  static const sand    = Color(0xFFC4965A);
  static const sandLight = Color(0xFFF0E6D6);
  static const teal    = Color(0xFF2D8B7A);
  static const tealDeep = Color(0xFF1A5C50);
  static const error   = Color(0xFFE53E3E);
  static const success = Color(0xFF38A169);
}

class BuddyTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: BuddyColors.canvas,
    colorScheme: ColorScheme.light(
      primary: BuddyColors.teal,
      secondary: BuddyColors.sand,
      surface: BuddyColors.surface,
      error: BuddyColors.error,
    ),
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: BuddyColors.canvas,
      foregroundColor: BuddyColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: BuddyColors.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BuddyColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuddyColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuddyColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: BuddyColors.teal, width: 1.5),
      ),
      hintStyle: const TextStyle(color: BuddyColors.inkMuted, fontSize: 15),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BuddyColors.ink,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

// ── Text Styles ────────────────────────────────────────────────────────────

// ── Scroll Behavior ────────────────────────────────────────────────────────
// Bouncing on iOS/macOS, clamping on Android — applied globally via MaterialApp.

class BuddyScrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      default:
        return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
  }
}

// ── Platform-aware page route ──────────────────────────────────────────────
// iOS → CupertinoPageRoute (native swipe-back + iOS slide transition).
// Android → horizontal PageRouteBuilder (Material doesn't use horizontal slide by default).

extension BuddyNavigation on BuildContext {
  PageRoute<T> buddyRoute<T>(Widget page) {
    if (Theme.of(this).platform == TargetPlatform.iOS) {
      return CupertinoPageRoute<T>(builder: (_) => page);
    }
    return PageRouteBuilder<T>(
      pageBuilder: (_, anim, __) => page,
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 320),
    );
  }
}

// ── Keyboard dismiss wrapper ───────────────────────────────────────────────
// Wrap any Scaffold body so tapping outside an input unfocuses it.

class KeyboardDismiss extends StatelessWidget {
  final Widget child;
  const KeyboardDismiss({super.key, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    behavior: HitTestBehavior.translucent,
    child: child,
  );
}

// ── Text Styles ────────────────────────────────────────────────────────────

class BT {
  static const displayLarge = TextStyle(fontFamily: 'Inter', fontSize: 36, fontWeight: FontWeight.w800, color: BuddyColors.sand);
  static const title1       = TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w700, color: BuddyColors.ink);
  static const title2       = TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w700, color: BuddyColors.ink);
  static const title3       = TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w600, color: BuddyColors.ink);
  static const body         = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w400, color: BuddyColors.ink);
  static const bodyBold     = TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: BuddyColors.ink);
  static const callout      = TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w400, color: BuddyColors.ink);
  static const footnote     = TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w400, color: BuddyColors.inkMuted);
  static const eyebrow      = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: BuddyColors.inkMuted, letterSpacing: 1.5);
  static const caption      = TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w400, color: BuddyColors.inkMuted);
}
