import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/api_service.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/calendar_page.dart';
import 'pages/history_page.dart';
import 'pages/following_page.dart';
import 'widgets/error_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiService.init();

  // Global async error handler — catches errors outside the widget tree
  runZonedGuarded((() {
    runApp(const AniMapleApp());
  }), (error, stackTrace) {
    debugPrint('UNCAUGHT ERROR: $error');
    debugPrint('$stackTrace');
  });
}

class AniMapleApp extends StatelessWidget {
  const AniMapleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniMaple',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0812),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF0a0812),
          primary: Color(0xFF8b5cf6),
          secondary: Color(0xFFa78bfa),
          onSurface: Color(0xFFe8e4f0),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        cardTheme: CardThemeData(
          color: const Color(0xFF110e1a),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0a0812),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const ErrorBoundary(child: MainShell()),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // Keys to access page state for refresh
  final _historyKey = GlobalKey<HistoryPageState>();
  final _followingKey = GlobalKey<FollowingPageState>();

  void _onTabChanged(int index) {
    setState(() => _currentIndex = index);
    // Refresh pages that need fresh data when tab becomes active
    if (index == 3) _historyKey.currentState?.refresh();
    if (index == 4) _followingKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const HomePage(),
          const SearchPage(),
          const CalendarPage(),
          HistoryPage(key: _historyKey),
          FollowingPage(key: _followingKey),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabChanged,
        backgroundColor: const Color(0xFF0a0812).withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF8b5cf6).withValues(alpha: 0.15),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Color(0xFFa78bfa)),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search, color: Color(0xFFa78bfa)),
            label: 'Catálogo',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today, color: Color(0xFFa78bfa)),
            label: 'Horario',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: Color(0xFFa78bfa)),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite, color: Color(0xFFa78bfa)),
            label: 'Mi lista',
          ),
        ],
      ),
    );
  }
}
