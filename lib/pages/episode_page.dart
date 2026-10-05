import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/app_player.dart';
import '../services/download_service.dart';
import '../services/hls_proxy.dart';
import '../widgets/download_sheet.dart';
import '../widgets/error_dialog.dart';
import '../widgets/webview_player.dart';
import '../widgets/tv_focusable.dart';
import '../services/tv_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

bool get _isDesktop => !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
class EpisodePage extends StatefulWidget {
  final String animeSlug;
  final int episodeNumber;
  final String animeTitle;

  /// true cuando se abre desde la biblioteca de descargas: la grilla muestra
  /// SOLO los capítulos descargados y Anterior/Siguiente navegan dentro de
  /// ese conjunto (el salto automático respeta el mismo filtro).
  final bool offlineLibrary;

  const EpisodePage({
    super.key,
    required this.animeSlug,
    required this.episodeNumber,
    required this.animeTitle,
    this.offlineLibrary = false,
  });

  @override
  State<EpisodePage> createState() => _EpisodePageState();
}

class _ServerQualityCandidate {
  final ServerMirror server;
  final String videoUrl;
  final String videoType;
  final Map<String, String>? headers;
  final int height;
  final int bandwidth;
  final int responseTimeMs;
  final double measuredMbps;

  _ServerQualityCandidate({
    required this.server,
    required this.videoUrl,
    required this.videoType,
    this.headers,
    required this.height,
    required this.bandwidth,
    required this.responseTimeMs,
    this.measuredMbps = 0.0,
  });
}

enum _PlayerTvFocus {
  none,
  backButton,
  seekBar,
  playPause,
  fullscreen,
  pageContent,
}

class _EpisodePageState extends State<EpisodePage> with TickerProviderStateMixin {
  _PlayerTvFocus _tvFocus = _PlayerTvFocus.none;
  final FocusNode _pageContentFocusNode = FocusNode();
  EpisodeDetail? _episode;
  AnimeDetail? _animeDetail;
  bool _loading = true;

  // ── Modo offline ──
  // Ruta del archivo local si el episodio está descargado. En modo offline no
  // se llama a la API: el detalle del episodio se sintetiza y la reproducción
  // abre el archivo directo (video_view resuelve file:// internamente).
  // addHistory se registra igual para sincronizar al volver la conexión.
  // ignore: unused_field
  String? _offlinePath;

  String? _activeServer;
  String? _currentVideoType;
  String _activeVariant = 'DUB';
  bool _isFullscreen = false;
  bool _autoPlayedNext = false;

  // Video controls
  bool _controlsVisible = true;
  bool _isDragging = false;
  double? _dragValue;
  Timer? _hideTimer;
  AnimationController? _controlsAnim;
  AnimationController? _seekAnim;
  AnimationController? _seekFadeAnim;
  double? _seekDelta;
  bool _seekAnimating = false;

  // Double-tap seek accumulation and continuous remote seek
  int _seekAccumulatorMs = 0;
  DateTime? _lastSeekTapTime;
  int _seekBasePosition = 0;
  static const Duration _seekAccumulationWindow = Duration(milliseconds: 1500);
  Timer? _seekResetTimer;
  Timer? _seekDebounceTimer;
  int? _targetSeekPositionMs;

  // PiP
  static const _pipChannel = MethodChannel('com.mapleprojects.animaple/pip');
  bool _isPipMode = false;

  // Watched episodes indicator
  Set<int> _watchedEpisodes = {};

  // Media notification
  static const _mediaChannel = MethodChannel('com.mapleprojects.animaple/media_session');

  // End-of-episode countdown
  bool _showCountdown = false;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;

  // Position update timer
  Timer? _positionTimer;

  // ── Reconexión + preservación de progreso ──
  int _lastPositionMs = 0;

  // Último source abierto, para reintentar la reconexión indefinidamente.
  String? _lastVideoUrl;
  Map<String, String>? _lastVideoHeaders;

  // true mientras se está reintentando reconectar tras un error de red.
  bool _reconnecting = false;
  Timer? _reconnectTimer;

  // true mientras se precalienta el origin del video (mp4upload lento).
  bool _prewarming = false;

  // ── Overlay de seleccion de servidor (animacion en vivo) ──
  // true mientras el sondeo de servidores corre.
  bool _probing = false;
  // Fila por servidor: nombre -> velocidad medida (Mbps) o ausente si sondea.
  final Map<String, double> _probeSpeeds = {};
  // Servidor elegido tras el sondeo (etiqueta para la animacion final).
  String? _probeChosen;
  // Cold start: evita mostrar el overlay al reabrir sin cambiar de fuente.
  bool _probeOverlayDismissed = false;

  // Posición a restaurar (ms) al volver a playing. -1 = sin pendiente.
  int _pendingSeek = -1;

  // Servidores que fallaron al arrancar en este episodio (para failover
  // automático cuando el servidor activo está caído, p.ej. 522 de Zilla).
  final Set<String> _failedServers = {};

  // true cuando el source actual alcanzó el estado playing alguna vez.
  // Distingue "el servidor nunca arrancó" (failover) de "se cortó a mitad"
  // (reconexión del mismo source preservando progreso).
  bool _sourceStarted = false;


  // Mutable episode number — allows in-place episode switching
  late int _currentEp;

  late final AppPlayer _player;

