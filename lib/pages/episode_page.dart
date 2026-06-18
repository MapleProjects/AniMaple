import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
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
  bool _loading = true;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;
  bool _videoError = false;
  String? _activeServer;
  String _activeVariant = 'SUB';
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ep = await ApiService.fetchEpisodeDetail(widget.animeSlug, widget.episodeNumber);
      setState(() {
        _episode = ep;
        _loading = false;
        // Default to DUB if available
        _activeVariant = ep.variants.contains('DUB') ? 'DUB' : (ep.variants.isNotEmpty ? ep.variants.first : 'DUB');
      });
      _autoPlay();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _autoPlay() {
    final ep = _episode;
    if (ep == null) return;
    final filtered = ep.embeds.where((s) => s.variant == _activeVariant).toList();
    // Prefer HLS first, then mp4upload
    final hls = filtered.where((s) => s.server.toLowerCase().contains('hls')).toList();
    if (hls.isNotEmpty) {
      _playServer(hls.first);
      return;
    }
    final mp4 = filtered.where((s) => s.server.toLowerCase().contains('mp4')).toList();
    if (mp4.isNotEmpty) {
      _playServer(mp4.first);
    } else if (filtered.isNotEmpty) {
      _playServer(filtered.first);
    }
  }

  Future<void> _playServer(ServerMirror server) async {
    _videoCtrl?.dispose();
    setState(() { _videoReady = false; _videoError = false; _activeServer = server.server; });

    try {
      // Get direct video URL
      final data = await ApiService.fetchVideoUrl(server.url);
      final videoUrl = data['url'] as String?;
      final videoType = data['type'] as String? ?? 'mp4';

      if (videoUrl == null || videoUrl.isEmpty) {
        setState(() => _videoError = true);
        return;
      }

      VideoPlayerController ctrl;

      if (videoType == 'hls') {
        // HLS: load directly (m3u8 has absolute URLs for segments)
        ctrl = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      } else {
        // MP4: use proxy to add Referer header
        final proxyUrl = '${ApiService.baseUrl}/api/proxy-video?url=${Uri.encodeComponent(videoUrl)}';
        ctrl = VideoPlayerController.networkUrl(Uri.parse(proxyUrl));
      }

      await ctrl.initialize();

      if (!mounted) { ctrl.dispose(); return; }

      setState(() { _videoCtrl = ctrl; _videoReady = true; });
      ctrl.play();

      ctrl.addListener(() {
        if (ctrl.value.hasError && mounted) {
          setState(() => _videoError = true);
        }
      });
    } catch (e) {
      debugPrint('Video error: $e');
      if (mounted) setState(() => _videoError = true);
    }
  }

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

    final filteredEmbeds = ep.embeds.where((s) => s.variant == _activeVariant).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0a0812),
      appBar: AppBar(
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
        actions: [
          // Fullscreen button
          IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
      body: Column(
        children: [
          // Video player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _videoReady && _videoCtrl != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_videoCtrl!),
                      _VideoControls(controller: _videoCtrl!),
                    ],
                  )
                : _videoError
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 40),
                          const SizedBox(height: 8),
                          const Text('Error cargando video', style: TextStyle(color: Color(0xFFef4444))),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _autoPlay,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8b5cf6)),
                            child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    )
                  : const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6))),
            ),
          ),
          // Variant selector (Doblaje / Subtitulado)
          if (ep.variants.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        onSelected: (_) {
                          setState(() => _activeVariant = v);
                          _autoPlay();
                        },
                        selectedColor: const Color(0xFF8b5cf6),
                        backgroundColor: const Color(0xFF110e1a),
                        labelStyle: TextStyle(
                          color: isActive ? Colors.white : const Color(0xFFa99fc0),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        side: const BorderSide(color: Color(0xFF1e1832)),
                      ),
                    );
                  }),
                ],
              ),
            ),
          // Server buttons
          if (filteredEmbeds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, color: Color(0xFF6d6488), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: filteredEmbeds.map((s) {
                        final isActive = _activeServer == s.server;
                        return ChoiceChip(
                          label: Text(s.server),
                          selected: isActive,
                          onSelected: (_) => _playServer(s),
                          selectedColor: const Color(0xFF8b5cf6),
                          backgroundColor: const Color(0xFF110e1a),
                          labelStyle: TextStyle(
                            color: isActive ? Colors.white : const Color(0xFFa99fc0),
                            fontWeight: FontWeight.w600,
                          ),
                          side: const BorderSide(color: Color(0xFF1e1832)),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),
          // Episode navigation
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: ep.number > 1
                      ? () {
                          _videoCtrl?.dispose();
                          Navigator.pushReplacement(context, MaterialPageRoute(
                            builder: (_) => EpisodePage(
                              animeSlug: widget.animeSlug,
                              episodeNumber: ep.number - 1,
                              animeTitle: widget.animeTitle,
                            ),
                          ));
                        }
                      : null,
                    icon: const Icon(Icons.skip_previous, size: 18),
                    label: const Text('Anterior'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFa99fc0),
                      side: const BorderSide(color: Color(0xFF1e1832)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _videoCtrl?.dispose();
                      Navigator.pushReplacement(context, MaterialPageRoute(
                        builder: (_) => EpisodePage(
                          animeSlug: widget.animeSlug,
                          episodeNumber: ep.number + 1,
                          animeTitle: widget.animeTitle,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Siguiente'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8b5cf6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoControls({required this.controller});

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _visible = !_visible),
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          color: Colors.black38,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      widget.controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 40,
                    ),
                    onPressed: () {
                      setState(() {
                        widget.controller.value.isPlaying
                          ? widget.controller.pause()
                          : widget.controller.play();
                      });
                    },
                  ),
                ],
              ),
              VideoProgressIndicator(
                widget.controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFF8b5cf6),
                  bufferedColor: Color(0xFF2a2240),
                  backgroundColor: Color(0xFF1e1832),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Text(_formatDuration(widget.controller.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                    const Text(' / ', style: TextStyle(color: Color(0xFF6d6488), fontSize: 12)),
                    Text(_formatDuration(widget.controller.value.duration),
                      style: const TextStyle(color: Color(0xFF6d6488), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
