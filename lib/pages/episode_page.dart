import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_view/video_view.dart';
import '../models/anime.dart';
import '../services/api_service.dart';

bool get _isDesktop => !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);


class EpisodePage extends StatefulWidget {
  final String animeSlug;
  final int episodeNumber;
  final String animeTitle;

  const EpisodePage({
    super.key,
    required this.animeSlug,
    required this.episodeNumber,
    required this.animeTitle,
  });

  @override
  State<EpisodePage> createState() => _EpisodePageState();
}

class _EpisodePageState extends State<EpisodePage> with TickerProviderStateMixin {
  EpisodeDetail? _episode;
  AnimeDetail? _animeDetail;
  bool _loading = true;

  String? _activeServer;
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

  // Double-tap seek accumulation
  int _seekAccumulatorMs = 0;
  DateTime? _lastSeekTapTime;
  int _seekBasePosition = 0;
  static const Duration _seekAccumulationWindow = Duration(milliseconds: 1500);
  Timer? _seekResetTimer;

  // PiP
  static const _pipChannel = MethodChannel('com.mapleprojects.animaple/pip');
  bool _isPipMode = false;

  // Media notification
  static const _mediaChannel = MethodChannel('com.mapleprojects.animaple/media_session');
  bool _notificationPermissionRequested = false;

  // End-of-episode countdown
  bool _showCountdown = false;
  int _countdownSeconds = 5;
  Timer? _countdownTimer;

  // Position update timer (video_view doesn't auto-rebuild on position change)
  Timer? _positionTimer;

  // Mouse hover (desktop only)
  bool _isHovering = false;

  // Linux fullscreen via MethodChannel
  static const _linuxChannel = MethodChannel('com.mapleprojects.animaple/linux_window');

  // Mutable episode number — allows in-place episode switching
  late int _currentEp;

  late final VideoController _player;

