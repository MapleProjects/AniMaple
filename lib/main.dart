import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/calendar_page.dart';
import 'pages/history_page.dart';
import 'pages/following_page.dart';
import 'widgets/error_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiService.init();

  // Restaurar sesión de Google Sign-In y sincronizar en segundo plano.
  // Patrón oficial google_sign_in v7: initialize() → attemptLightweightAuthentication()
  // UNA sola vez (tras el primer frame, cuando existe contexto de Activity).
  // NO en bucle: cada llamada en Android puede abrir el selector de cuentas.
  // El estado real (login/logout) se refleja vía authenticationEvents en la UI.
  unawaited(() async {
    await SyncService.initialize();
    // Arrancar SIEMPRE el polling de 10s y el watcher de conectividad, esté
    // o no la sesión restaurada todavía: si la app inicia sin Internet, al
    // volver la red el watcher reintenta restaurar sesión y sincronizar —
    // todo de fondo, el usuario no tiene que tocar nada.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncService.startAutoSync();
      SyncService.watchConnectivity();
      SyncService.attemptRestoreAndSync();
      // Notificaciones: permiso + agendado del worker + espejo de seguidos.
      // Se pide al ARRANQUE (no al entrar a un capítulo): app recién instalada
      // debe tener todas las notificaciones habilitadas desde el comienzo.
      NotificationService.init();
      // Si el permiso de notificaciones fue denegado de forma permanente
      // (Android 13+: "Don't allow" no permite volver a preguntar), guiar una
      // sola vez a Ajustes. Sin esto, un usuario que negó sin querer jamás
      // recibe avisos de capítulos nuevos, ni con la app abierta ni cerrada.
      Future.delayed(const Duration(milliseconds: 1500), () async {
        final status = await NotificationService.notificationStatus();
        if (status != 'permanent') return;
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('notif_settings_prompted') ?? false) return;
        await prefs.setBool('notif_settings_prompted', true);
        final ctx = AniMapleApp.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        await showDialog<void>(
          context: ctx,
          builder: (dctx) => AlertDialog(
            title: const Text('Activa las notificaciones'),
            content: const Text(
              'AniMaple necesita permiso para avisarte cuando un anime de '
              'tu lista estrena capítulo, incluso con la app cerrada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Ahora no'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dctx);
                  NotificationService.openAppNotificationSettings();
                },
                child: const Text('Abrir ajustes'),
              ),
            ],
          ),
        );
      });
      // Optimización de batería (Doze): el worker de capítulos revisa cada
      // 8 min en segundo plano y tras reinicios. Si el sistema difiere el
      // trabajo en reposo, los avisos se retrasan. Eximir a la app (una sola
      // vez, dialog del sistema) la equipara a WhatsApp/Facebook.
      Future.delayed(const Duration(milliseconds: 2400), () async {
        final ignored = await NotificationService.isBatteryOptimizationIgnored();
        if (ignored) return;
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('battery_prompt_done') ?? false) return;
        await prefs.setBool('battery_prompt_done', true);
        final ctx = AniMapleApp.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        await showDialog<void>(
          context: ctx,
          builder: (dctx) => AlertDialog(
            title: const Text('Notificaciones en segundo plano'),
            content: const Text(
              'Para que los avisos de capítulos lleguen incluso con el '
              'teléfono en reposo o tras reiniciarlo, permite que AniMaple '
              'ignore la optimización de batería.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('No, gracias'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dctx);
                  NotificationService.requestBatteryOptimizationExemption();
                },
                child: const Text('Activar'),
              ),
            ],
          ),
        );
      });
      // Actualización: consultar releases de GitHub. Si hay versión nueva,
      // mostrar el diálogo Actualizar/Posponer (diálogo también accesible
      // desde el botón-badge junto a la cuenta).
      Future.delayed(const Duration(milliseconds: 2500), () async {
        final hasUpdate = await UpdateService.checkForUpdate();
        if (!hasUpdate) return;
        final ctx = AniMapleApp.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final update = await UpdateService.showUpdateDialog(ctx);
        if (update == true &&
            AniMapleApp.navigatorKey.currentContext?.mounted == true) {
          await UpdateService.downloadAndInstall(
              AniMapleApp.navigatorKey.currentContext!);
        }
      });
    });
  }());

  // Global async error handler — catches errors outside the widget tree
  runZonedGuarded(
    (() {
      runApp(const AniMapleApp());
    }),
    (error, stackTrace) {
      debugPrint('UNCAUGHT ERROR: $error');
      debugPrint('$stackTrace');
    },
  );
}

class AniMapleApp extends StatelessWidget {
  const AniMapleApp({super.key});

  /// Navigator global para mostrar diálogos desde servicios (ej. actualización).
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AniMaple',
      navigatorKey: navigatorKey,
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

  @override
  void initState() {
    super.initState();
    // Reaccionar a cambios del estado local (merge desde la nube o logout)
    // para reflejarlos en vivo sin resync manual.
    SyncService.stateVersion.addListener(_onSyncStateChanged);
  }

  @override
  void dispose() {
    SyncService.stateVersion.removeListener(_onSyncStateChanged);
    super.dispose();
  }

  void _onSyncStateChanged() {
    if (!mounted) return;
    _historyKey.currentState?.refresh();
    _followingKey.currentState?.refresh();
  }

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
