import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_view/video_view.dart' as vv;
import 'fsr_service.dart';

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Unified media player abstraction for AniMaple.
/// Uses media_kit (libmpv) on Windows/Desktop and video_view (ExoPlayer) on Android.
abstract class AppPlayer {
  ValueListenable<bool> get isPlaying;
  ValueListenable<bool> get isLoading;
  ValueListenable<int> get positionMs;
  ValueListenable<int> get durationMs;
  ValueListenable<String?> get error;
  ValueListenable<int> get finishedCount;

  bool get isDisposed;

  Future<void> open(String url, {Map<String, String>? headers, int? startPositionMs});
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(int positionMs);
  Future<void> close();
  void dispose();
  Future<void> setFsrEnabled(bool enabled);

  Widget buildView({BoxFit fit = BoxFit.contain});

  factory AppPlayer.create() {
    if (isDesktopPlatform) {
      final player = MediaKitAppPlayer.instance;
      player._reset();
      return player;
    } else {
      return VideoViewAppPlayer();
    }
  }
}

/// Windows / Desktop implementation using media_kit (libmpv).
class MediaKitAppPlayer implements AppPlayer {
  static MediaKitAppPlayer? _instance;

  static MediaKitAppPlayer get instance {
    _instance ??= MediaKitAppPlayer._();
    return _instance!;
  }

  late final mk.Player _player;
  late final mkv.VideoController _videoController;

  final ValueNotifier<bool> _isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<int> _positionMs = ValueNotifier<int>(0);
  final ValueNotifier<int> _durationMs = ValueNotifier<int>(0);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  final ValueNotifier<int> _finishedCount = ValueNotifier<int>(0);

  final List<StreamSubscription> _subscriptions = [];
  bool _disposed = false;

  MediaKitAppPlayer._() {
    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        title: 'AniMaple',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    _videoController = mkv.VideoController(
      _player,
      configuration: mkv.VideoControllerConfiguration(
        enableHardwareAcceleration: !Platform.isLinux,
      ),
    );

    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (!_disposed) _isPlaying.value = playing;
    }));

    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      if (!_disposed) _isLoading.value = buffering;
    }));

    _subscriptions.add(_player.stream.position.listen((pos) {
      if (!_disposed) _positionMs.value = pos.inMilliseconds;
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      if (!_disposed) _durationMs.value = dur.inMilliseconds;
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (!_disposed && completed) {
        final dur = _durationMs.value;
        final pos = _positionMs.value;
        // Verify that the video actually reached the end before signaling finished.
        // On network streams or seeks, libmpv may emit eof-reached prematurely.
        if (dur > 20000 && pos > 0 && pos < (dur - 15000)) {
          debugPrint('MediaKit: spurious completed/eof ignored at $pos ms / $dur ms');
          _player.play();
          return;
        }
        _finishedCount.value = _finishedCount.value + 1;
      }
    }));

    _subscriptions.add(_player.stream.error.listen((err) {
      if (!_disposed && err.isNotEmpty) {
        _error.value = err;
      }
    }));
  }

  void _reset() {
    _disposed = false;
    _isPlaying.value = false;
    _isLoading.value = true;
    _positionMs.value = 0;
    _durationMs.value = 0;
    _error.value = null;
    _finishedCount.value = 0;
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  ValueListenable<bool> get isPlaying => _isPlaying;

  @override
  ValueListenable<bool> get isLoading => _isLoading;

  @override
  ValueListenable<int> get positionMs => _positionMs;

  @override
  ValueListenable<int> get durationMs => _durationMs;

  @override
  ValueListenable<String?> get error => _error;

  @override
  ValueListenable<int> get finishedCount => _finishedCount;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> open(String url, {Map<String, String>? headers, int? startPositionMs}) async {
    _disposed = false;
    _error.value = null;
    _isLoading.value = true;

    final referer = headers?['Referer'] ??
        (url.contains('zilla')
            ? 'https://player.zilla-networks.com/'
            : (url.contains('mp4upload')
                ? 'https://www.mp4upload.com/'
                : ''));

    final effectiveHeaders = <String, String>{
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
      'Accept': '*/*',
      'Accept-Language': 'es-EC,es-419;q=0.9,es;q=0.8',
      'User-Agent': _defaultUserAgent,
      if (referer.isNotEmpty) 'Referer': referer,
      if (referer.isNotEmpty) 'Origin': referer.endsWith('/') ? referer.substring(0, referer.length - 1) : referer,
      ...?headers,
    };

    final ua = effectiveHeaders['User-Agent']!;
    final ref = effectiveHeaders['Referer'] ?? '';

    try {
      final platform = _player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty('user-agent', ua);
        if (ref.isNotEmpty) {
          await (platform as dynamic).setProperty('referrer', ref);
        }
        await (platform as dynamic).setProperty('force-seekable', 'yes');
        await (platform as dynamic).setProperty('demuxer-seekable-cache', 'yes');
        await (platform as dynamic).setProperty('keep-open', 'yes');
        await (platform as dynamic).setProperty('hr-seek', 'yes');
        await (platform as dynamic).setProperty('hr-seek-framedrop', 'yes');
        await (platform as dynamic).setProperty('demuxer-readahead-secs', '120');
        await (platform as dynamic).setProperty('demuxer-max-bytes', '134217728'); // 128 MB
        await (platform as dynamic).setProperty('demuxer-max-back-bytes', '67108864'); // 64 MB
        await (platform as dynamic).setProperty('network-timeout', '30');
      }
    } catch (e) {
      debugPrint('Error applying mpv properties: $e');
    }

    final media = mk.Media(
      url,
      httpHeaders: effectiveHeaders,
      start: (startPositionMs != null && startPositionMs > 0)
          ? Duration(milliseconds: startPositionMs)
          : null,
    );
    await _player.open(media, play: true);
  }

  @override
  Future<void> setFsrEnabled(bool enabled) async {
    // Shaders multi-paso complejos con texturas intermedias agotan las swapchains
    // de ANGLE/D3D11 en Windows (HRESULT 0x887A0022) provocando EGL Context Lost
    // y caída del proceso. En desktop mantenemos la pipeline nativa limpia.
    try {
      final platform = _player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty('glsl-shaders', '');
      }
    } catch (_) {}
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    await _player.pause();
  }

  @override
  Future<void> seekTo(int positionMs) async {
    if (_disposed) return;
    _positionMs.value = positionMs;
    _isLoading.value = true;
    try {
      await _player.seek(Duration(milliseconds: positionMs));
    } catch (e) {
      debugPrint('Error seeking in MediaKitAppPlayer: $e');
    }
  }

  @override
  Future<void> close() async {
    _isPlaying.value = false;
    _isLoading.value = false;
    _positionMs.value = 0;
    _durationMs.value = 0;
    _finishedCount.value = 0;
    _error.value = null;
    try {
      await _player.pause();
      await _player.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _isPlaying.value = false;
    _isLoading.value = false;
    _positionMs.value = 0;
    _durationMs.value = 0;
    _finishedCount.value = 0;
    _error.value = null;
    try {
      _player.pause();
      _player.stop();
    } catch (_) {}
  }

  static final GlobalKey _videoWidgetKey = GlobalKey();

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    return mkv.Video(
      key: _videoWidgetKey,
      controller: _videoController,
      controls: mkv.NoVideoControls,
      fit: fit,
    );
  }
}

