import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
  bool _videoReady = false;
  bool _videoError = false;
  String? _activeServer;
  String _activeVariant = 'DUB';
  bool _isFullscreen = false;

  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.playing.listen((_) { if (mounted) setState(() {}); });
    _player.stream.duration.listen((_) { if (mounted) setState(() {}); });
    _player.stream.position.listen((_) { if (mounted) setState(() {}); });
    _player.stream.buffer.listen((_) { if (mounted) setState(() {}); });
    _player.stream.error.listen((err) {
      debugPrint('MEDIA_KIT ERROR: $err');
      if (mounted && err.isNotEmpty) setState(() => _videoError = true);
    });
    _load();
  }

  @override
  void dispose() {
    _player.dispose();
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ep = await ApiService.fetchEpisodeDetail(widget.animeSlug, widget.episodeNumber);
      AnimeDetail? detail;
      try { detail = await ApiService.fetchAnimeDetail(widget.animeSlug); } catch (_) {}
      setState(() {
        _episode = ep;
        _animeDetail = detail;
        _loading = false;
        _activeVariant = ep.variants.contains('DUB') ? 'DUB' : (ep.variants.isNotEmpty ? ep.variants.first : 'DUB');
      });
      // Register in history
      if (detail != null) {
        ApiService.addHistory(detail.id, detail.slug, detail.title, ep.number);
      }
      _autoPlay();
    } catch (e) {
      debugPrint('LOAD ERROR: $e');
      setState(() => _loading = false);
    }
  }

  void _autoPlay() {
    final ep = _episode;
    if (ep == null) return;
    final filtered = ep.embeds.where((s) => s.variant == _activeVariant).toList();
    final hls = filtered.where((s) => s.server.toLowerCase().contains('hls')).toList();
    if (hls.isNotEmpty) { _playServer(hls.first); return; }
    final mp4 = filtered.where((s) => s.server.toLowerCase().contains('mp4')).toList();
    if (mp4.isNotEmpty) { _playServer(mp4.first); return; }
    if (filtered.isNotEmpty) { _playServer(filtered.first); }
  }

  Future<void> _playServer(ServerMirror server) async {
    setState(() { _videoReady = false; _videoError = false; _activeServer = server.server; });

    try {
      debugPrint('PLAY SERVER: ${server.server} → ${server.url}');
      final data = await ApiService.fetchVideoUrl(server.url);
      final videoUrl = data['url'] as String?;
      final videoType = data['type'] as String? ?? 'mp4';

      debugPrint('VIDEO URL: $videoUrl (type: $videoType)');

      if (videoUrl == null || videoUrl.isEmpty) {
        setState(() => _videoError = true);
        return;
      }

      String playUrl;
      if (videoType == 'hls') {
        playUrl = videoUrl;
      } else {
        playUrl = '${ApiService.baseUrl}/api/proxy-video?url=${Uri.encodeComponent(videoUrl)}';
      }

      debugPrint('PLAYING: $playUrl');
      await _player.open(Media(playUrl));
      if (mounted) setState(() => _videoReady = true);
    } catch (e, st) {
      debugPrint('PLAY ERROR: $e\n$st');
      if (mounted) setState(() => _videoError = true);
    }
  }

  void _retry() {
    // Retry the current server without resetting variant/server selection
    final ep = _episode;
    if (ep == null) return;
    final currentServer = _activeServer;
    if (currentServer != null) {
      final server = ep.embeds.where((s) => s.server == currentServer && s.variant == _activeVariant).firstOrNull;
      if (server != null) {
        _playServer(server);
        return;
      }
    }
    // Fallback: auto-select if no current server
    _autoPlay();
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

    final filteredEmbeds = ep.embeds.where((s) =>
      s.variant == _activeVariant &&
      (s.server.toLowerCase().contains('hls') || s.server.toLowerCase().contains('mp4'))
    ).toList();
    final anime = _animeDetail;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 900;

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
          IconButton(
            icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
      body: isWide
        ? _buildWideLayout(ep, filteredEmbeds, anime)
        : _buildNarrowLayout(ep, filteredEmbeds, anime),
    );
  }

  // ── Wide layout: video left, info right ──
  Widget _buildWideLayout(EpisodeDetail ep, List<ServerMirror> filteredEmbeds, AnimeDetail? anime) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: video + controls
        Expanded(
          flex: 3,
          child: Column(
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPlayer()),
              if (_videoReady) _buildPlaybar(),
              _buildVariantAndServers(ep, filteredEmbeds),
            ],
          ),
        ),
        // Right: info + episodes
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

  // ── Narrow layout: video top, info bottom ──
  Widget _buildNarrowLayout(EpisodeDetail ep, List<ServerMirror> filteredEmbeds, AnimeDetail? anime) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _buildVideoPlayer()),
          if (_videoReady) _buildPlaybar(),
          _buildVariantAndServers(ep, filteredEmbeds),
          Padding(padding: const EdgeInsets.all(16), child: _buildInfoSection(ep, anime)),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Container(
      color: Colors.black,
      child: _videoReady
        ? Video(controller: _controller)
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
                    onPressed: _retry,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8b5cf6)),
                    child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6))),
    );
  }

  Widget _buildPlaybar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_player.state.playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
            onPressed: () => _player.playOrPause(),
          ),
          Expanded(
            child: Slider(
              value: _player.state.position.inSeconds.toDouble().clamp(0, _player.state.duration.inSeconds.toDouble().clamp(1, double.infinity)),
              max: _player.state.duration.inSeconds.toDouble().clamp(1, double.infinity),
              activeColor: const Color(0xFF8b5cf6),
              inactiveColor: const Color(0xFF1e1832),
              onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
            ),
          ),
          Text('${_fmt(_player.state.position)} / ${_fmt(_player.state.duration)}',
            style: const TextStyle(color: Color(0xFFa99fc0), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildVariantAndServers(EpisodeDetail ep, List<ServerMirror> filteredEmbeds) {
    return Column(
      children: [
        // Variant selector
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
                      onSelected: (_) { setState(() => _activeVariant = v); _retry(); },
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
        // Server buttons
        if (filteredEmbeds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
        // Title
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Text(widget.animeTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFe8e4f0))),
        ),
        const SizedBox(height: 4),
        Text('Episodio ${ep.number}', style: const TextStyle(fontSize: 14, color: Color(0xFF6d6488))),
        // Meta
        if (anime != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(anime.category, const Color(0xFF8b5cf6)),
            _chip(anime.status, const Color(0xFF22c55e)),
            ...anime.genres.map((g) => _chip(g.name, const Color(0xFF3b82f6))),
          ]),
        ],
        // Synopsis
        if (anime != null && anime.synopsis.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(anime.synopsis, style: const TextStyle(fontSize: 14, color: Color(0xFFa99fc0), height: 1.5)),
        ],
        // Episode grid
        if (anime != null && anime.episodes.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Episodios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFe8e4f0))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: anime.episodes.map((e) {
            final isCurrent = e.number == ep.number;
            return GestureDetector(
              onTap: () {
                if (!isCurrent) {
                  Navigator.pushReplacement(context, MaterialPageRoute(
                    builder: (_) => EpisodePage(animeSlug: widget.animeSlug, episodeNumber: e.number, animeTitle: widget.animeTitle),
                  ));
                }
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

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
