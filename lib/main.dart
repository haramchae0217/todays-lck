import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await initializeDateFormatting('ko');
  await NotificationService.instance.initialize();
  runApp(const ProviderScope(child: LckApp()));
}

class LckApp extends StatelessWidget {
  const LckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LCK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0891B2),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF0891B2),
          surface: const Color(0xFF111528),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0E1A),
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFFF1F5F9),
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: Color(0xFF94A3B8)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0D1225),
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFF0891B2).withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? const Color(0xFF0891B2) : const Color(0xFF475569),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? const Color(0xFF0891B2) : const Color(0xFF475569),
              size: 22,
            );
          }),
        ),
        dividerColor: const Color(0xFF1E293B),
        cardColor: const Color(0xFF111528),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF0891B2))),
      ),
      error: (_, __) => const LoginScreen(),
      data: (user) => user != null ? const HomeScreen() : const LoginScreen(),
    );
  }
}