/// Android implementation using video_view (ExoPlayer).
class VideoViewAppPlayer implements AppPlayer {
  late final vv.VideoController _vvController;

  final ValueNotifier<bool> _isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<int> _positionMs = ValueNotifier<int>(0);
  final ValueNotifier<int> _durationMs = ValueNotifier<int>(0);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  final ValueNotifier<int> _finishedCount = ValueNotifier<int>(0);

  Timer? _posTimer;
  bool _disposed = false;

  VideoViewAppPlayer() {
    _vvController = vv.VideoController(
      autoPlay: true,
      cancelableNotification: true,
      keepScreenOn: true,
      fsrEnabled: FsrService.isEnabled.value,
    );

    _vvController.playbackState.addListener(_onState);
    _vvController.loading.addListener(_onLoading);
    _vvController.error.addListener(_onError);
    _vvController.finishedTimes.addListener(_onFinished);
    _vvController.mediaInfo.addListener(_onMediaInfo);

    _posTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_disposed) {
        _positionMs.value = _vvController.position.value;
      }
    });
  }

  void _onState() {
    if (_disposed) return;
    _isPlaying.value =
        _vvController.playbackState.value == vv.VideoControllerPlaybackState.playing;
  }

  void _onLoading() {
    if (_disposed) return;
    _isLoading.value = _vvController.loading.value;
  }

  void _onError() {
    if (_disposed) return;
    _error.value = _vvController.error.value;
  }

  void _onFinished() {
    if (_disposed) return;
    _finishedCount.value = _vvController.finishedTimes.value;
  }

  void _onMediaInfo() {
    if (_disposed) return;
    final dur = _vvController.mediaInfo.value?.duration;
    if (dur != null) _durationMs.value = dur;
  }

  @override
  ValueListenable<bool> get isPlaying => _isPlaying;

  @override
  ValueListenable<bool> get isLoading => _isLoading;

  @override
  ValueListenable<int> get positionMs => _positionMs;

  @override
  ValueListenable<int> get durationMs => _durationMs;

  @override
  ValueListenable<String?> get error => _error;

  @override
  ValueListenable<int> get finishedCount => _finishedCount;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> open(String url, {Map<String, String>? headers, int? startPositionMs}) async {
    if (_disposed) return;
    _error.value = null;
    final referer = headers?['Referer'] ??
        (url.contains('zilla')
            ? 'https://player.zilla-networks.com/'
            : (url.contains('mp4upload')
                ? 'https://www.mp4upload.com/'
                : ''));
    final effectiveHeaders = <String, String>{
      if (referer.isNotEmpty) 'Referer': referer,
      ...?headers,
    };
    _vvController.setFsrEnabled(FsrService.isEnabled.value);
    _vvController.open(url, headers: effectiveHeaders);
    if (startPositionMs != null && startPositionMs > 0) {
      _vvController.seekTo(startPositionMs);
    }
  }

  @override
  Future<void> setFsrEnabled(bool enabled) async {
    try {
      _vvController.setFsrEnabled(enabled);
    } catch (e) {
      debugPrint('Error applying FSR 2K in VideoViewAppPlayer: $e');
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _vvController.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _vvController.pause();
  }

  @override
  Future<void> seekTo(int positionMs) async {
    if (_disposed) return;
    _vvController.seekTo(positionMs);
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    _vvController.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _posTimer?.cancel();
    _vvController.playbackState.removeListener(_onState);
    _vvController.loading.removeListener(_onLoading);
    _vvController.error.removeListener(_onError);
    _vvController.finishedTimes.removeListener(_onFinished);
    _vvController.mediaInfo.removeListener(_onMediaInfo);
    _vvController.dispose();
  }

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    return vv.VideoView(
      controller: _vvController,
      keepScreenOn: true,
      fsrEnabled: FsrService.isEnabled.value,
    );
  }
}