  @override
  void initState() {
    super.initState();
    _currentEp = widget.episodeNumber;
    _player = VideoController(autoPlay: true, cancelableNotification: true);
    _controlsAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 250), value: 1.0);
    _seekAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _seekFadeAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1.0);
    _player.playbackState.addListener(_onStateChanged);
    _player.finishedTimes.addListener(_onFinished);
    _player.error.addListener(_onError);
    _player.loading.addListener(_onLoading);
    _player.videoSize.addListener(_onVideoSize);
    _player.mediaInfo.addListener(_onMediaInfo);
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
              SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
        case 'mediaTogglePlayPause':
          _togglePlayPause();
          break;
        case 'mediaStop':
          _player.pause();
          _dismissMediaNotification();
          break;
      }
    });
  }

  // ── Desktop-only: keyboard shortcut F + mouse hover ──

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onMouseEnter(PointerEvent event) {
    _isHovering = true;
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _controlsAnim!.forward();
    }
    _startHideTimer();
  }

  void _onMouseExit(PointerEvent event) {
    _isHovering = false;
    if (!_isDragging && !_showCountdown) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
      _controlsAnim?.reverse();
    }
  }

  Future<void> _enterPip() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (e) {
      debugPrint('PiP enter error: $e');
    }
  }

  void _closePlayback() {
    _player.close();
    _positionTimer?.cancel();
    _syncPipState(false);
    _dismissMediaNotification();
    if (mounted) Navigator.pop(context);
  }

  void _onStateChanged() {
    final playing = _player.playbackState.value == VideoControllerPlaybackState.playing;
    if (playing) {
      _startPositionTimer();
      // Auto-hide controls when video starts playing
      _startHideTimer();
    } else {
      _positionTimer?.cancel();
    }
    // Only sync playing=true to native. Don't sync false —
    // the player may report non-playing states (buffering, surface lost)
    // before onPause fires on MIUI, which breaks auto-PiP.
    if (playing) _syncPipState(true);
    // Request notification permission on first play
    if (playing) _requestNotificationPermission();
    // Update media notification with current state
    _updateMediaSession(playing);
    if (mounted) setState(() {});
  }

  void _syncPipState(bool playing) {
    try {
      _pipChannel.invokeMethod('updatePipState', playing);
    } catch (_) {}
  }

  void _updateMediaSession(bool playing) {
    try {
      final duration = _player.mediaInfo.value?.duration ?? 0;
      final position = _player.position.value;
      final animeDetail = _animeDetail;
      _mediaChannel.invokeMethod('updateMediaSession', {
        'title': widget.animeTitle,
        'episode': _currentEp,
        'playing': playing,
        'position': position,
        'duration': duration,
        'animeId': animeDetail?.id ?? 0,
      });
    } catch (_) {}
  }

  void _dismissMediaNotification() {
    try {
      _mediaChannel.invokeMethod('dismissMediaNotification');
    } catch (_) {}
  }

  void _requestNotificationPermission() {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      _mediaChannel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  void _onFinished() {
    if (_player.finishedTimes.value > 0 && mounted && !_autoPlayedNext) {
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

  void _onError() {
    final err = _player.error.value;
    if (err != null && err.isNotEmpty) {
      debugPrint('VIDEO_VIEW ERROR: $err');
    }
  }

  void _onLoading() {
    if (mounted) setState(() {});
  }

  void _onVideoSize() {
    debugPrint('VIDEO_VIEW videoSize: ${_player.videoSize.value}');
    if (mounted) setState(() {});
  }

  void _onMediaInfo() {
    debugPrint('VIDEO_VIEW mediaInfo: ${_player.mediaInfo.value?.duration}');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _positionTimer?.cancel();
    _seekResetTimer?.cancel();
    _controlsAnim?.dispose();
    _seekAnim?.dispose();
    _seekFadeAnim?.dispose();
    _player.playbackState.removeListener(_onStateChanged);
    _player.finishedTimes.removeListener(_onFinished);
    _player.error.removeListener(_onError);
    _player.loading.removeListener(_onLoading);
    _player.videoSize.removeListener(_onVideoSize);
    _player.mediaInfo.removeListener(_onMediaInfo);
    _player.dispose();
    _syncPipState(false);
    _dismissMediaNotification();
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _load() async {
    while (mounted) {
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
        _autoPlay();
        return;
      } catch (e) {
        debugPrint('EPISODE LOAD RETRY: $e');
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  void _autoPlay() {
    final ep = _episode;
    if (ep == null) return;
    final filtered = ep.embeds.where((s) => s.variant == _activeVariant).toList();
    // Only HLS and MP4Upload — ignore other servers
    final hls = filtered.where((s) => s.server.toLowerCase().contains('hls')).toList();
    if (hls.isNotEmpty) { _playServer(hls.first); return; }
    final mp4 = filtered.where((s) => s.server.toLowerCase().contains('mp4upload')).toList();
    if (mp4.isNotEmpty) { _playServer(mp4.first); return; }
  }

  Future<void> _playServer(ServerMirror server) async {
    if (mounted) setState(() { _activeServer = server.server; _autoPlayedNext = false; });

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
        // Pass raw URL directly — ExoPlayer handles HLS natively.
        // For MP4Upload, pass Referer header (required or 403 Forbidden).
        final headers = videoType == 'mp4'
            ? {'Referer': 'https://www.mp4upload.com/'}
            : null;
        _player.open(videoUrl, headers: headers);
        return;
      } catch (e) {
        debugPrint('PLAY RETRY: $e');
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  // In-place episode switch — no Navigator, no widget rebuild, fullscreen persists
  void _switchEpisode(int newEp) {
    final detail = _animeDetail;
    if (detail == null) return;
    if (newEp < 1 || newEp > detail.episodes.length) return;
    if (newEp == _currentEp) return;
    setState(() {
      _currentEp = newEp;
      _loading = true;
    });
    _player.close();
    _load();
  }

  void _goNext() => _switchEpisode(_currentEp + 1);
  void _goPrev() => _switchEpisode(_currentEp - 1);

  void _toggleFullscreen() async {
    if (_isDesktop) {
      try { await _linuxChannel.invokeMethod('toggleFullScreen'); } catch (_) {}
    }
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen && !_isDesktop) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else if (!_isDesktop) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6))));
    }
    final ep = _episode;
    if (ep == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Error cargando episodio')));
    }

    final filteredEmbeds = ep.embeds.where((s) =>
      s.variant == _activeVariant &&
      (s.server.toLowerCase().contains('hls') || s.server.toLowerCase().contains('mp4upload'))
    ).toList();
    final anime = _animeDetail;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFF0a0812),
      appBar: (_isFullscreen || _isPipMode) ? null : AppBar(
        backgroundColor: const Color(0xFF0a0812),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
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
          ? Center(child: AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPlayer()))
          : isWide
            ? _buildWideLayout(ep, filteredEmbeds, anime)
            : _buildNarrowLayout(ep, filteredEmbeds, anime),
    );

    if (_isDesktop) {
      return Focus(autofocus: true, onKeyEvent: _handleKeyEvent, child: scaffold);
    }
    return scaffold;
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
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      // Clear _dragValue when player position catches up after seek
      if (_dragValue != null && !_isDragging) {
        final pos = _player.position.value;
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
    if (_isHovering) return; // Don't hide on desktop when mouse is over
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isDragging && !_isHovering) setState(() => _controlsVisible = false);
      _controlsAnim?.reverse();
    });
  }

  void _togglePlayPause() {
    final ps = _player.playbackState.value;
    if (ps == VideoControllerPlaybackState.playing) {
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
    final pos = _player.position.value;
    final dur = _player.mediaInfo.value?.duration ?? 0;

    // Accumulate seeks within the time window
    if (_lastSeekTapTime != null && now.difference(_lastSeekTapTime!) < _seekAccumulationWindow) {
      _seekAccumulatorMs += deltaMs;
    } else {
      // New sequence — reset accumulator
      _seekBasePosition = pos;
      _seekAccumulatorMs = deltaMs;
    }
    _lastSeekTapTime = now;

    final target = (_seekBasePosition + _seekAccumulatorMs).clamp(0, dur);
    _player.seekTo(target);

    _seekDelta = _seekAccumulatorMs.toDouble();
    _seekAnimating = true;
    setState(() {});

    // Restart fade animation on each tap
    _seekFadeAnim!.forward(from: 0);

    // Cancel previous reset timer, start new one
    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _seekFadeAnim!.reverse().then((_) {
        if (mounted) setState(() {
          _seekAnimating = false;
          _seekDelta = null;
        });
      });
    });

    _showControlsTemporarily();
  }

  // ── Video player with overlay controls ──

  Widget _buildVideoPlayer() {
    final duration = _player.mediaInfo.value?.duration ?? 0;
    final position = _player.position.value;
    final isPlaying = _player.playbackState.value == VideoControllerPlaybackState.playing;
    final playerWidget = Stack(
      alignment: Alignment.center,
      children: [
        // Video surface
        VideoView(controller: _player),

        // ── Everything below is hidden in PiP mode ──
        if (!_isPipMode) ...[

        // Loading spinner
        if (_player.loading.value)
          const CircularProgressIndicator(color: Color(0xFF8b5cf6), strokeWidth: 2.5),

        // Big center play/pause (when paused)
        if (!isPlaying && !_player.loading.value)
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
                        _seekDelta! < 0 ? Icons.replay_5_rounded : Icons.forward_5_rounded,
                        color: Colors.white, size: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_seekDelta! > 0 ? '+' : ''}${(_seekDelta! ~/ 1000)}s',
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
                  onDoubleTap: _showCountdown ? null : () => _seekRelative(-2500),
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
                  onDoubleTap: _showCountdown ? null : () => _seekRelative(2500),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
          ),
        ),

        // PiP mode is handled natively by Android — no Flutter overlay
        ], // end if (!_isPipMode)

        // Bottom controls bar with drag bubble
        IgnorePointer(
          ignoring: !_controlsVisible,
          child: FadeTransition(
            opacity: _controlsAnim!,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dur = _player.mediaInfo.value?.duration ?? 0;
                final pos = _player.position.value;
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
                    if (_isDragging)
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

                                      return Listener(
                                        onPointerDown: (e) {
                                          _isDragging = true;
                                          _hideTimer?.cancel();
                                          final x = e.localPosition.dx.clamp(0.0, trackW);
                                          final val = (x / trackW * dur).clamp(0.0, dur.toDouble());
                                          setState(() { _dragValue = val; });
                                        },
                                        onPointerMove: (e) {
                                          final x = e.localPosition.dx.clamp(0.0, trackW);
                                          final val = (x / trackW * dur).clamp(0.0, dur.toDouble());
                                          setState(() { _dragValue = val; });
                                        },
                                        onPointerUp: (e) {
                                          final target = (_dragValue ?? dv).toInt().clamp(0, dur);
                                          _player.seekTo(target);
                                          _isDragging = false;
                                          _dragValue = null;
                                          setState(() {});
                                          _startHideTimer();
                                        },
                                        onPointerCancel: (e) {
                                          _isDragging = false;
                                          _dragValue = null;
                                          setState(() {});
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
                                                width: trackW * frac,
                                                child: Container(
                                                  height: trackH,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF8b5cf6),
                                                    borderRadius: BorderRadius.circular(2),
                                                  ),
                                                ),
                                              ),
                                              // Thumb
                                              Positioned(
                                                left: (trackW * frac) - 7,
                                                child: Container(
                                                  width: 14, height: 14,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF8b5cf6),
                                                    shape: BoxShape.circle,
                                                    boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
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
                                      child: Icon(
                                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: Colors.white, size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${_formatTime(pos)} / ${_formatTime(dur)}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: _enterPip,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white70, size: 20),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: _toggleFullscreen,
                                      child: Icon(
                                        _isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                        color: Colors.white, size: 22,
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
      return MouseRegion(onEnter: _onMouseEnter, onExit: _onMouseExit, child: playerWidget);
    }
    return playerWidget;
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
            child: SizedBox(
              height: 44,
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
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 44,
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
        ],
      ),
    );
  }

  Widget _buildVariantAndServers(EpisodeDetail ep, List<ServerMirror> filteredEmbeds) {
    return Column(
      children: [
        if (ep.variants.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.language, color: Color(0xFF6d6488), size: 18),
                const SizedBox(width: 8),
                ...ep.variants.map((v) {
                  final isActive = v == _activeVariant;
                  final label = v == 'DUB' ? 'Doblaje' : 'Subtitulado';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: isActive,
                      onSelected: (_) { setState(() => _activeVariant = v); _autoPlay(); },
                      selectedColor: const Color(0xFF8b5cf6),
                      backgroundColor: const Color(0xFF110e1a),
                      labelStyle: TextStyle(color: isActive ? Colors.white : const Color(0xFFa99fc0), fontWeight: FontWeight.w600, fontSize: 13),
                      side: const BorderSide(color: Color(0xFF1e1832)),
                    ),
                  );
                }),
              ],
            ),
          ),
        if (filteredEmbeds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, color: Color(0xFF6d6488), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8, runSpacing: 4,
                    children: filteredEmbeds.map((s) {
                      final isActive = _activeServer == s.server;
                      return ChoiceChip(
                        label: Text(s.server),
                        selected: isActive,
                        onSelected: (_) => _playServer(s),
                        selectedColor: const Color(0xFF8b5cf6),
                        backgroundColor: const Color(0xFF110e1a),
                        labelStyle: TextStyle(color: isActive ? Colors.white : const Color(0xFFa99fc0), fontWeight: FontWeight.w600),
                        side: const BorderSide(color: Color(0xFF1e1832)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoSection(EpisodeDetail ep, AnimeDetail? anime) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Text(widget.animeTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFe8e4f0))),
        ),
        const SizedBox(height: 4),
        Text('Episodio ${ep.number}', style: const TextStyle(fontSize: 14, color: Color(0xFF6d6488))),
        if (anime != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(anime.category, const Color(0xFF8b5cf6)),
            if (int.tryParse(anime.status) == null)
              _chip(anime.status, const Color(0xFF22c55e)),
            ...anime.genres.map((g) => _chip(g.name, const Color(0xFF3b82f6))),
          ]),
        ],
        if (anime != null && anime.synopsis.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(anime.synopsis, style: const TextStyle(fontSize: 14, color: Color(0xFFa99fc0), height: 1.5)),
        ],
        if (anime != null && anime.episodes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Episodios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFe8e4f0))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: anime.episodes.map((e) {
            final isCurrent = e.number == ep.number;
            return GestureDetector(
              onTap: () {
                if (!isCurrent) _switchEpisode(e.number);
              },
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isCurrent ? const Color(0xFF8b5cf6) : const Color(0xFF110e1a),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCurrent ? const Color(0xFF8b5cf6) : const Color(0xFF1e1832)),
                ),
                child: Center(child: Text('${e.number}', style: TextStyle(fontWeight: FontWeight.w700, color: isCurrent ? Colors.white : const Color(0xFFe8e4f0)))),
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
