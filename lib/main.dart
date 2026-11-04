import 'dart:async';
import 'dart:io' show Platform, File, FileMode;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
import 'ui/theme.dart';
import 'ui/tokens.dart';
import 'ui/widgets/glass_navigation_bar.dart';
import 'ui/widgets/ambient_backdrop.dart';

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
      final content =
          '[$now] [$source]\nError: $error\nStack trace:\n${stack ?? ''}\n----------------------------------------\n';
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
        final file = File(
          '$home/.local/share/com.mapleprojects.animaple/player.log',
        );
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          '[${DateTime.now().toIso8601String()}][DEBUG] $message\n',
          mode: FileMode.append,
          flush: true,
        );
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
  unawaited(HlsProxy.instance.start());
  unawaited(DownloadService.instance.init());
  unawaited(FsrService.init());
  unawaited(AppPlayer.clearPlaybackCacheGlobal());

  unawaited(() async {
    await SyncService.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SyncService.startAutoSync();
      SyncService.watchConnectivity();
      SyncService.attemptRestoreAndSync();
      NotificationService.init();

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

      Future.delayed(const Duration(milliseconds: 2400), () async {
        final ignored =
            await NotificationService.isBatteryOptimizationIgnored();
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

      Future.delayed(const Duration(milliseconds: 2500), () async {
        final hasUpdate = await UpdateService.checkForUpdate();
        if (!hasUpdate) return;
        final ctx = AniMapleApp.navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        final update = await UpdateService.showUpdateDialog(ctx);
        if (update == true &&
            AniMapleApp.navigatorKey.currentContext?.mounted == true) {
          await UpdateService.downloadAndInstall(
            AniMapleApp.navigatorKey.currentContext!,
          );
        }
      });
    });
  }());

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
      theme: AppTheme.dark,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
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
        final isWideLayout = isTv || screenWidth > 800;

        if (isWideLayout) {
          final railWidth = isTv ? 108.0 : 96.0;
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const AmbientBackdrop(opacity: 0.85),
                Row(
                  children: [
                    Container(
                      width: railWidth,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.surface.withValues(alpha: 0.38),
                            AppColors.bg.withValues(alpha: 0.55),
                          ],
                        ),
                        border: Border(
                          right: BorderSide(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      child: SafeArea(
                        right: false,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildRailItem(
                              0,
                              'Inicio',
                              Icons.home_outlined,
                              Icons.home,
                            ),
                            _buildRailItem(
                              1,
                              'Catálogo',
                              Icons.search_outlined,
                              Icons.search,
                            ),
                            _buildRailItem(
                              2,
                              'Horario',
                              Icons.calendar_today_outlined,
                              Icons.calendar_today,
                            ),
                            _buildRailItem(
                              3,
                              'Historial',
                              Icons.history_outlined,
                              Icons.history,
                            ),
                            _buildRailItem(
                              4,
                              'Mi lista',
                              Icons.favorite_outline,
                              Icons.favorite,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _pages(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            floatingActionButton: isTv ? null : const DownloadsFab(),
          );
        }

        return Scaffold(
          extendBody: true,
          body: IndexedStack(index: _currentIndex, children: _pages()),
          bottomNavigationBar: GlassNavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTabChanged,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Catálogo',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                selectedIcon: Icon(Icons.calendar_today),
                label: 'Horario',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'Historial',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_outline),
                selectedIcon: Icon(Icons.favorite),
                label: 'Mi lista',
              ),
            ],
          ),
          floatingActionButton: const DownloadsFab(),
        );
      },
    );
  }

  /// Páginas del shell. `TickerMode` detiene las animaciones de las pestañas
  /// ocultas: sin esto, los fondos animados siguen produciendo frames.
  List<Widget> _pages() => [
    TickerMode(enabled: _currentIndex == 0, child: const HomePage()),
    TickerMode(enabled: _currentIndex == 1, child: const SearchPage()),
    TickerMode(enabled: _currentIndex == 2, child: const CalendarPage()),
    TickerMode(
      enabled: _currentIndex == 3,
      child: HistoryPage(key: _historyKey),
    ),
    TickerMode(
      enabled: _currentIndex == 4,
      child: FollowingPage(key: _followingKey),
    ),
  ];

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
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
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
          borderRadius: BorderRadius.circular(AppRadius.md),
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: AppColors.primary.withValues(alpha: 0.2),
          highlightColor: Colors.transparent,
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpace.sm + 2,
              horizontal: AppSpace.xs,
            ),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.16)
                  : (highlight
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _isFocused
                    ? AppColors.primaryBright
                    : (active
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : Colors.transparent),
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? widget.selectedIcon : widget.unselectedIcon,
                  color: active || highlight
                      ? AppColors.primaryBright
                      : AppColors.textMuted,
                  size: 25,
                ),
                const SizedBox(height: AppSpace.xs + 1),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active || highlight
                        ? AppColors.textStrong
                        : AppColors.textMuted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