  @override
  void initState() {
    super.initState();
    if (TvService.isTvMode) {
      _isFullscreen = true;
    }
    _currentEp = widget.episodeNumber;
    _player = AppPlayer.create();
    _controlsAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 250), value: 1.0);
    _seekAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _seekFadeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1.0);
    _player.isPlaying.addListener(_onStateChanged);
    _player.finishedCount.addListener(_onFinished);
    _player.error.addListener(_onError);
    _player.isLoading.addListener(_onLoading);
    _player.positionMs.addListener(_onPositionChanged);
    _player.durationMs.addListener(_onDurationChanged);
    _startPositionTimer();
    _load();
    _initPip();
    _initMediaSession();
  }

  void _initPip() {
    _pipChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipModeChanged':
          final isInPip = call.arguments as bool;
          if (mounted) {
            setState(() {
              _isPipMode = isInPip;
              if (isInPip) {
                _controlsVisible = false;
                _controlsAnim!.value = 0;
                _hideTimer?.cancel();
              }
            });
            if (!isInPip) {
              // Exiting PiP — pause video so audio stops
              _player.pause();
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            }
          }
          break;
        case 'pipTogglePlayPause':
          // User tapped play/pause in PiP controls
          _togglePlayPause();
          break;
        case 'mediaTogglePlayPause':
          // User tapped play/pause in media notification
          _togglePlayPause();
          break;
        case 'mediaStop':
          // User tapped stop in media notification
          _closePlayback();
          break;
        case 'onUserLeaveHint':
          // Native handles auto-PiP entry — nothing to do here
          break;
      }
    });
  }

  void _initMediaSession() {
    _mediaChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'mediaPlay':
          // Comando EXPLÍCITO: no togglear. Si ya está reproduciendo, no hace
          // nada (evita que un reenvío doble del sistema invierta el estado).
          if (!_player.isPlaying.value) _togglePlayPause();
          break;
        case 'mediaPause':
          if (_player.isPlaying.value) _togglePlayPause();
          break;
        case 'mediaSeekTo':
          // Usuario arrastró la barra en la notificación media.
          final ms = (call.arguments as num?)?.toInt() ?? 0;
          _player.seekTo(ms);
          break;
        case 'mediaStop':
          _player.pause();
          _dismissMediaNotification();
          break;
      }
    });
  }

  // ── Controles de teclado y control remoto D-Pad / TV ──

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    if (!isDown && !isRepeat) return KeyEventResult.ignored;
    final key = event.logicalKey;

    final isSeekKey = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaFastForward;

    // Solo permitir repetición continua en las teclas de adelantar y retroceder
    if (isRepeat && !isSeekKey) {
      return KeyEventResult.ignored;
    }

    if (TvService.isTvMode) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
        if (_controlsVisible) {
          _hideTimer?.cancel();
          setState(() {
            _controlsVisible = false;
            _tvFocus = _PlayerTvFocus.none;
          });
          _controlsAnim?.reverse();
          return KeyEventResult.handled;
        } else if (_isFullscreen) {
          _toggleFullscreen();
          return KeyEventResult.handled;
        } else {
          _closePlayback();
          return KeyEventResult.handled;
        }
      }

      if (_tvFocus == _PlayerTvFocus.pageContent) {
        if (key == LogicalKeyboardKey.arrowUp) {
          _showControlsTemporarily();
          setState(() {
            _tvFocus = _PlayerTvFocus.playPause;
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      if (!_controlsVisible) {
        if (key == LogicalKeyboardKey.arrowDown) {
          if (!_isFullscreen) {
            setState(() {
              _tvFocus = _PlayerTvFocus.pageContent;
            });
            _pageContentFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          _showControlsTemporarily();
          setState(() {
            _tvFocus = _PlayerTvFocus.seekBar;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _showControlsTemporarily();
          setState(() {
            _tvFocus = _PlayerTvFocus.seekBar;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
          _seekRelative(-9900);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
          _seekRelative(9900);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.mediaPlayPause) {
          _togglePlayPause();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.mediaPlay) {
          _player.play();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.mediaPause) {
          _player.pause();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      // ── Controles visibles en TV ──
      if (_tvFocus == _PlayerTvFocus.backButton) {
        if (key == LogicalKeyboardKey.arrowDown) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.seekBar;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA) {
          _closePlayback();
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
      } else if (_tvFocus == _PlayerTvFocus.seekBar) {
        if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
          _seekRelative(-9900);
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
          _seekRelative(9900);
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.playPause;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (!_isFullscreen) {
            _startHideTimer();
            setState(() {
              _tvFocus = _PlayerTvFocus.backButton;
            });
            return KeyEventResult.handled;
          }
          _hideTimer?.cancel();
          setState(() {
            _controlsVisible = false;
            _tvFocus = _PlayerTvFocus.none;
          });
          _controlsAnim?.reverse();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.mediaPlayPause) {
          _togglePlayPause();
          _startHideTimer();
          return KeyEventResult.handled;
        }
      } else if (_tvFocus == _PlayerTvFocus.playPause) {
        if (key == LogicalKeyboardKey.arrowRight) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.fullscreen;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.seekBar;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (!_isFullscreen) {
            _hideTimer?.cancel();
            setState(() {
              _controlsVisible = false;
              _tvFocus = _PlayerTvFocus.pageContent;
            });
            _controlsAnim?.reverse();
            _pageContentFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA ||
            key == LogicalKeyboardKey.mediaPlayPause) {
          _togglePlayPause();
          _startHideTimer();
          return KeyEventResult.handled;
        }
      } else if (_tvFocus == _PlayerTvFocus.fullscreen) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.playPause;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.seekBar;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          if (!_isFullscreen) {
            _hideTimer?.cancel();
            setState(() {
              _controlsVisible = false;
              _tvFocus = _PlayerTvFocus.pageContent;
            });
            _controlsAnim?.reverse();
            _pageContentFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          _startHideTimer();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA) {
          _toggleFullscreen();
          _startHideTimer();
          return KeyEventResult.handled;
        }
      } else {
        if (key == LogicalKeyboardKey.arrowDown) {
          _startHideTimer();
          setState(() {
            _tvFocus = _PlayerTvFocus.seekBar;
          });
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _hideTimer?.cancel();
          setState(() {
            _controlsVisible = false;
            _tvFocus = _PlayerTvFocus.none;
          });
          _controlsAnim?.reverse();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_controlsVisible) {
        setState(() => _controlsVisible = false);
        _controlsAnim?.reverse();
        return KeyEventResult.handled;
      } else if (_isFullscreen && _isDesktop) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      _player.play();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      _player.pause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(-9900);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(9900);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (!_controlsVisible) {
        _showControlsTemporarily();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onMouseEnter(PointerEvent event) {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnim!.forward();
    }
    _startHideTimer();
  }

  void _onMouseMove(PointerEvent event) {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnim!.forward();
    }
    _startHideTimer();
  }

  void _onMouseExit(PointerEvent event) {
    if (!_isDragging && !_showCountdown) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
      _controlsAnim?.reverse();
    }
  }

  static Size _lastPipSize = const Size(380, 214);
  Size? _savedWindowSize;
  Offset? _savedWindowPosition;
  bool _pipHovered = false;

  Future<void> _enterPip() async {
    if (_isDesktop) {
      try {
        if (!_isPipMode) {
          // Si la ventana está en pantalla completa o maximizada, restaurarla primero
          if (_isFullscreen || await windowManager.isFullScreen()) {
            await windowManager.setFullScreen(false);
            _isFullscreen = false;
          }
          if (await windowManager.isMaximized()) {
            await windowManager.unmaximize();
          }

          _savedWindowSize = await windowManager.getSize();
          _savedWindowPosition = await windowManager.getPosition();

          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setAspectRatio(16 / 9);
          await windowManager.setMinimumSize(const Size(280, 158));
          await windowManager.setMaximumSize(const Size(800, 450));
          await windowManager.setMaximizable(false);
          await windowManager.setResizable(true);

          final targetSize = (_lastPipSize.width <= 500 && _lastPipSize.height <= 300)
              ? _lastPipSize
              : const Size(380, 214);
          await windowManager.setSize(targetSize);
          await windowManager.setAlignment(Alignment.bottomRight);

          setState(() {
            _isPipMode = true;
            _controlsVisible = false;
          });
        } else {
          await _exitPipDesktop();
        }
      } catch (e) {
        debugPrint('Windows PiP error: $e');
      }
      return;
    }

    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (e) {
      debugPrint('PiP enter error: $e');
    }
  }

  Future<void> _exitPipDesktop() async {
    if (!_isDesktop) return;
    try {
      if (_isPipMode) {
        try {
          final curSize = await windowManager.getSize();
          if (curSize.width >= 280 && curSize.width <= 700) {
            _lastPipSize = curSize;
          }
        } catch (_) {}
      }
      // NUNCA usar Size.infinite (genera overflow a INT_MIN en C++ y bloquea maximizar/redimensionar)
      await windowManager.setMaximumSize(const Size(19200, 10800));
      await windowManager.setMinimumSize(const Size(800, 500));
      await windowManager.setAspectRatio(0);
      await windowManager.setMaximizable(true);
      await windowManager.setResizable(true);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal, windowButtonVisibility: true);

      final targetW = (_savedWindowSize != null && _savedWindowSize!.width >= 900)
          ? _savedWindowSize!.width
          : 1280.0;
      final targetH = (_savedWindowSize != null && _savedWindowSize!.height >= 600)
          ? _savedWindowSize!.height
          : 720.0;
      await windowManager.setSize(Size(targetW, targetH));
      if (_savedWindowPosition != null) {
        await windowManager.setPosition(_savedWindowPosition!);
      } else {
        await windowManager.center();
      }
    } catch (e) {
      debugPrint('Error exiting Desktop PiP: $e');
    }
    if (mounted) {
      setState(() {
        _isPipMode = false;
        _controlsVisible = true;
      });
    }
  }

  void _closePlayback() {
    _player.close();
    _positionTimer?.cancel();
    _syncPipState(false);
    _dismissMediaNotification();
    if (_isDesktop) {
      if (_isFullscreen) {
        windowManager.setFullScreen(false);
        windowManager.setTitleBarStyle(TitleBarStyle.normal, windowButtonVisibility: true);
      }
      if (_isPipMode) {
        _exitPipDesktop();
      }
    }
    if (mounted) Navigator.maybePop(context);
  }

  void _onStateChanged() {
    final playing = _player.isPlaying.value;
    if (playing) {
      _sourceStarted = true;
      // El anime arranco: retirar el overlay de seleccion/conexion.
      if (_probeOverlayDismissed == false) {
        if (mounted) setState(() => _probeOverlayDismissed = true);
      }
      WakelockPlus.enable();
      _startPositionTimer();
      // Auto-hide controls when video starts playing
      _startHideTimer();

      // Restaurar la posición pendiente cuando el video vuelve a estar
      // reproduciéndose (tras reconexión o cambio de servidor/idioma).
      if (_pendingSeek > 0 && _pendingSeek != _player.positionMs.value) {
        final target = _pendingSeek;
        _pendingSeek = -1; // consumir antes del seek (evitar loops)
        _player.seekTo(target);
      } else if (_pendingSeek == 0) {
        _pendingSeek = -1;
      }

      // Si estábamos reconectando y ya estamos reproduciendo… todo
      // correcto; el timer de reconexión se cancela aquí.
      _stopReconnectIfPlaying();
    } else {
      WakelockPlus.disable();
      _positionTimer?.cancel();
    }
    // Sincronizar SIEMPRE el estado real del reproductor con el nativo. Sin
    // esto, con autoplay _userStartedPlayback queda false y el nativo nunca
    // sabe que está reproduciendo → onUserLeaveHint no entra en PiP hasta que
    // el usuario toca play manual una vez.
    _syncPipState(playing);
    // Update media notification with current state
    _updateMediaSession(playing);
    if (mounted) setState(() {});
  }

  /// Cancela el reintento de reconexión si el video ya está reproduciéndose.
  void _stopReconnectIfPlaying() {
    if (_reconnecting && (_player.isPlaying.value || _player.positionMs.value > 0)) {
      _reconnecting = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _videoErrorShown = false; // permitir reportar un error futuro
      if (mounted) setState(() {});
    }
  }

  void _syncPipState(bool playing) {
    if (!Platform.isAndroid) return;
    try {
      _pipChannel.invokeMethod('updatePipState', playing);
    } catch (_) {}
  }

  void _updateMediaSession(bool playing) {
    if (!Platform.isAndroid) return;
    try {
      final duration = _player.durationMs.value;
      final position = _player.positionMs.value;
      final animeDetail = _animeDetail;
      _mediaChannel.invokeMethod('updateMediaSession', {
        'title': widget.animeTitle,
        'episode': _currentEp,
        'playing': playing,
        'position': position,
        'duration': duration,
        'animeId': animeDetail?.id ?? 0,
      });
      // Diagnóstico visible: si el servicio nativo reporta que no pudo
      // publicar la notificación, mostrarlo (no tragar errores en silencio).
      if (playing && mounted) _checkMediaLogOnce();
    } catch (_) {}
  }

  bool _mediaLogChecked = false;

  /// Consulta el log nativo del servicio UN tiempo después del arranque
  /// (el intent se procesa asíncrono; consultar al instante lee el estado
  /// anterior). Si el servicio reporta fallo, lo muestra en pantalla.
  Future<void> _checkMediaLogOnce() async {
    if (_mediaLogChecked) return;
    _mediaLogChecked = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    try {
      final log = await _mediaChannel
          .invokeMethod<String>('getMediaNotificationLog');
      if (mounted && log != null) {
        if (log.contains('FAIL')) {
          _videoErrorShown = true;
          showErrorSheet(context, log, null, title: 'Notificación de reproducción');
        }
      }
    } catch (_) {}
  }

  void _dismissMediaNotification() {
    if (!Platform.isAndroid) return;
    try {
      _mediaChannel.invokeMethod('dismissMediaNotification');
    } catch (_) {}
  }

  void _onFinished() {
    final pos = _player.positionMs.value;
    final dur = _player.durationMs.value;
    // Don't treat seek stalls, buffer underruns, or premature network EOF as completion
    if (dur > 20000 && pos > 0 && pos < (dur - 15000)) {
      debugPrint('EpisodePage: Ignored premature onFinished at $pos ms / $dur ms');
      _player.play();
      return;
    }
    if (_player.finishedCount.value > 0 && mounted && !_autoPlayedNext) {
      _autoPlayedNext = true;
      final has = _animeDetail != null && _currentEp < _animeDetail!.episodes.length;
      if (has) {
        _startCountdown();
      }
    }
  }

  void _startCountdown() {
    setState(() { _showCountdown = true; _countdownSeconds = 5; });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdownSeconds--);
      if (_countdownSeconds <= 0) {
        t.cancel();
        setState(() => _showCountdown = false);
        _goNext();
      }
    });
  }

  void _skipCountdown() {
    _countdownTimer?.cancel();
    setState(() => _showCountdown = false);
    _goNext();
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() => _showCountdown = false);
  }

  bool _videoErrorShown = false;

  void _onError() {
    final err = _player.error.value;
    if (err != null && err.isNotEmpty) {
      debugPrint('VIDEO ERROR: $err');
      // Si el reproductor está activamente reproduciendo, ignorar fallos secundarios de decoder/logs
      if (_player.isPlaying.value) {
        debugPrint('Ignoring non-fatal error while actively playing: $err');
        return;
      }
      final hadSource = _lastVideoUrl != null && _lastVideoUrl!.isNotEmpty;

      // El source NUNCA llegó a reproducirse: el servidor activo está caído
      // (p.ej. Zilla devolviendo 522) — conmutar automáticamente al siguiente
      // espejo disponible de la misma variante en vez de reconectar contra un
      // servidor muerto.
      if (hadSource && !_sourceStarted && !_reconnecting) {
        if (_failoverToNextServer()) return;
      }

      // Pérdida de conexión durante la reproducción → reconexión automática
      // indefinida (cada 8s) hasta que el video vuelva, restaurando el
      // progreso visto. Solo si el source ya reproducía antes del corte.
      if (hadSource && _sourceStarted && !_reconnecting) {
        _startReconnect();
        return;
      }

      // Error sin source previo (o sin más espejos): mostrarlo una sola vez.
      if (mounted && !_videoErrorShown) {
        _videoErrorShown = true;
        showErrorSheet(
          context,
          Exception('Error del reproductor de video: $err'),
          null,
          title: 'Error de reproducción',
        );
      }
    }
  }

  /// Salta al siguiente servidor de la variante activa en orden automático,
  /// marcando el actual como fallido. Al no quedar más espejos devuelve false
  /// para que el error se muestre al usuario.
  bool _failoverToNextServer() {
    if (_activeServer != null) _failedServers.add(_activeServer!);
    final ep = _episode;
    if (ep == null) return false;

    final remaining = ep.embeds
        .where((s) =>
            s.variant == _activeVariant &&
            !_failedServers.contains(s.server) &&
            _isPlayableServer(s))
        .toList();
    if (remaining.isEmpty) return false;

    debugPrint('FAILOVER: $_activeServer falló, re-evaluando servidores restantes');
    _lastPositionMs = 0;
    _pendingSeek = -1;
    _lastVideoUrl = null;
    _lastVideoHeaders = null;
    _sourceStarted = false;
    _videoErrorShown = false;
    unawaited(_autoPlayResolved(ep));
    return true;
  }

  /// Reintenta abrir el último source cada segundo, indefinidamente, hasta
  /// que la conexión vuelva y el video se reproduzca de nuevo. Al lograrlo,
  /// [isPlaying] cambia a playing y [seekTo] restaura la posición.
  void _startReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    _videoErrorShown = false;
    // Guardar el progreso justo antes de caer, por si el timer no lo capturó.
    final pos = _player.positionMs.value;
    if (pos > 0) _lastPositionMs = pos;
    if (mounted) setState(() {});

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _player.isDisposed) {
        _reconnectTimer?.cancel();
        return;
      }
      // Si el player ya volvió a reproducir, no reintentar más.
      if (_player.isPlaying.value) {
        _stopReconnectIfPlaying();
        return;
      }
      final url = _lastVideoUrl;
      if (url == null || url.isEmpty) {
        _reconnectTimer?.cancel();
        _reconnecting = false;
        return;
      }
      debugPrint('Reconnect intent: $url (resume ${_lastPositionMs}ms)');
      try {
        _pendingSeek = _lastPositionMs; // restaurar al volver a playing
        _player.open(url, headers: _lastVideoHeaders, startPositionMs: _pendingSeek > 0 ? _pendingSeek : null);
        _player.play();
      } catch (e) {
        debugPrint('Reconnect open error: $e');
      }
    });
  }

  /// Cancela la reconexión (se llama cuando el video ya se reprodució).
  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    _videoErrorShown = false;
    if (mounted) setState(() {});
  }

  /// Prueba un servidor individual de forma asíncrona, midiendo su latencia
  /// y evaluando la resolución máxima disponible (ej: 1080p en HLS).
  Future<_ServerQualityCandidate?> _probeServer(ServerMirror s) async {
    final sw = Stopwatch()..start();
    try {
      if (s.server.toLowerCase().contains('byse') && !ApiService.isByseCached(s.url)) {
        return null;
      }
      final data = await ApiService.fetchVideoUrl(s.url)
          .timeout(const Duration(seconds: 12));
      final videoUrl = data['url'] as String?;
      final videoType = data['type'] as String? ?? 'mp4';
      if (videoUrl == null || videoUrl.isEmpty || videoType == 'embed') {
        return null;
      }

      final customHeaders = (data['headers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString()));
      final headers = customHeaders ??
          (videoType == 'hls'
              ? <String, String>{'Referer': 'https://player.zilla-networks.com/'}
              : videoType == 'mp4'
                  ? <String, String>{'Referer': 'https://www.mp4upload.com/'}
                  : null);

      var effectiveUrl = videoUrl;
      int height = 720;
      int bandwidth = 0;

      if (videoType == 'hls') {
        final q = await ApiService.resolveHighestQualityHls(videoUrl, headers: headers);
        effectiveUrl = q['url'] as String? ?? videoUrl;
        height = q['height'] as int? ?? 720;
        bandwidth = q['bandwidth'] as int? ?? 0;
      } else if (videoType == 'mp4') {
        final lower = '$videoUrl ${s.server}'.toLowerCase();
        final match = RegExp(r'(\d{3,4})p?').firstMatch(lower);
        if (match != null) {
          final parsed = int.tryParse(match.group(1)!) ?? 0;
          if (parsed >= 240 && parsed <= 4320) {
            height = parsed;
          }
        }
      }

      // Velocidad REAL del stream (no solo latencia del resolver): elegir
      // el servidor que de verdad entrega datos, no el que responde rapido
      // pero streamea lento.
      double measuredMbps = 0.0;
      if (videoType == 'mp4' || videoType == 'hls') {
        measuredMbps = await ApiService.measureStreamMbps(
          effectiveUrl,
          headers: headers,
          timeout: const Duration(seconds: 8),
        );
      }
      sw.stop();
      return _ServerQualityCandidate(
        server: s,
        videoUrl: effectiveUrl,
        videoType: videoType,
        headers: headers,
        height: height,
        bandwidth: bandwidth,
        responseTimeMs: sw.elapsedMilliseconds,
        measuredMbps: measuredMbps,
      );
    } catch (_) {
      return null;
    }
  }

  /// Servidores que la app puede reproducir nativamente.
  bool _isPlayableServer(ServerMirror s) {
    final name = s.server.toLowerCase();
    final url = s.url.toLowerCase();
    if (name.contains('hls')) return true;
    if (name.contains('mp4upload')) return true;
    if (name.contains('upnshare') || url.contains('uns.bio')) return true;
    if (name.contains('voe') || url.contains('voe.sx')) return true;
    if (name.contains('byse') || url.contains('byselapuix.com') || url.contains('n1mwq.org')) return true;
    if (url.contains('.m3u8') || url.contains('zilla-networks')) return true;
    if (url.contains('.mp4') || url.contains('mp4upload.com')) return true;
    return false;
  }

  /// Determina el orden de servidores a probar para [variant].
  Future<List<ServerMirror>> _orderedServers(EpisodeDetail ep, String variant) async {
    final filtered = ep.embeds
        .where((s) =>
            s.variant == variant &&
            !_failedServers.contains(s.server) &&
            _isPlayableServer(s))
        .toList();
    final upn = filtered.where((s) => s.server.toLowerCase().contains('upnshare') || s.url.toLowerCase().contains('uns.bio')).toList();
    final hls = filtered.where((s) => s.server.toLowerCase().contains('hls')).toList();
    final voe = filtered.where((s) => s.server.toLowerCase().contains('voe') || s.url.toLowerCase().contains('voe.sx')).toList();
    final mp4 = filtered.where((s) => s.server.toLowerCase().contains('mp4upload')).toList();
    final byse = filtered.where((s) => s.server.toLowerCase().contains('byse') || s.url.toLowerCase().contains('byselapuix.com')).toList();
    final others = filtered
        .where((s) => !hls.contains(s) && !upn.contains(s) && !voe.contains(s) && !mp4.contains(s) && !byse.contains(s))
        .toList();
    final ordered = <ServerMirror>[];
    ordered.addAll(upn);
    ordered.addAll(hls);
    ordered.addAll(voe);
    ordered.addAll(mp4);
    ordered.addAll(byse);
    for (final s in others) {
      if (!ordered.contains(s)) ordered.add(s);
    }
    // Dedupe final por identidad.
    final seen = <String>{};
    return ordered.where((s) => seen.add('${s.server}:${s.url}')).toList();
  }

  void _onLoading() {
    if (mounted) setState(() {});
  }

  void _onPositionChanged() {
    if (_reconnecting && (_player.isPlaying.value || _player.positionMs.value > 0)) {
      _stopReconnectIfPlaying();
    }
    if (_pendingSeek > 0 && _player.positionMs.value > 0) {
      final target = _pendingSeek;
      _pendingSeek = -1;
      _player.seekTo(target);
    }
    if (mounted) setState(() {});
  }

  void _onDurationChanged() {
    if (_pendingSeek > 0 && _player.durationMs.value > 0) {
      final target = _pendingSeek;
      _pendingSeek = -1;
      _player.seekTo(target);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _positionTimer?.cancel();
    _seekResetTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _pageContentFocusNode.dispose();
    _controlsAnim?.dispose();
    _seekAnim?.dispose();
    _seekFadeAnim?.dispose();
    _player.isPlaying.removeListener(_onStateChanged);
    _player.finishedCount.removeListener(_onFinished);
    _player.error.removeListener(_onError);
    _player.isLoading.removeListener(_onLoading);
    _player.positionMs.removeListener(_onPositionChanged);
    _player.durationMs.removeListener(_onDurationChanged);
    _player.dispose();
    if (_isDesktop) {
      if (_isFullscreen) {
        windowManager.setFullScreen(false);
        windowManager.setTitleBarStyle(TitleBarStyle.normal, windowButtonVisibility: true);
      }
      if (_isPipMode) {
        _exitPipDesktop();
      }
    }
    _syncPipState(false);
    _dismissMediaNotification();
    if (_isFullscreen && !_isDesktop) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _load() async {
    // ── 0. Detalle offline del anime (sin API): reconstruido de meta.json.
    // Da sinopsis, etiquetas y grilla de capítulos en modo sin conexión.
    if (_animeDetail == null) {
      try {
        final local = await DownloadService.instance.animeDetailFor(widget.animeSlug);
        if (local != null) _animeDetail = local;
      } catch (_) {}
    }

    // ── 1. Offline-first: ¿existe descarga local de este episodio? ──
    final localPath = await DownloadService.instance
        .videoPath(widget.animeSlug, _currentEp);
    if (localPath != null) {
      if (!mounted) return;
      setState(() {
        _offlinePath = localPath;
        _episode = EpisodeDetail(
          id: 0,
          mediaId: (_animeDetail?.id ?? 0),
          number: _currentEp,
          variants: const ['DUB'],
          filler: false,
          embeds: const [],
          downloads: const [],
        );
        _loading = false;
        _autoPlayedNext = false;
      });
      ApiService.addHistory(
        _animeDetail?.id ?? 0,
        widget.animeSlug,
        widget.animeTitle,
        _currentEp,
      );
      try {
        final history = await ApiService.fetchHistory();
        _watchedEpisodes = history
            .where((h) => h.animeSlug == widget.animeSlug)
            .map((h) => h.episodeNumber)
            .toSet();
        _watchedEpisodes.add(_currentEp);
      } catch (_) {}
      // Ruta absoluta sin esquema: video_view la convierte a file:// en
      // Android (open: `!source.contains("://")` → "file://$source") y usa
      // media_kit/libmpv directamente en desktop.
      unawaited(_player.open(localPath));
      return;
    }

    // ── 2. Streaming normal (online) ──
    const maxRetries = 15;
    for (var attempt = 0; attempt < maxRetries && mounted; attempt++) {
      try {
        final ep = await ApiService.fetchEpisodeDetail(widget.animeSlug, _currentEp);
        // Only fetch anime detail on first load (not on episode switch)
        AnimeDetail? detail = _animeDetail;
        if (detail == null) {
          try { detail = await ApiService.fetchAnimeDetail(widget.animeSlug); } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _episode = ep;
            _animeDetail = detail;
            _loading = false;
            _autoPlayedNext = false;
            _activeVariant = ep.variants.contains('DUB') ? 'DUB' : (ep.variants.isNotEmpty ? ep.variants.first : 'DUB');
          });
        }
        // Register in history
        ApiService.addHistory(
          detail?.id ?? 0,
          widget.animeSlug,
          detail?.title ?? widget.animeTitle,
          ep.number,
        );
        // Load watched episodes for indicator
        try {
          final history = await ApiService.fetchHistory();
          _watchedEpisodes = history
              .where((h) => h.animeSlug == widget.animeSlug)
              .map((h) => h.episodeNumber)
              .toSet();
          _watchedEpisodes.add(ep.number); // Current episode is also "watched"
        } catch (_) {}
        _autoPlay();
        return;
      } catch (e, st) {
        debugPrint('EPISODE LOAD RETRY: $e');
        // Offline esperado al cargar el episodio: sin hoja de error, reintenta
        // solo. Solo errores reales (no de red) muestran el reporte.
        if (attempt == 0 &&
            mounted &&
            !isConnectivityError(e)) {
          showErrorSheet(context, e, st, slug: widget.animeSlug);
        }
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    // All retries failed — show error state
    if (mounted) setState(() { _loading = false; });
  }

  void _autoPlay() {
    final ep = _episode;
    if (ep == null) return;
    _failedServers.clear();
    unawaited(_autoPlayResolved(ep));
  }

  Future<void> _autoPlayResolved(EpisodeDetail ep) async {
    // Probar todos los servidores candidatos simultáneamente en cada capítulo para
    // elegir el que responda más rápido con la mejor calidad disponible.
    final candidates = ep.embeds
        .where((s) =>
            s.variant == _activeVariant &&
            !_failedServers.contains(s.server) &&
            _isPlayableServer(s))
        .toList();
    if (candidates.isEmpty) return;

    // Overlay en vivo: mostrar la animacion de sondeo y colorear cada
    // servidor conforme termina de medirse.
    if (mounted) {
      setState(() {
        _probing = true;
        _probeSpeeds.clear();
        _probeChosen = null;
        _probeOverlayDismissed = false;
        for (final s in candidates) {
          _probeSpeeds[s.server] = double.nan; // sondeando
        }
      });
    }

    final results = await Future.wait(candidates.map((s) async {
      final r = await _probeServer(s);
      if (mounted) {
        setState(() {
          _probeSpeeds[s.server] = r?.measuredMbps ?? 0.0;
        });
      }
      return r;
    }));
    final valid = results.whereType<_ServerQualityCandidate>().toList();

    if (valid.isNotEmpty) {
      // Priorizar siempre la mayor resolución disponible (1080p > 720p > 480p > 360p).
      // Con la caché en disco y precarga continua, conexiones limitadas reproducen fluidamente 1080p.
      valid.sort((a, b) {
        // Servidor con fallo absoluto o latencia inmanejable queda al final
        final aliveA = (a.measuredMbps > 0.0 && a.responseTimeMs < 10000) ? 1 : 0;
        final aliveB = (b.measuredMbps > 0.0 && b.responseTimeMs < 10000) ? 1 : 0;
        if (aliveA != aliveB) return aliveB.compareTo(aliveA);

        // Umbral de viabilidad para reproducción fluida sin cortes/buffering:
        // 1080p requiere al menos 3.0 Mbps estables
        // 720p requiere al menos 1.8 Mbps estables
        // <= 480p requiere al menos 0.8 Mbps
        double minBw(int h) {
          if (h >= 1080) return 3.0;
          if (h >= 720) return 1.8;
          return 0.8;
        }

        final viableA = a.measuredMbps >= minBw(a.height) ? 1 : 0;
        final viableB = b.measuredMbps >= minBw(b.height) ? 1 : 0;

        // Si uno es viable para su resolución y el otro no entrega suficiente ancho de banda,
        // priorizar el servidor viable para evitar congelamiento de reproducción.
        if (viableA != viableB) return viableB.compareTo(viableA);

        // A igualdad de viabilidad:
        // 1. Si ambos son viables y tienen diferente resolución, mayor resolución primero
        if (viableA == 1 && a.height != b.height) {
          return b.height.compareTo(a.height);
        }

        // 2. Si hay una diferencia significativa de velocidad real (>= 1.5 Mbps),
        // preferir el que entregue notablemente mayor ancho de banda
        final speedDiff = b.measuredMbps - a.measuredMbps;
        if (speedDiff.abs() >= 1.5) {
          return b.measuredMbps.compareTo(a.measuredMbps);
        }

        // 3. Resolución disponible
        if (a.height != b.height) {
          return b.height.compareTo(a.height);
        }

        // 4. Ancho de banda medido
        if (a.measuredMbps != b.measuredMbps) {
          return b.measuredMbps.compareTo(a.measuredMbps);
        }

        // 5. Menor latencia de respuesta
        return a.responseTimeMs.compareTo(b.responseTimeMs);
      });

      final best = valid.first;
      debugPrint('BEST SERVER PROBED: ${best.server.server} (${best.height}p, ${best.bandwidth}bps, ${best.responseTimeMs}ms, ${best.measuredMbps.toStringAsFixed(2)}Mbps)');
      if (mounted) {
        setState(() {
          _probeChosen = best.server.server;
          _probing = false;
        });
      }
      // El overlay NO desaparece aqui: permanece mostrando "conectando"
      // hasta que _onStateChanged detecte que el video realmente reprodujo.
      await _playCandidateDirect(best);
      return;
    }

    // Fallback a lista secuencial si las pruebas no respondieron
    if (mounted) {
      setState(() {
        _probing = false;
      });
    }
    final ordered = await _orderedServers(ep, _activeVariant);
    if (ordered.isNotEmpty) {
      await _playServer(ordered.first);
    }
  }

  Future<void> _playCandidateDirect(_ServerQualityCandidate candidate) async {
    if (mounted) {
      setState(() {
        _activeServer = candidate.server.server;
        _currentVideoType = candidate.videoType;
        _autoPlayedNext = false;
      });
    }
    _videoErrorShown = false;
    _sourceStarted = false;

    try {
      final videoUrl = candidate.videoUrl;
      final videoType = candidate.videoType;
      final headers = candidate.headers;

      debugPrint('PLAYING DIRECT: $videoUrl (type=$videoType, height=${candidate.height}p, bw=${candidate.bandwidth})');

      if (_lastPositionMs > 0) {
        _pendingSeek = _lastPositionMs;
      } else {
        _pendingSeek = 0;
      }

      _lastVideoUrl = videoUrl;
      _lastVideoHeaders = headers;

      _stopReconnect();

      if (videoType == 'mp4') {
        if (mounted) setState(() => _prewarming = true);
        try {
          await ApiService.prewarmVideo(videoUrl, headers: headers)
              .timeout(const Duration(seconds: 32), onTimeout: () => false);
        } finally {
          if (mounted) setState(() => _prewarming = false);
        }
      }

      var streamUrl = videoUrl;
      if (HlsProxy.instance.isRunning && !videoUrl.startsWith('http://127.0.0.1')) {
        if (videoType == 'hls') {
          streamUrl = HlsProxy.instance.proxyM3U8(videoUrl, referer: headers?['Referer']);
        } else if (videoType == 'mp4') {
          streamUrl = HlsProxy.instance.proxyVideo(videoUrl, referer: headers?['Referer']);
        }
      }

      await _player.open(streamUrl, headers: headers, startPositionMs: _pendingSeek > 0 ? _pendingSeek : null);
    } catch (e, st) {
      debugPrint('PLAY CANDIDATE ERROR: $e');
      if (mounted) showErrorSheet(context, e, st, title: 'Error de reproducción');
    }
  }

  Future<void> _playServer(ServerMirror server) async {
    if (mounted) {
      setState(() {
        _activeServer = server.server;
        _probeChosen = server.server;
        _probeOverlayDismissed = false;
        _autoPlayedNext = false;
      });
    }
    _videoErrorShown = false; // permitir mostrar un nuevo error
    _sourceStarted = false;   // nuevo source: aún no ha reproducido

    while (mounted) {
      try {
        debugPrint('PLAY SERVER: ${server.server} → ${server.url}');
        final data = await ApiService.fetchVideoUrl(server.url);
        final videoUrl = data['url'] as String?;
        final videoType = data['type'] as String? ?? 'mp4';

        if (videoUrl == null || videoUrl.isEmpty) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        debugPrint('PLAYING: $videoUrl (type=$videoType)');
        if (videoType == 'embed') {
          _player.pause();
          _stopReconnect();
          if (mounted) {
            setState(() {
              _currentVideoType = 'embed';
              _lastVideoUrl = videoUrl;
              _sourceStarted = true;
              _probing = false;
              _probeOverlayDismissed = true;
            });
          }
          return;
        }

        if (mounted) {
          setState(() {
            _currentVideoType = videoType;
          });
        }
        final customHeaders = (data['headers'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v.toString()));

        final headers = customHeaders ??
            (videoType == 'hls'
                ? <String, String>{
                    'Referer': 'https://player.zilla-networks.com/',
                  }
                : videoType == 'mp4'
                    ? <String, String>{'Referer': 'https://www.mp4upload.com/'}
                    : null);

        var effectiveUrl = videoUrl;
        if (videoType == 'hls') {
          final q = await ApiService.resolveHighestQualityHls(videoUrl, headers: headers);
          effectiveUrl = q['url'] as String? ?? videoUrl;
        }

        if (_lastPositionMs > 0) {
          _pendingSeek = _lastPositionMs;
        } else {
          _pendingSeek = 0;
        }

        _lastVideoUrl = effectiveUrl;
        _lastVideoHeaders = headers;

        _stopReconnect();

        if (videoType == 'mp4') {
          if (mounted) setState(() => _prewarming = true);
          try {
            await ApiService.prewarmVideo(videoUrl, headers: headers)
                .timeout(const Duration(seconds: 32),
                    onTimeout: () => false);
          } finally {
            if (mounted) setState(() => _prewarming = false);
          }
        }

        var streamUrl = effectiveUrl;
        if (HlsProxy.instance.isRunning && !effectiveUrl.startsWith('http://127.0.0.1')) {
          if (videoType == 'hls') {
            streamUrl = HlsProxy.instance.proxyM3U8(effectiveUrl, referer: headers?['Referer']);
          } else if (videoType == 'mp4') {
            streamUrl = HlsProxy.instance.proxyVideo(effectiveUrl, referer: headers?['Referer']);
          }
        }

        await _player.open(streamUrl, headers: headers, startPositionMs: _pendingSeek > 0 ? _pendingSeek : null);
        return;
      } catch (e, st) {
        debugPrint('PLAY RETRY: $e');
        if (mounted) showErrorSheet(context, e, st, title: 'Error de reproducción');
        return;
      }
    }
  }

  // In-place episode switch — no Navigator, no widget rebuild, fullscreen persists
  void _switchEpisode(int newEp) async {
    final detail = _animeDetail;
    if (detail == null) return;
    if (widget.offlineLibrary &&
        !DownloadService.instance.isDownloaded(widget.animeSlug, newEp)) {
      return; // Modo biblioteca: navegar solo entre capítulos descargados.
    }
    // Soporta animes con episodio 0 (ovas/prólogos/especiales) o numeración no continua
    if (!detail.episodes.any((e) => e.number == newEp)) return;
    if (newEp == _currentEp) return;

    try {
      await _player.pause();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentEp = newEp;
        _loading = true;
        // Reset del estado offline: el nuevo capítulo se resuelve en _load().
        _offlinePath = null;
        _showCountdown = false;
        _autoPlayedNext = false;
        _probeChosen = null;
        _probing = false;
        _probeOverlayDismissed = false;
        _sourceStarted = false;
        _currentVideoType = null;
      });
    }
    // Cancelar reconexión y reiniciar la posición: es otro capítulo, no
    // debe heredar el progreso del anterior.
    _countdownTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnecting = false;
    _pendingSeek = 0;
    _lastPositionMs = 0;
    _lastVideoUrl = null;
    _lastVideoHeaders = null;
    _failedServers.clear();
    _probeSpeeds.clear();
    await _player.close();
    if (mounted) {
      _load();
    }
  }

  void _goNext() => _switchEpisode(_currentEp + 1);
  void _goPrev() => _switchEpisode(_currentEp - 1);

  void _toggleFullscreen() async {
    if (_isDesktop && _isPipMode) {
      await _exitPipDesktop();
    }
    final nextFullscreen = !_isFullscreen;
    if (_isDesktop) {
      try {
        if (nextFullscreen) {
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
          await windowManager.setFullScreen(true);
        } else {
          await windowManager.setFullScreen(false);
          await windowManager.setTitleBarStyle(TitleBarStyle.normal, windowButtonVisibility: true);
        }
      } catch (e) {
        debugPrint('Windows fullscreen error: $e');
      }
    } else {
      if (nextFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    if (mounted) {
      setState(() => _isFullscreen = nextFullscreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _episode == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0a0812),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6))),
      );
    }
    final ep = _episode;
    if (ep == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Error cargando episodio')));
    }

    final filteredEmbeds = ep.embeds.where((s) =>
      s.variant == _activeVariant && _isPlayableServer(s)
    ).toList();
    final anime = _animeDetail;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFF0a0812),
      appBar: (_isFullscreen || _isPipMode) ? null : AppBar(
        backgroundColor: const Color(0xFF0a0812),
        leading: Container(
          margin: const EdgeInsets.all(6),
          decoration: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.backButton)
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFa78bfa), width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8b5cf6).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                )
              : null,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _closePlayback,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.animeTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFe8e4f0))),
            Text('Episodio ${ep.number}', style: const TextStyle(fontSize: 12, color: Color(0xFF6d6488))),
          ],
        ),

      ),
      body: _isPipMode
        ? _buildVideoPlayer()
        : _isFullscreen
          ? SizedBox.expand(child: _buildVideoPlayer())
          : isWide
            ? _buildWideLayout(ep, filteredEmbeds, anime)
            : _buildNarrowLayout(ep, filteredEmbeds, anime),
    );

    final wrapped = PopScope(
      canPop: !_controlsVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _controlsVisible) {
          setState(() => _controlsVisible = false);
          _controlsAnim?.reverse();
          return;
        }
        if (didPop) {
          _player.close();
          _syncPipState(false);
          _dismissMediaNotification();
          if (_isDesktop && _isFullscreen) {
            windowManager.setFullScreen(false);
            windowManager.setTitleBarStyle(TitleBarStyle.normal, windowButtonVisibility: true);
          }
        }
      },
      child: scaffold,
    );

    return Focus(autofocus: true, onKeyEvent: _handleKeyEvent, child: wrapped);
  }

  Widget _buildWideLayout(EpisodeDetail ep, List<ServerMirror> filteredEmbeds, AnimeDetail? anime) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPlayer()),
              _buildNavButtons(ep),
              _buildVariantAndServers(ep, filteredEmbeds),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildInfoSection(ep, anime),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(EpisodeDetail ep, List<ServerMirror> filteredEmbeds, AnimeDetail? anime) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPlayer()),
          _buildNavButtons(ep),
          _buildVariantAndServers(ep, filteredEmbeds),
          Padding(padding: const EdgeInsets.all(16), child: _buildInfoSection(ep, anime)),
        ],
      ),
    );
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _controlsAnim!.forward();
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
      _controlsAnim!.reverse();
    }
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    var lastMediaSync = DateTime.now();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      // Cargar el progreso visto para restaurarlo (reconexión / cambio de
      // servidor / cambio de idioma). Solo se guarda en reproducción.
      if (_player.isPlaying.value) {
        _lastPositionMs = _player.positionMs.value;
      }
      // Sincronizar la notificación media (barra de progreso) ~1 vez por
      // segundo mientras se reproduce, para que la timeline avance.
      final now = DateTime.now();
      if (now.difference(lastMediaSync).inMilliseconds >= 1000) {
        lastMediaSync = now;
        _updateMediaSession(_player.isPlaying.value);
      }
      // Clear _dragValue when player position catches up after seek
      if (_dragValue != null && !_isDragging) {
        final pos = _player.positionMs.value;
        if ((pos - _dragValue!).abs() < 1500) {
          _dragValue = null;
        }
      }
      setState(() {});
    });
  }

  void _showControlsTemporarily() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnim!.forward();
    }
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: TvService.isTvMode ? 4 : 3), () {
      if (mounted && !_isDragging && !_showCountdown && _player.isPlaying.value) {
        setState(() {
          _controlsVisible = false;
          _tvFocus = _PlayerTvFocus.none;
        });
        _controlsAnim?.reverse();
      }
    });
  }

  void _togglePlayPause() {
    final ps = _player.isPlaying.value;
    if (ps) {
      _player.pause();
      if (!_isPipMode) {
        setState(() => _controlsVisible = true);
        _controlsAnim!.forward();
      }
      _hideTimer?.cancel();
    } else {
      _player.play();
      if (!_isPipMode) _startHideTimer();
    }
  }

  void _seekRelative(int deltaMs) {
    final now = DateTime.now();
    final dur = _player.durationMs.value;

    // Accumulate seeks within the time window
    if (_lastSeekTapTime != null && now.difference(_lastSeekTapTime!) < _seekAccumulationWindow) {
      _seekAccumulatorMs += deltaMs;
    } else {
      // New sequence — reset accumulator
      _seekBasePosition = _player.positionMs.value;
      _seekAccumulatorMs = deltaMs;
    }
    _lastSeekTapTime = now;

    final target = (_seekBasePosition + _seekAccumulatorMs).clamp(0, dur);
    _targetSeekPositionMs = target;
    _dragValue = target.toDouble();

    _seekDelta = _seekAccumulatorMs.toDouble();
    _seekAnimating = true;
    setState(() {});

    // Restart fade animation on each tap
    _seekFadeAnim!.forward(from: 0);

    // Debounce del seek real en el reproductor para no saturar la red al mantener presionado
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      final finalTarget = _targetSeekPositionMs;
      _targetSeekPositionMs = null;
      if (finalTarget != null) {
        _player.seekTo(finalTarget);
      }
    });

    // Cancel previous reset timer, start new one
    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _seekFadeAnim!.reverse().then((_) {
        if (mounted) {
          setState(() {
            _seekAnimating = false;
            _seekDelta = null;
            _dragValue = null;
          });
        }
      });
    });

    _showControlsTemporarily();
  }

  // ── Video player with overlay controls ──

  /// Overlay elegante de seleccion de servidor: animacion de sondeo con
  /// barras por servidor que muestran la velocidad medida en vivo, y al
  /// terminar una tarjeta de confirmacion con el servidor elegido y calidad.
  Widget _buildProbeOverlay() {
    final chosen = _probeChosen;
    final anyStarted = _probeSpeeds.isNotEmpty;
    final isTv = TvService.isTvMode;

    final content = Container(
      color: const Color(0xFF07050d).withValues(alpha: isTv ? 0.95 : 0.65),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
        child: chosen != null
            ? _ProbeChosenCard(
                key: ValueKey('chosen_$chosen'),
                server: chosen,
                prewarming: _prewarming,
              )
            : _ProbeScanPanel(
                key: const ValueKey('scan'),
                speeds: _probeSpeeds,
                started: anyStarted,
              ),
      ),
    );

    return ClipRect(
      child: isTv
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: content,
            ),
    );
  }

  Widget _buildVideoPlayer() {
    final isPlaying = _player.isPlaying.value;
    final isEmbed = _currentVideoType == 'embed';
    final playerWidget = Stack(
      alignment: Alignment.center,
      children: [
        // Video surface
        if (isEmbed && _lastVideoUrl != null)
          WebviewPlayer(url: _lastVideoUrl!, referer: 'https://animeav1.com/')
        else
          _player.buildView(fit: _isPipMode ? BoxFit.cover : BoxFit.contain),

        // Overlay de seleccion de servidor (sondeo en vivo + confirmacion)
        if (!_probeOverlayDismissed && (_probing || _probeChosen != null || !_sourceStarted || _prewarming || _loading))
          _buildProbeOverlay(),

        // ── Everything below is hidden in PiP mode or in web embed player mode ──
        if (!_isPipMode && !isEmbed) ...[

        // Rueda de carga del reproductor: solo en reconexiones tras haber iniciado el capitulo
        if (_sourceStarted && _reconnecting && !isPlaying)
          const CircularProgressIndicator(color: Color(0xFFd8b4fe), strokeWidth: 2.5),

        // Reconexión automática (pérdida de internet): aviso al usuario con diseño elegante
        if (_reconnecting && !isPlaying)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF161324), Color(0xFF241b38)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF7c3aed).withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8b5cf6).withValues(alpha: 0.3),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF8b5cf6), strokeWidth: 2.5),
                SizedBox(height: 14),
                Text(
                  'Reconectando…',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  'Conexión perdida, restaurando reproducción',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

        // Big center play/pause (when paused)
        if (!isPlaying && !_player.isLoading.value && _sourceStarted)
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
            ),
          ),

        // Double-tap seek indicator — right side for forward, left for rewind
        if (_seekAnimating && _seekDelta != null)
          Positioned(
            top: 0,
            bottom: 0,
            right: _seekDelta! > 0 ? 24 : null,
            left: _seekDelta! < 0 ? 24 : null,
            child: FadeTransition(
              opacity: _seekFadeAnim!,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _seekDelta! < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                        color: Colors.white, size: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_seekDelta! > 0 ? '+' : ''}${_formatSeekDelta(_seekDelta!)}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // End-of-episode countdown overlay
        if (_showCountdown)
          Container(
            color: Colors.black.withValues(alpha: 0.85),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Siguiente episodio en',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  // Countdown circle
                  SizedBox(
                    width: 80, height: 80,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80, height: 80,
                          child: CircularProgressIndicator(
                            value: _countdownSeconds / 5,
                            strokeWidth: 3,
                            color: const Color(0xFF8b5cf6),
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        Text(
                          '$_countdownSeconds',
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Episodio ${_currentEp + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Cancel button (left)
                      GestureDetector(
                        onTap: _cancelCountdown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Cancelar', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Skip button (right)
                      GestureDetector(
                        onTap: _skipCountdown,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8b5cf6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Saltar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Tap zones for play/pause + double-tap seek (disabled during countdown)
        Positioned.fill(
          child: IgnorePointer(
            ignoring: _showCountdown,
            child: Row(
            children: [
              // Left third: double-tap rewind
              Expanded(
                flex: 33,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _showCountdown ? null : _toggleControls,
                  onDoubleTap: _showCountdown ? null : () => _seekRelative(-9900),
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Center third: single tap = play/pause (always)
              Expanded(
                flex: 34,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _showCountdown ? null : _togglePlayPause,
                  onDoubleTap: _showCountdown ? null : _togglePlayPause,
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Right third: double-tap forward
              Expanded(
                flex: 33,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _showCountdown ? null : _toggleControls,
                  onDoubleTap: _showCountdown ? null : () => _seekRelative(9900),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
          ),
        ),

        // PiP mode is handled natively by Android — no Flutter overlay
        ], // end if (!_isPipMode)

        // Desktop PiP interactive overlay (hover controls, dragging, restore, resize)
        if (_isPipMode && _isDesktop)
          Positioned.fill(
            child: DragToResizeArea(
              resizeEdgeSize: 8,
              child: MouseRegion(
                onEnter: (_) => setState(() => _pipHovered = true),
                onExit: (_) => setState(() => _pipHovered = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => windowManager.startDragging(),
                  onDoubleTap: _exitPipDesktop,
                  child: AnimatedOpacity(
                    opacity: _pipHovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      child: Stack(
                        children: [
                          // Top action bar
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              icon: const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 20),
                              tooltip: 'Restaurar ventana',
                              onPressed: _exitPipDesktop,
                            ),
                          ),
                          // Center Play/Pause button
                          Center(
                            child: IconButton(
                              iconSize: 44,
                              icon: Icon(
                                _player.isPlaying.value ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                color: const Color(0xFFa78bfa),
                              ),
                              onPressed: _togglePlayPause,
                            ),
                          ),
                          // Bottom progress indicator
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: ValueListenableBuilder<int>(
                              valueListenable: _player.positionMs,
                              builder: (context, pos, _) {
                                final dur = _player.durationMs.value;
                                final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                                return LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8b5cf6)),
                                  minHeight: 3,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Bottom controls bar with drag bubble
        if (!_isPipMode && !isEmbed)
        IgnorePointer(
          ignoring: !_controlsVisible,
          child: FadeTransition(
            opacity: _controlsAnim!,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dur = _player.durationMs.value;
                final pos = _player.positionMs.value;
                final dv = _dragValue != null ? _dragValue! : pos.clamp(0, dur).toDouble();
                final frac = dur > 0 ? (dv / dur).clamp(0.0, 1.0) : 0.0;
                // Position bubble above thumb. Account for slider padding (16px each side).
                final sliderWidth = constraints.maxWidth - 32;
                final thumbX = 16 + (frac * sliderWidth);
                final bubbleLeft = thumbX.clamp(30.0, constraints.maxWidth - 30.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Bubble tooltip (above the controls)
                    if (_isDragging && _dragValue != null)
                      Positioned(
                        bottom: 110,
                        left: bubbleLeft - 28,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
                              ),
                              child: Text(
                                _formatTime(dv.toInt()),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            CustomPaint(
                              size: const Size(12, 6),
                              painter: _BubbleArrowPainter(),
                            ),
                          ],
                        ),
                      ),
                    // Controls bar
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Custom seek bar — raw pointer events for reliable drag
                              if (dur > 0)
                                SizedBox(
                                  height: 60,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final trackW = constraints.maxWidth;
                                      final trackH = 4.0;
                                      final topY = (constraints.maxHeight - trackH) / 2;
                                      final frac = dur > 0 ? (dv / dur).clamp(0.0, 1.0) : 0.0;

                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (details) {
                                          final effectiveW = (trackW - 20).clamp(1.0, double.infinity);
                                          final x = (details.localPosition.dx - 10).clamp(0.0, effectiveW);
                                          final target = ((x / effectiveW) * dur).clamp(0.0, dur.toDouble()).toInt();
                                          _isDragging = false;
                                          _dragValue = target.toDouble();
                                          _player.seekTo(target);
                                          _lastPositionMs = target;
                                          setState(() {});
                                          _startHideTimer();
                                        },
                                        onHorizontalDragStart: (details) {
                                          _isDragging = true;
                                          _hideTimer?.cancel();
                                          final effectiveW = (trackW - 20).clamp(1.0, double.infinity);
                                          final x = (details.localPosition.dx - 10).clamp(0.0, effectiveW);
                                          final val = ((x / effectiveW) * dur).clamp(0.0, dur.toDouble());
                                          setState(() { _dragValue = val; });
                                        },
                                        onHorizontalDragUpdate: (details) {
                                          final effectiveW = (trackW - 20).clamp(1.0, double.infinity);
                                          final x = (details.localPosition.dx - 10).clamp(0.0, effectiveW);
                                          final val = ((x / effectiveW) * dur).clamp(0.0, dur.toDouble());
                                          setState(() { _dragValue = val; });
                                        },
                                        onHorizontalDragEnd: (details) {
                                          if (_dragValue != null) {
                                            final target = _dragValue!.toInt().clamp(0, dur);
                                            _player.seekTo(target);
                                            _lastPositionMs = target;
                                          }
                                          _isDragging = false;
                                          _dragValue = null;
                                          setState(() {});
                                          _startHideTimer();
                                        },
                                        onHorizontalDragCancel: () {
                                          _isDragging = false;
                                          _dragValue = null;
                                          setState(() {});
                                          _startHideTimer();
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              // Track bg
                                              Positioned(
                                                top: topY, left: 0, right: 0,
                                                child: Container(
                                                  height: trackH,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white24,
                                                    borderRadius: BorderRadius.circular(2),
                                                  ),
                                                ),
                                              ),
                                              // Active track
                                              Positioned(
                                                top: topY, left: 0,
                                                width: (trackW - 20).clamp(0.0, double.infinity) * frac,
                                                child: Container(
                                                  height: trackH,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF8b5cf6),
                                                    borderRadius: BorderRadius.circular(2),
                                                    boxShadow: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar)
                                                        ? [
                                                            BoxShadow(
                                                              color: const Color(0xFF8b5cf6).withValues(alpha: 0.8),
                                                              blurRadius: 8,
                                                              spreadRadius: 1,
                                                            ),
                                                          ]
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                              // Thumb
                                              Positioned(
                                                left: ((trackW - 20).clamp(0.0, double.infinity) * frac) -
                                                    (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar ? 10 : 7),
                                                top: topY - (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar ? 8 : 5),
                                                child: Container(
                                                  width: TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar ? 20 : 14,
                                                  height: TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar ? 20 : 14,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF8b5cf6),
                                                    shape: BoxShape.circle,
                                                    border: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar)
                                                        ? Border.all(color: Colors.white, width: 2.5)
                                                        : null,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar)
                                                            ? const Color(0xFF8b5cf6).withValues(alpha: 0.8)
                                                            : Colors.black45,
                                                        blurRadius: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar) ? 10 : 4,
                                                        spreadRadius: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.seekBar) ? 2 : 0,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              // Compact row: play/pause · time · pip · fullscreen
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _togglePlayPause,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.playPause)
                                              ? const Color(0xFF8b5cf6).withValues(alpha: 0.35)
                                              : Colors.transparent,
                                          border: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.playPause)
                                              ? Border.all(color: const Color(0xFFa78bfa), width: 2)
                                              : null,
                                        ),
                                        child: Icon(
                                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                          color: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.playPause)
                                              ? const Color(0xFFa78bfa)
                                              : Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${_formatTime(pos)} / ${_formatTime(dur)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    const Spacer(),
                                    if (!TvService.isTvMode) ...[
                                      GestureDetector(
                                        onTap: _enterPip,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          child: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white70, size: 20),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    GestureDetector(
                                      onTap: _toggleFullscreen,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          color: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.fullscreen)
                                              ? const Color(0xFF8b5cf6).withValues(alpha: 0.35)
                                              : Colors.transparent,
                                          border: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.fullscreen)
                                              ? Border.all(color: const Color(0xFFa78bfa), width: 2)
                                              : null,
                                        ),
                                        child: Icon(
                                          _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                          color: (TvService.isTvMode && _tvFocus == _PlayerTvFocus.fullscreen)
                                              ? const Color(0xFFa78bfa)
                                              : Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );

    if (_isDesktop) {
      return MouseRegion(
        onEnter: _onMouseEnter,
        onHover: _onMouseMove,
        onExit: _onMouseExit,
        child: playerWidget,
      );
    }
    return playerWidget;
  }

  /// Format seek delta for display: each tap = 9900ms real, shows as exactly 10s.
  /// 9900→10s, 19800→20s, 59400→1:00, 69300→1:10
  static String _formatSeekDelta(num deltaMs) {
    final taps = (deltaMs.abs() / 9900).round(); // exact tap count
    final displaySeconds = taps * 10; // each tap = 10s visually
    if (displaySeconds < 60) return '${displaySeconds}s';
    final m = displaySeconds ~/ 60;
    final s = displaySeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String _formatTime(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours > 0 ? '${d.inHours}:' : '';
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h$m:$s';
  }

  Widget _buildNavButtons(EpisodeDetail ep) {
    final hasPrev = ep.number > 1;
    final hasNext = _animeDetail != null && ep.number < _animeDetail!.episodes.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: TvFocusable(
              focusNode: hasPrev ? _pageContentFocusNode : null,
              onTap: hasPrev ? _goPrev : null,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: hasPrev ? _goPrev : null,
                  icon: const Icon(Icons.skip_previous_rounded, size: 20),
                  label: const Text('Anterior', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasPrev ? const Color(0xFF1a1530) : const Color(0xFF110e1a),
                    foregroundColor: hasPrev ? const Color(0xFFa78bfa) : const Color(0xFF4a4260),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: hasPrev ? const Color(0xFF2a2240) : const Color(0xFF1e1832)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TvFocusable(
              focusNode: !hasPrev ? _pageContentFocusNode : null,
              onTap: hasNext ? _goNext : null,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: hasNext ? _goNext : null,
                  icon: const Icon(Icons.skip_next_rounded, size: 20),
                  label: const Text('Siguiente', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasNext ? const Color(0xFF1a1530) : const Color(0xFF110e1a),
                    foregroundColor: hasNext ? const Color(0xFFa78bfa) : const Color(0xFF4a4260),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    side: BorderSide(color: hasNext ? const Color(0xFF2a2240) : const Color(0xFF1e1832)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantAndServers(EpisodeDetail ep, List<ServerMirror> filteredEmbeds) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (ep.variants.length > 1) ...[
            const Icon(Icons.language, color: Color(0xFF6d6488), size: 18),
            ...ep.variants.map((v) {
              final isActive = v == _activeVariant;
              final label = v == 'DUB' ? 'Doblaje' : 'Subtitulado';
              return ChoiceChip(
                label: Text(label),
                selected: isActive,
                onSelected: (_) { setState(() => _activeVariant = v); _autoPlay(); },
                selectedColor: const Color(0xFF8b5cf6),
                backgroundColor: const Color(0xFF110e1a),
                labelStyle: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFFa99fc0),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                side: const BorderSide(color: Color(0xFF1e1832)),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(EpisodeDetail ep, AnimeDetail? anime) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _closePlayback,
          child: Text(widget.animeTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFe8e4f0))),
        ),
        const SizedBox(height: 4),
        Text('Episodio ${ep.number}', style: const TextStyle(fontSize: 14, color: Color(0xFF6d6488))),
        if (anime != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(anime.category, const Color(0xFF8b5cf6)),
            if (anime.status.isNotEmpty && anime.status != 'unknown')
              _chip(anime.status, anime.status.contains('Finalizado') ? const Color(0xFF22c55e) : const Color(0xFFf59e0b)),
            ...anime.genres.map((g) => _chip(g.name, const Color(0xFF3b82f6))),
          ]),
        ],
        if (anime != null && anime.synopsis.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(anime.synopsis, style: const TextStyle(fontSize: 14, color: Color(0xFFa99fc0), height: 1.5)),
        ],
        if (anime != null && anime.episodes.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text('Episodios',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFe8e4f0))),
              ),
              // Botón "Descargar": abre el selector de capítulos con el
              // capítulo actual ya marcado (mismo menú del detail page).
              ValueListenableBuilder<Map<String, double>>(
                valueListenable: DownloadService.instance.progress,
                builder: (context, progress, _) {
                  final dl = DownloadService.instance;
                  final n = ep.number;
                  final slug = widget.animeSlug;
                  final isDownloaded = dl.isDownloaded(slug, n);
                  final isQueued = dl.isQueued(slug, n);

                  // Sin detalle del anime no se puede abrir el selector.
                  if (_animeDetail == null) {
                    return const SizedBox.shrink();
                  }

                  // Descargado o en cola: solo estado, sin acción de descarga.
                  if (isDownloaded || isQueued) {
                    return Icon(
                      isDownloaded
                          ? Icons.check_circle_rounded
                          : Icons.downloading_rounded,
                      size: 20,
                      color: isDownloaded
                          ? const Color(0xFF22c55e)
                          : const Color(0xFFf59e0b),
                    );
                  }

                  return TvFocusable(
                    onTap: () => DownloadSheet.show(
                      context,
                      _animeDetail!,
                      preselected: {n},
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: OutlinedButton.icon(
                      onPressed: () => DownloadSheet.show(
                        context,
                        _animeDetail!,
                        preselected: {n},
                      ),
                      icon: const Icon(Icons.download_rounded, size: 17),
                      label: const Text('Descargar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFa78bfa),
                        side: const BorderSide(color: Color(0xFF3b2f5c)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 34),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: anime.episodes
              .where((e) =>
                  !widget.offlineLibrary ||
                  DownloadService.instance.isDownloaded(
                      widget.animeSlug, e.number))
              .map((e) {
            final isCurrent = e.number == ep.number;
            final isWatched = _watchedEpisodes.contains(e.number) && !isCurrent;
            final isDownloaded =
                DownloadService.instance.isDownloaded(widget.animeSlug, e.number);
            return TvFocusable(
              onTap: () {
                if (!isCurrent) _switchEpisode(e.number);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFF8b5cf6) : const Color(0xFF110e1a),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrent
                        ? const Color(0xFF8b5cf6)
                        : isDownloaded
                            ? const Color(0xFF22c55e)
                            : isWatched
                                ? const Color(0xFF8b5cf6)
                                : const Color(0xFF1e1832),
                    width: isWatched || isDownloaded ? 2 : 1,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('${e.number}', style: TextStyle(fontWeight: FontWeight.w700, color: isCurrent ? Colors.white : const Color(0xFFe8e4f0))),
                    if (isWatched)
                      Positioned(
                        top: 2, right: 2,
                        child: Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF8b5cf6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList()),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  static Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

/// Small downward arrow for the seek bubble tooltip
class _BubbleArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Componente glassmorphism con estética oscura púrpura nativa de AniMaple.
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? borderColor;
  final List<Color>? gradientColors;

  const _GlassCard({
    required this.child,
    this.padding,
    this.borderRadius = 10,
    this.borderColor,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors ??
              [
                const Color(0xFF18122c).withValues(alpha: TvService.isTvMode ? 0.95 : 0.85),
                const Color(0xFF0e0a1a).withValues(alpha: TvService.isTvMode ? 0.98 : 0.90),
              ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? const Color(0xFF8b5cf6).withValues(alpha: 0.22),
          width: 1.0,
        ),
      ),
      child: child,
    );

    if (TvService.isTvMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: container,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: container,
      ),
    );
  }
}

/// Panel de sondeo en vivo con diseño nativo de AniMaple en tarjetas separadas.
class _ProbeScanPanel extends StatefulWidget {
  final Map<String, double> speeds;
  final bool started;
  const _ProbeScanPanel({super.key, required this.speeds, required this.started});

  @override
  State<_ProbeScanPanel> createState() => _ProbeScanPanelState();
}

class _ProbeScanPanelState extends State<_ProbeScanPanel> {
  @override
  Widget build(BuildContext context) {
    final entries = widget.speeds.entries.toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabecera estilizada con la identidad púrpura de AniMaple
          _GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            borderRadius: 10,
            borderColor: const Color(0xFF8b5cf6).withValues(alpha: 0.30),
            gradientColors: [
              const Color(0xFF22173d).withValues(alpha: 0.88),
              const Color(0xFF110d1e).withValues(alpha: 0.92),
            ],
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8b5cf6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Seleccionando servidor',
                        style: TextStyle(
                          color: Color(0xFFe8e4f0),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.started
                            ? 'Midiendo velocidad en tiempo real…'
                            : 'Buscando las mejores fuentes…',
                        style: const TextStyle(
                          color: Color(0xFF8b5cf6),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _serverGlassTile(e.key, e.value),
            ),
        ],
      ),
    );
  }

  Widget _serverGlassTile(String name, double mbps) {
    final isEmbed = name.toLowerCase().contains('byse');
    final probing = mbps.isNaN;
    final ok = !probing && mbps >= 2.5;
    final meh = !probing && mbps > 0.0 && mbps < 2.5;
    final label = name.length > 24 ? '${name.substring(0, 24)}…' : name;

    final accent = probing
        ? const Color(0xFFa78bfa)
        : isEmbed
            ? const Color(0xFFc084fc)
            : ok
                ? const Color(0xFF22c55e)
                : meh
                    ? const Color(0xFFf59e0b)
                    : const Color(0xFFef4444);

    return _GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 10,
      borderColor: accent.withValues(alpha: 0.22),
      gradientColors: [
        const Color(0xFF18122c).withValues(alpha: 0.80),
        const Color(0xFF0e0a1a).withValues(alpha: 0.88),
      ],
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFe8e4f0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.28), width: 0.8),
            ),
            child: Text(
              probing
                  ? 'Midiendo…'
                  : isEmbed
                      ? 'Web embed'
                      : '${mbps.toStringAsFixed(1)} Mbps',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta final de servidor elegido con diseño nativo y unificado de AniMaple.
class _ProbeChosenCard extends StatefulWidget {
  final String server;
  final bool prewarming;
  const _ProbeChosenCard({super.key, required this.server, this.prewarming = false});

  @override
  State<_ProbeChosenCard> createState() => _ProbeChosenCardState();
}

class _ProbeChosenCardState extends State<_ProbeChosenCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = widget.prewarming ? const Color(0xFFa78bfa) : const Color(0xFF22c55e);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: _GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        borderRadius: 12,
        borderColor: const Color(0xFF8b5cf6).withValues(alpha: 0.32),
        gradientColors: [
          const Color(0xFF20163b).withValues(alpha: 0.90),
          const Color(0xFF0e0a1a).withValues(alpha: 0.94),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF8b5cf6).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF8b5cf6).withValues(alpha: 0.30),
                  width: 0.8,
                ),
              ),
              child: Text(
                widget.prewarming ? 'OPTIMIZANDO FUENTE' : 'SERVIDOR SELECCIONADO',
                style: const TextStyle(
                  color: Color(0xFFc4b5fd),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.server,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFe8e4f0),
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.prewarming
                  ? 'Preparando transmisión fluida…'
                  : 'Conectando con el servidor…',
              style: const TextStyle(
                color: Color(0xFF8b5cf6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.prewarming) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    color: Color(0xFF8b5cf6),
                    backgroundColor: Color(0xFF22173d),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FadeTransition(
              opacity: Tween(begin: 0.6, end: 1.0).animate(_pulse),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.prewarming ? 'Cargando datos iniciales…' : 'Iniciando reproducción…',
                    style: const TextStyle(
                      color: Color(0xFFa99fc0),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
