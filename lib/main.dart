import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
    httpClient: _TimeoutClient(),
  );
  runApp(const LogbookApp());
}

/// Gives every server request a time limit, so a bad mobile connection shows
/// an error with Retry instead of a spinner that never stops.
class _TimeoutClient extends http.BaseClient {
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(const Duration(seconds: 20));
}

class LogbookApp extends StatelessWidget {
  const LogbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: const AuthGate(),
    );
  }
}

ThemeData _theme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    primary: Brand.blue,
    secondary: Brand.orange,
    tertiary: Brand.sky,
    surface: Colors.white,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.mist,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.mist,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Brand.ink,
      titleTextStyle: TextStyle(
          color: Brand.ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Brand.blue.withValues(alpha: 0.07)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: rounded)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Brand.blue,
      foregroundColor: Colors.white,
      shape: rounded,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border(Brand.blue.withValues(alpha: 0.15)),
      enabledBorder: border(Brand.blue.withValues(alpha: 0.15)),
      focusedBorder: border(Brand.blue, 2),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Brand.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

/// Shows Login or Home depending on whether someone is signed in.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
              scale: Tween(begin: 0.97, end: 1.0).animate(anim), child: child),
        ),
        child: auth.currentSession == null
            ? const LoginScreen(key: ValueKey('login'))
            : const HomeScreen(key: ValueKey('home')),
      ),
    );
  }
}
