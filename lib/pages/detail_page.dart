import 'dart:ui';
import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/tv_service.dart';
import '../widgets/download_sheet.dart';
import '../widgets/error_dialog.dart';
import '../widgets/tv_focusable.dart';
import 'episode_page.dart';

class DetailPage extends StatefulWidget {
  final String slug;
  const DetailPage({super.key, required this.slug});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  AnimeDetail? _anime;
  bool _loading = true;
  bool _followed = false;
  Set<int> _watchedEpisodes = {};
  int? _lastWatchedEpisode;
  final DownloadService _dl = DownloadService.instance;

  @override
  void initState() {
    super.initState();
    _load();
    _dl.version.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    _dl.version.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    const maxRetries = 10;
    for (var attempt = 0; attempt < maxRetries && mounted; attempt++) {
    try {
      debugPrint('DETAIL LOAD attempt=$attempt slug=${widget.slug}');
      final anime = await ApiService.fetchAnimeDetail(widget.slug);
      debugPrint('DETAIL LOAD fetchAnimeDetail OK: ${anime.title}');
      final followed = await ApiService.fetchFollowed();
      debugPrint('DETAIL LOAD fetchFollowed OK: ${followed.length} entries');
      final history = await ApiService.fetchHistory();
      debugPrint('DETAIL LOAD fetchHistory OK: ${history.length} entries');
      final animeHistory = history
          .where((h) => h.animeSlug == widget.slug)
          .toList();
      final watched = animeHistory.map((h) => h.episodeNumber).toSet();
      int? lastWatched;
      if (animeHistory.isNotEmpty) {
        animeHistory.sort((a, b) {
          final da = DateTime.tryParse(a.watchedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = DateTime.tryParse(b.watchedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        lastWatched = animeHistory.first.episodeNumber;
      }
      if (mounted) {
      setState(() {
        _anime = anime;
        _followed = followed.any((f) => f.animeId == anime.id);
        _watchedEpisodes = watched;
        _lastWatchedEpisode = lastWatched;
        _loading = false;
      });
      }
      return;
    } catch (e, st) {
      debugPrint('DETAIL RETRY attempt=$attempt slug=${widget.slug} ERROR: $e');
      debugPrint('DETAIL STACKTRACE: $st');
      if (attempt == 0 &&
          mounted &&
          !isConnectivityError(e)) {
        showErrorSheet(context, e, st, slug: widget.slug);
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    }
    if (mounted) setState(() { _loading = false; });
  }

  Future<void> _toggleFollow() async {
    if (_anime == null) return;
    final result = await ApiService.toggleFollow(_anime!.id, _anime!.title, _anime!.slug);
    setState(() => _followed = result);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6))));
    }
    final anime = _anime;
    if (anime == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFef4444), size: 48),
              const SizedBox(height: 16),
              const Text('No se pudo cargar el anime', style: TextStyle(color: Color(0xFFe8e4f0), fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Slug: ${widget.slug}', style: const TextStyle(color: Color(0xFF6d6488), fontSize: 12)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () { setState(() { _loading = true; }); _load(); },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8b5cf6), foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final isWide = TvService.isTvMode || MediaQuery.sizeOf(context).width > 760;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0812),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo ambiental decorativo: backdrop o póster desenfocado para evitar espacios vacíos.
          if (anime.backdrop != null)
            Opacity(
              opacity: 0.22,
              child: Image.network(
                anime.backdrop!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            )
          else if (anime.poster != null)
            Opacity(
              opacity: 0.16,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Image.network(
                  anime.poster!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x990a0812),
                  Color(0xCC0a0812),
                  Color(0xFF0a0812),
                ],
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              if (!isWide && anime.backdrop != null)
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  backgroundColor: const Color(0xFF0a0812),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          anime.backdrop!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xFF0a0812)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverAppBar(
                  pinned: false,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: const BackButton(color: Color(0xFFe8e4f0)),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 28 : 16,
                    vertical: isWide ? 8 : 12,
                  ),
                  child: isWide
                      ? _buildWideHeader(anime)
                      : _buildMobileHeader(anime),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isWide ? 28 : 16,
                    right: isWide ? 28 : 16,
                    top: 12,
                    bottom: 8,
                  ),
                  child: Text(
                    'Episodios (${anime.episodesCount})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFe8e4f0),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isWide ? 28 : 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 80,
                    childAspectRatio: 1,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final ep = anime.episodes[i];
                      final isWatched = _watchedEpisodes.contains(ep.number);
                      final isDownloaded = _dl.isDownloaded(anime.slug, ep.number);
                      final isQueued = _dl.isQueued(anime.slug, ep.number);
                      final epProgress =
                          _dl.progress.value['${anime.slug}#${ep.number}'];
                      return TvFocusable(
                        onTap: () => _playEpisode(anime, ep.number),
                        borderRadius: BorderRadius.circular(8),
                        scaleOnFocus: 1.10,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF110e1a),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isQueued
                                  ? const Color(0xFFf59e0b)
                                  : isDownloaded
                                      ? const Color(0xFF22c55e)
                                      : isWatched
                                          ? const Color(0xFF8b5cf6)
                                          : const Color(0xFF1e1832),
                              width: isWatched || isDownloaded || isQueued ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text('${ep.number}', style: TextStyle(fontWeight: FontWeight.w700, color: isDownloaded ? const Color(0xFF22c55e) : const Color(0xFFe8e4f0))),
                              if (isWatched && !isDownloaded)
                                Positioned(
                                  top: 2, right: 2,
                                  child: Container(
                                    width: 8, height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF8b5cf6),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              if (isWatched && isDownloaded)
                                Positioned(
                                  top: 2, right: 2,
                                  child: Container(width: 8, height: 8,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8b5cf6),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFF0a0812), width: 1.5),
                                    ),
                                  ),
                                ),
                              if (isDownloaded && !isQueued)
                                Positioned(
                                  bottom: 2, left: 2,
                                  child: Icon(Icons.download_done_rounded,
                                      size: 11, color: const Color(0xFF22c55e)),
                                ),
                              if (isQueued)
                                Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: CircularProgressIndicator(
                                    value: (epProgress != null && epProgress > 0 && epProgress <= 1)
                                        ? epProgress
                                        : null,
                                    strokeWidth: 2,
                                    color: const Color(0xFFf59e0b),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: anime.episodes.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWideHeader(AnimeDetail anime) {
    final hasEpisodes = anime.episodes.isNotEmpty;
    final hasHistory = _lastWatchedEpisode != null &&
        anime.episodes.any((e) => e.number == _lastWatchedEpisode);
    final targetEpisode = hasHistory
        ? _lastWatchedEpisode!
        : (hasEpisodes ? anime.episodes.first.number : 1);
    final playLabel = hasHistory
        ? 'Continuar Ep. $_lastWatchedEpisode'
        : 'Reproducir';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (anime.poster != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF2a2240)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.network(
                anime.poster!,
                width: 150,
                height: 225,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                anime.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFe8e4f0),
                ),
              ),
              if (anime.aka != null) ...[
                const SizedBox(height: 4),
                Text(
                  anime.aka!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8b82a3),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(anime.category, const Color(0xFF8b5cf6)),
                  _chip(
                    anime.status,
                    anime.status.contains('Finalizado')
                        ? const Color(0xFF22c55e)
                        : const Color(0xFFf59e0b),
                  ),
                  _chip('${anime.episodesCount} eps', const Color(0xFF3b82f6)),
                  ...anime.genres.map((g) => _chip(g.name, const Color(0xFF6366f1))),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                anime.synopsis,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFFb4abc9),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  TvFocusable(
                    onTap: hasEpisodes
                        ? () => _playEpisode(anime, targetEpisode)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    scaleOnFocus: 1.05,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8b5cf6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            playLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TvFocusable(
                    onTap: _toggleFollow,
                    borderRadius: BorderRadius.circular(8),
                    scaleOnFocus: 1.05,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131022),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _followed
                              ? const Color(0xFFef4444)
                              : const Color(0xFF2a2240),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _followed
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: _followed
                                ? const Color(0xFFef4444)
                                : const Color(0xFFa78bfa),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _followed ? 'Siguiendo' : 'Mi lista',
                            style: TextStyle(
                              color: _followed
                                  ? const Color(0xFFef4444)
                                  : const Color(0xFFe8e4f0),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TvFocusable(
                    onTap: () => DownloadSheet.show(context, anime),
                    borderRadius: BorderRadius.circular(8),
                    scaleOnFocus: 1.05,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131022),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2a2240)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.download_rounded,
                            color: Color(0xFFa78bfa),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _downloadLabel(anime.slug),
                            style: const TextStyle(
                              color: Color(0xFFa78bfa),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileHeader(AnimeDetail anime) {
    final hasEpisodes = anime.episodes.isNotEmpty;
    final hasHistory = _lastWatchedEpisode != null &&
        anime.episodes.any((e) => e.number == _lastWatchedEpisode);
    final targetEpisode = hasHistory
        ? _lastWatchedEpisode!
        : (hasEpisodes ? anime.episodes.first.number : 1);
    final playLabel = hasHistory
        ? 'Continuar Ep. $_lastWatchedEpisode'
        : 'Reproducir';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (anime.poster != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  anime.poster!,
                  width: 100,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anime.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFe8e4f0),
                    ),
                  ),
                  if (anime.aka != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      anime.aka!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6d6488),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(anime.category, const Color(0xFF8b5cf6)),
                      _chip(
                        anime.status,
                        anime.status.contains('Finalizado')
                            ? const Color(0xFF22c55e)
                            : const Color(0xFFf59e0b),
                      ),
                      _chip('${anime.episodesCount} eps', const Color(0xFF3b82f6)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TvFocusable(
                onTap: hasEpisodes
                    ? () => _playEpisode(anime, targetEpisode)
                    : null,
                borderRadius: BorderRadius.circular(8),
                scaleOnFocus: 1.05,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8b5cf6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        playLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TvFocusable(
              onTap: _toggleFollow,
              borderRadius: BorderRadius.circular(8),
              scaleOnFocus: 1.05,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF131022),
                  border: Border.all(
                    color: _followed
                        ? const Color(0xFFef4444)
                        : const Color(0xFF2a2240),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _followed
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _followed
                          ? const Color(0xFFef4444)
                          : const Color(0xFFa78bfa),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _followed ? 'Siguiendo' : 'Mi lista',
                      style: TextStyle(
                        color: _followed
                            ? const Color(0xFFef4444)
                            : const Color(0xFFe8e4f0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TvFocusable(
          onTap: () => DownloadSheet.show(context, anime),
          borderRadius: BorderRadius.circular(8),
          scaleOnFocus: 1.05,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFF131022),
              border: Border.all(color: const Color(0xFF2a2240)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.download_rounded,
                  color: Color(0xFFa78bfa),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  _downloadLabel(anime.slug),
                  style: const TextStyle(
                    color: Color(0xFFa78bfa),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (anime.genres.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: anime.genres.map((g) => _chip(g.name, const Color(0xFF3b82f6))).toList(),
          ),
        const SizedBox(height: 14),
        Text(
          anime.synopsis,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFFa99fc0),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Etiqueta del botón de descargas según estado del anime.
  String _downloadLabel(String slug) {
    final n = _dl.downloadedEpisodes(slug).length;
    if (_dl.isQueued(slug, -1) || _dl.progress.value.keys.any((k) => k.startsWith('$slug#'))) {
      if (n == 0) return 'Descargando…';
    }
    if (n > 0) return 'Descargas ($n)';
    return 'Descargar';
  }

  void _playEpisode(AnimeDetail anime, int episodeNumber) {
    ApiService.addHistory(anime.id, anime.slug, anime.title, episodeNumber);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => EpisodePage(
        animeSlug: anime.slug,
        episodeNumber: episodeNumber,
        animeTitle: anime.title,
      ),
    )).then((_) => _refreshWatched());
  }

  Future<void> _refreshWatched() async {
    try {
      final history = await ApiService.fetchHistory();
      final animeHistory = history
          .where((h) => h.animeSlug == widget.slug)
          .toList();
      final watched = animeHistory.map((h) => h.episodeNumber).toSet();
      int? lastWatched;
      if (animeHistory.isNotEmpty) {
        animeHistory.sort((a, b) {
          final da = DateTime.tryParse(a.watchedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = DateTime.tryParse(b.watchedAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        lastWatched = animeHistory.first.episodeNumber;
      }
      if (mounted) {
        setState(() {
          _watchedEpisodes = watched;
          _lastWatchedEpisode = lastWatched;
        });
      }
    } catch (_) {}
  }

  static Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
