import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_view/video_view.dart';
import '../models/anime.dart';
import '../services/api_service.dart';


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

class _EpisodePageState extends State<EpisodePage> {
  EpisodeDetail? _episode;
  AnimeDetail? _animeDetail;
  bool _loading = true;

  String? _activeServer;
  String _activeVariant = 'DUB';
  bool _isFullscreen = false;
  bool _autoPlayedNext = false;

  // Video controls
  bool _controlsVisible = true;
  bool _showBigPlay = false;
  bool _isDragging = false;
  Timer? _hideTimer;

  // Mutable episode number — allows in-place episode switching
  late int _currentEp;

  late final VideoController _player;

  @override
  void initState() {
    super.initState();
    _currentEp = widget.episodeNumber;
    _player = VideoController(autoPlay: true, cancelableNotification: true);
    _player.playbackState.addListener(_onStateChanged);
    _player.finishedTimes.addListener(_onFinished);
    _player.error.addListener(_onError);
    _player.loading.addListener(_onLoading);
    _player.videoSize.addListener(_onVideoSize);
    _player.mediaInfo.addListener(_onMediaInfo);
    _load();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _onFinished() {
    if (_player.finishedTimes.value > 0 && mounted && !_autoPlayedNext) {
      _autoPlayedNext = true;
      _goNext();
    }
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
    _player.playbackState.removeListener(_onStateChanged);
    _player.finishedTimes.removeListener(_onFinished);
    _player.error.removeListener(_onError);
    _player.loading.removeListener(_onLoading);
    _player.videoSize.removeListener(_onVideoSize);
    _player.mediaInfo.removeListener(_onMediaInfo);
    _player.dispose();
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
        // The Dart proxy was corrupting binary segment data causing
        // ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED / NoDeclaredBrand.
        _player.open(videoUrl);
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

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
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

    return Scaffold(
      backgroundColor: const Color(0xFF0a0812),
      appBar: _isFullscreen ? null : AppBar(
        backgroundColor: const Color(0xFF0a0812),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.animeTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFe8e4f0))),
            Text('Episodio $ep.number', style: const TextStyle(fontSize: 12, color: Color(0xFF6d6488))),
          ],
        ),

      ),
      body: _isFullscreen
        ? Stack(
            children: [
              Center(child: AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPlayer())),
              Positioned(
                top: 8, left: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 30),
                    onPressed: _toggleFullscreen,
                  ),
                ),
              ),
            ],
          )
        : isWide
          ? _buildWideLayout(ep, filteredEmbeds, anime)
          : _buildNarrowLayout(ep, filteredEmbeds, anime),
    );
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
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) {
        _showBigPlay = false;
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isDragging) setState(() => _controlsVisible = false);
    });
  }

  void _togglePlayPause() {
    final ps = _player.playbackState.value;
    if (ps == VideoControllerPlaybackState.playing) {
      _player.pause();
      setState(() {
        _showBigPlay = true;
        _controlsVisible = true;
      });
      _hideTimer?.cancel();
    } else {
      _player.play();
      setState(() => _showBigPlay = false);
      _startHideTimer();
    }
  }

  // ── Video player with overlay controls ──

  Widget _buildVideoPlayer() {
    final duration = _player.mediaInfo.value?.duration ?? 0;
    final position = _player.position.value;
    final isPlaying = _player.playbackState.value == VideoControllerPlaybackState.playing;

    return GestureDetector(
      onTap: _toggleControls,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Video surface
            VideoView(controller: _player),

            // Loading spinner
            if (_player.loading.value && !_player.loading.value)
              const CircularProgressIndicator(color: Color(0xFF8b5cf6)),

            // Big center play/pause (when paused)
            if (_showBigPlay || (!isPlaying && !_player.loading.value))
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white, size: 40,
                  ),
                ),
              ),

            // Bottom controls bar
            if (_controlsVisible)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Seek slider
                        if (duration > 0)
                          SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: const Color(0xFF8b5cf6),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: const Color(0xFF8b5cf6),
                              overlayColor: const Color(0xFF8b5cf6).withValues(alpha: 0.2),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              min: 0,
                              max: duration.toDouble(),
                              value: position.clamp(0, duration).toDouble(),
                              onChangeStart: (v) {
                                _isDragging = true;
                                _hideTimer?.cancel();
                              },
                              onChanged: (v) => setState(() {}),
                              onChangeEnd: (v) {
                                _player.seekTo(v.toInt());
                                _isDragging = false;
                                _startHideTimer();
                              },
                            ),
                          ),
                        // Bottom row: play/pause, time, fullscreen
                        Row(
                          children: [
                            // Play/pause button
                            GestureDetector(
                              onTap: _togglePlayPause,
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white, size: 28,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Time labels
                            Text(
                              '${_formatTime(position)} / ${_formatTime(duration)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const Spacer(),
                            // Fullscreen button
                            GestureDetector(
                              onTap: _toggleFullscreen,
                              child: Icon(
                                _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                color: Colors.white, size: 24,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
