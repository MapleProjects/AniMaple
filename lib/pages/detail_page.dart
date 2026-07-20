import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../widgets/error_dialog.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
      final watched = history
          .where((h) => h.animeSlug == widget.slug)
          .map((h) => h.episodeNumber)
          .toSet();
      if (mounted) {
      setState(() {
        _anime = anime;
        _followed = followed.any((f) => f.animeId == anime.id);
        _watchedEpisodes = watched;
        _loading = false;
      });
      }
      return;
    } catch (e, st) {
      debugPrint('DETAIL RETRY attempt=$attempt slug=${widget.slug} ERROR: $e');
      debugPrint('DETAIL STACKTRACE: $st');
      if (attempt == 0 && mounted) showErrorSheet(context, e, st, slug: widget.slug);
      await Future.delayed(const Duration(seconds: 3));
    }
    }
    // All retries failed — show error
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero with backdrop
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (anime.backdrop != null)
                    Image.network(anime.backdrop!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                  else
                    Container(color: const Color(0xFF110e1a)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xFF0a0812)]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + poster row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (anime.poster != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(anime.poster!, width: 100, height: 150, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(anime.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFe8e4f0))),
                            if (anime.aka != null) ...[
                              const SizedBox(height: 4),
                              Text(anime.aka!, style: const TextStyle(fontSize: 13, color: Color(0xFF6d6488))),
                            ],
                            const SizedBox(height: 8),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              _chip(anime.category, const Color(0xFF8b5cf6)),
                              _chip(anime.status, anime.status.contains('Finalizado') ? const Color(0xFF22c55e) : const Color(0xFFf59e0b)),
                              _chip('${anime.episodesCount} eps', const Color(0xFF3b82f6)),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (anime.episodes.isNotEmpty) {
                            _playEpisode(anime, anime.episodes.last.number);
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Reproducir'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8b5cf6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _toggleFollow,
                      icon: Icon(_followed ? Icons.favorite : Icons.favorite_border, color: _followed ? const Color(0xFFef4444) : const Color(0xFF6d6488)),
                      label: Text(_followed ? 'Siguiendo' : 'Mi lista', style: TextStyle(color: _followed ? const Color(0xFFef4444) : const Color(0xFF6d6488))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1e1832)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  // Genres
                  if (anime.genres.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: anime.genres.map((g) => _chip(g.name, const Color(0xFF3b82f6))).toList()),
                  const SizedBox(height: 16),
                  // Synopsis
                  Text(anime.synopsis, style: const TextStyle(fontSize: 14, color: Color(0xFFa99fc0), height: 1.5)),
                  const SizedBox(height: 24),
                  // Episodes
                  Text('Episodios (${anime.episodesCount})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFe8e4f0))),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // Episode grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  return InkWell(
                    onTap: () => _playEpisode(anime, ep.number),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF110e1a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isWatched
                              ? const Color(0xFF8b5cf6)
                              : const Color(0xFF1e1832),
                          width: isWatched ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text('${ep.number}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFe8e4f0))),
                          if (isWatched)
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
    );
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
      final watched = history
          .where((h) => h.animeSlug == widget.slug)
          .map((h) => h.episodeNumber)
          .toSet();
      if (mounted) setState(() => _watchedEpisodes = watched);
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
