import 'dart:async';
import 'dart:io' show Platform, File, FileMode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'services/api_service.dart';
import 'services/download_service.dart';
import 'services/sync_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'services/fsr_service.dart';
import 'services/hls_proxy.dart';
import 'services/tv_service.dart';
import 'services/app_player.dart';
import 'pages/home_page.dart';
import 'pages/search_page.dart';
import 'pages/calendar_page.dart';
import 'pages/history_page.dart';
import 'pages/following_page.dart';
import 'dart:ui' show PlatformDispatcher;
import 'package:path_provider/path_provider.dart';
import 'widgets/downloads_fab.dart';
import 'package:media_kit/media_kit.dart';
import 'widgets/error_dialog.dart';

void _setupCrashLogger() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _writeCrashLog('FlutterError', details.exceptionAsString(), details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT PLATFORM ERROR: $error');
    _writeCrashLog('PlatformDispatcher', error.toString(), stack);
    return true; // Evitar que el proceso termine abruptamente sin reporte
  };
}

void _writeCrashLog(String source, String error, StackTrace? stack) {
  try {
    getApplicationSupportDirectory().then((dir) {
      final file = File('${dir.path}/crash.log');
      final now = DateTime.now().toIso8601String();
      final content = '[$now] [$source]\nError: $error\nStack trace:\n${stack ?? ''}\n----------------------------------------\n';
      file.writeAsStringSync(content, mode: FileMode.append);
    });
  } catch (_) {}
}

void _setupFileLogger() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    original(message, wrapWidth: wrapWidth);
    if (message != null) {
      try {
        final home = Platform.environment['HOME'] ?? '';
        final file = File('$home/.local/share/com.mapleprojects.animaple/player.log');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('[${DateTime.now().toIso8601String()}][DEBUG] $message\n', mode: FileMode.append, flush: true);
      } catch (_) {}
    }
  };
}

void main() async {
  _setupCrashLogger();
  _setupFileLogger();
  WidgetsFlutterBinding.ensureInitialized();
  await TvService.init();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    MediaKit.ensureInitialized();
  }
  ApiService.init();
  // Iniciar proxy local HTTP de alto rendimiento para streaming concurrente
  unawaited(HlsProxy.instance.start());
  // Descargas offline: cargar índice y limpiar .part huérfanos de sesiones
  // anteriores (crash/apagado a mitad de descarga).
  unawaited(DownloadService.instance.init());
  unawaited(FsrService.init());
  // Limpieza proactiva de cualquier resto de caché de reproducción previa
  unawaited(AppPlayer.clearPlaybackCacheGlobal());

  // Restaurar sesión de Google Sign-In y sincronizar en segundo plano.
  // google_sign_in 6.x usa signInSilently() (100% invisible en Android, sin
  // ventanas emergentes de Credential Manager).
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
    return ValueListenableBuilder<bool>(
      valueListenable: TvService.isTv,
      builder: (context, isTv, _) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isWideLayout = isTv || Platform.isLinux || Platform.isWindows || screenWidth > 800;

        if (isWideLayout) {
          return Scaffold(
            body: Row(
              children: [
                Container(
                  width: 96,
                  color: const Color(0xFF0e0b18),
                  child: SafeArea(
                    right: false,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 16),
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF8b5cf6), Color(0xFFec4899)],
                            ).createShader(bounds),
                            child: const Text(
                              'AniMaple',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildRailItem(0, 'Inicio', Icons.home_outlined, Icons.home),
                              _buildRailItem(1, 'Catálogo', Icons.search_outlined, Icons.search),
                              _buildRailItem(2, 'Horario', Icons.calendar_today_outlined, Icons.calendar_today),
                              _buildRailItem(3, 'Historial', Icons.history_outlined, Icons.history),
                              _buildRailItem(4, 'Mi lista', Icons.favorite_outline, Icons.favorite),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1, color: Color(0xFF1e1832)),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      const HomePage(),
                      const SearchPage(),
                      const CalendarPage(),
                      HistoryPage(key: _historyKey),
                      FollowingPage(key: _followingKey),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: isTv ? null : const DownloadsFab(),
          );
        }

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
          floatingActionButton: const DownloadsFab(),
        );
      },
    );
  }

  Widget _buildRailItem(
    int index,
    String label,
    IconData unselectedIcon,
    IconData selectedIcon,
  ) {
    return _RailNavItem(
      isSelected: _currentIndex == index,
      label: label,
      unselectedIcon: unselectedIcon,
      selectedIcon: selectedIcon,
      onTap: () => _onTabChanged(index),
    );
  }
}

class _RailNavItem extends StatefulWidget {
  final bool isSelected;
  final String label;
  final IconData unselectedIcon;
  final IconData selectedIcon;
  final VoidCallback onTap;

  const _RailNavItem({
    required this.isSelected,
    required this.label,
    required this.unselectedIcon,
    required this.selectedIcon,
    required this.onTap,
  });

  @override
  State<_RailNavItem> createState() => _RailNavItemState();
}

class _RailNavItemState extends State<_RailNavItem> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected;
    final highlight = _isFocused || _isHovered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FocusableActionDetector(
        onShowFocusHighlight: (f) => setState(() => _isFocused = f),
        onShowHoverHighlight: (h) => setState(() => _isHovered = h),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onTap(),
          ),
        },
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: const Color(0xFF8b5cf6).withValues(alpha: 0.2),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF8b5cf6).withValues(alpha: 0.25)
                  : (highlight
                      ? const Color(0xFF8b5cf6).withValues(alpha: 0.12)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isFocused
                    ? const Color(0xFFa78bfa)
                    : (active
                        ? const Color(0xFF8b5cf6).withValues(alpha: 0.4)
                        : Colors.transparent),
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? widget.selectedIcon : widget.unselectedIcon,
                  color: active || highlight
                      ? const Color(0xFFa78bfa)
                      : const Color(0xFF6d6488),
                  size: 26,
                ),
                const SizedBox(height: 5),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active || highlight
                        ? const Color(0xFFf3f0fa)
                        : const Color(0xFF6d6488),
                    fontSize: 12,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
