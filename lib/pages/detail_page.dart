import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/tv_service.dart';
import '../ui/tokens.dart';
import '../ui/widgets/ambient_backdrop.dart';
import '../ui/widgets/cover_palette.dart';
import '../ui/widgets/pill_badge.dart';
import '../ui/widgets/section_header.dart';
import '../ui/widgets/skeletons.dart';
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
  CoverPalette _palette = CoverPalette.fallback;
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
            final da =
                DateTime.tryParse(a.watchedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final db =
                DateTime.tryParse(b.watchedAt) ??
                DateTime.fromMillisecondsSinceEpoch(0);
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
          // Paleta para el fundido del banner; no bloquea la carga.
          CoverPaletteStore.of(anime.poster).then((p) {
            if (mounted) setState(() => _palette = p);
          });
        }
        return;
      } catch (e, st) {
        debugPrint(
          'DETAIL RETRY attempt=$attempt slug=${widget.slug} ERROR: $e',
        );
        debugPrint('DETAIL STACKTRACE: $st');
        if (attempt == 0 && mounted && !isConnectivityError(e)) {
          showErrorSheet(context, e, st, slug: widget.slug);
        }
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_anime == null) return;
    final wasFollowing = _followed;
    // Actualización optimista: el botón responde al instante.
    setState(() => _followed = !wasFollowing);
    try {
      final result = await ApiService.toggleFollow(
        _anime!.id,
        _anime!.title,
        _anime!.slug,
      );
      if (!mounted) return;
      setState(() => _followed = result);
    } catch (_) {
      if (mounted) setState(() => _followed = wasFollowing);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.page),
            child: SkeletonScope(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SkeletonBox(
                        width: 104,
                        height: 156,
                        radius: AppRadius.sm,
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBox(height: 22, radius: AppRadius.xs),
                            SizedBox(height: AppSpace.sm),
                            SkeletonBox(width: 140, height: 12),
                            SizedBox(height: AppSpace.lg),
                            SkeletonBox(height: 12),
                            SizedBox(height: AppSpace.sm),
                            SkeletonBox(height: 12),
                            SizedBox(height: AppSpace.sm),
                            SkeletonBox(width: 200, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xl),
                  const SkeletonBox(
                    width: 150,
                    height: 18,
                    radius: AppRadius.xs,
                  ),
                  const SizedBox(height: AppSpace.md),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 72,
                          childAspectRatio: 1,
                          crossAxisSpacing: AppSpace.sm,
                          mainAxisSpacing: AppSpace.sm,
                        ),
                    itemCount: 12,
                    itemBuilder: (_, __) =>
                        const SkeletonBox(radius: AppRadius.sm),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final anime = _anime;
    if (anime == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.danger,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'No se pudo cargar el anime',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Slug: ${widget.slug}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                  });
                  _load();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isWide = TvService.isTvMode || MediaQuery.sizeOf(context).width > 760;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo ambiental: portada decodificada a baja resolución, sin blur GPU.
          AmbientBackdrop(
            imageUrl: anime.backdrop ?? anime.poster,
            fallbackUrl: anime.poster,
            opacity: 0.85,
          ),
          CustomScrollView(
            slivers: [
              if (!isWide && (anime.backdrop != null || anime.poster != null))
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: (anime.backdrop ?? anime.poster)!,
                          fit: BoxFit.cover,
                          memCacheWidth: 1080,
                          filterQuality: FilterQuality.medium,
                          fadeInDuration: AppMotion.slow,
                          placeholder: (_, __) =>
                              const ColoredBox(color: AppColors.surfaceHigh),
                          errorWidget: (_, __, ___) {
                            final poster = anime.poster;
                            if (poster == null || poster == anime.backdrop) {
                              return const ColoredBox(
                                color: AppColors.surfaceHigh,
                              );
                            }
                            return CachedNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              memCacheWidth: 1080,
                              filterQuality: FilterQuality.medium,
                              placeholder: (_, __) => const ColoredBox(
                                color: AppColors.surfaceHigh,
                              ),
                              errorWidget: (_, __, ___) => const ColoredBox(
                                color: AppColors.surfaceHigh,
                              ),
                            );
                          },
                        ),
                        // Fundido hacia el color ambiental: evita el corte recto
                        // entre el banner y el cuerpo sin usar ShaderMask.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.bg.withValues(alpha: 0.50),
                                AppColors.bg.withValues(alpha: 0.0),
                                AppColors.bg.withValues(alpha: 0.0),
                                _seamColor,
                              ],
                              stops: const [0.0, 0.16, 0.42, 1.0],
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
                  leading: const BackButton(color: AppColors.text),
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
                child: SectionHeader(
                  title: 'Episodios',
                  kicker: '${anime.episodesCount} capítulos',
                  padding: EdgeInsets.fromLTRB(
                    isWide ? AppSpace.xxl : AppSpace.page,
                    AppSpace.lg,
                    isWide ? AppSpace.xxl : AppSpace.page,
                    AppSpace.sm,
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
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final ep = anime.episodes[i];
                    final isWatched = _watchedEpisodes.contains(ep.number);
                    final isDownloaded = _dl.isDownloaded(
                      anime.slug,
                      ep.number,
                    );
                    final isQueued = _dl.isQueued(anime.slug, ep.number);
                    final epProgress =
                        _dl.progress.value['${anime.slug}#${ep.number}'];
                    return TvFocusable(
                      onTap: () => _playEpisode(anime, ep.number),
                      borderRadius: BorderRadius.circular(8),
                      scaleOnFocus: 1.10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isQueued
                                ? AppColors.warning
                                : isDownloaded
                                ? AppColors.success
                                : isWatched
                                ? AppColors.primary
                                : AppColors.outline,
                            width: isWatched || isDownloaded || isQueued
                                ? 2
                                : 1,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Text(
                              '${ep.number}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isDownloaded
                                    ? AppColors.success
                                    : AppColors.text,
                              ),
                            ),
                            if (isWatched && !isDownloaded)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            if (isWatched && isDownloaded)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.bg,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            if (isDownloaded && !isQueued)
                              Positioned(
                                bottom: 2,
                                left: 2,
                                child: Icon(
                                  Icons.download_done_rounded,
                                  size: 11,
                                  color: AppColors.success,
                                ),
                              ),
                            if (isQueued)
                              Padding(
                                padding: const EdgeInsets.all(7),
                                child: CircularProgressIndicator(
                                  value:
                                      (epProgress != null &&
                                          epProgress > 0 &&
                                          epProgress <= 1)
                                      ? epProgress
                                      : null,
                                  strokeWidth: 2,
                                  color: AppColors.warning,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: anime.episodes.length),
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
    final hasHistory =
        _lastWatchedEpisode != null &&
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
                border: Border.all(color: AppColors.surfaceHighest),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CachedNetworkImage(
                imageUrl: anime.poster!,
                width: 150,
                height: 225,
                fit: BoxFit.cover,
                memCacheWidth: 450,
                fadeInDuration: AppMotion.slow,
                placeholder: (_, __) =>
                    const ColoredBox(color: AppColors.surfaceHigh),
                errorWidget: (_, __, ___) => const SizedBox(),
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
                  color: AppColors.text,
                ),
              ),
              if (anime.aka != null) ...[
                const SizedBox(height: 4),
                Text(
                  anime.aka!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(anime.category, AppColors.primary),
                  _chip(
                    anime.status,
                    anime.status.contains('Finalizado')
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  _chip('${anime.episodesCount} eps', AppColors.info),
                  ...anime.genres.map((g) => _chip(g.name, AppColors.primary)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                anime.synopsis,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
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
                        color: AppColors.primary,
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
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _followed
                              ? AppColors.danger
                              : AppColors.surfaceHighest,
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
                                ? AppColors.danger
                                : AppColors.primaryBright,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _followed ? 'Siguiendo' : 'Mi lista',
                            style: TextStyle(
                              color: _followed
                                  ? AppColors.danger
                                  : AppColors.text,
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
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.surfaceHighest),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.download_rounded,
                            color: AppColors.primaryBright,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _downloadLabel(anime.slug),
                            style: const TextStyle(
                              color: AppColors.primaryBright,
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
    final hasHistory =
        _lastWatchedEpisode != null &&
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
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: CachedNetworkImage(
                  imageUrl: anime.poster!,
                  width: 104,
                  height: 156,
                  fit: BoxFit.cover,
                  memCacheWidth: 312,
                  fadeInDuration: AppMotion.slow,
                  placeholder: (_, __) =>
                      const ColoredBox(color: AppColors.surfaceHigh),
                  errorWidget: (_, __, ___) => const SizedBox(),
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
                      color: AppColors.text,
                    ),
                  ),
                  if (anime.aka != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      anime.aka!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _chip(anime.category, AppColors.primary),
                      _chip(
                        anime.status,
                        anime.status.contains('Finalizado')
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      _chip('${anime.episodesCount} eps', AppColors.info),
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
                    color: AppColors.primary,
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
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(
                    color: _followed
                        ? AppColors.danger
                        : AppColors.surfaceHighest,
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
                          ? AppColors.danger
                          : AppColors.primaryBright,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _followed ? 'Siguiendo' : 'Mi lista',
                      style: TextStyle(
                        color: _followed ? AppColors.danger : AppColors.text,
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
              color: AppColors.surface,
              border: Border.all(color: AppColors.surfaceHighest),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.download_rounded,
                  color: AppColors.primaryBright,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  _downloadLabel(anime.slug),
                  style: const TextStyle(
                    color: AppColors.primaryBright,
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
            children: anime.genres
                .map((g) => _chip(g.name, AppColors.info))
                .toList(),
          ),
        const SizedBox(height: 14),
        Text(
          anime.synopsis,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Color final del degradado del banner: igual al fondo ambiental.
  Color get _seamColor => Color.lerp(AppColors.bg, _palette.base, 0.72)!;

  /// Etiqueta del botón de descargas según estado del anime.
  String _downloadLabel(String slug) {
    final n = _dl.downloadedEpisodes(slug).length;
    if (_dl.isQueued(slug, -1) ||
        _dl.progress.value.keys.any((k) => k.startsWith('$slug#'))) {
      if (n == 0) return 'Descargando…';
    }
    if (n > 0) return 'Descargas ($n)';
    return 'Descargar';
  }

  void _playEpisode(AnimeDetail anime, int episodeNumber) {
    ApiService.addHistory(anime.id, anime.slug, anime.title, episodeNumber);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EpisodePage(
          animeSlug: anime.slug,
          episodeNumber: episodeNumber,
          animeTitle: anime.title,
        ),
      ),
    ).then((_) => _refreshWatched());
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
          final da =
              DateTime.tryParse(a.watchedAt) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final db =
              DateTime.tryParse(b.watchedAt) ??
              DateTime.fromMillisecondsSinceEpoch(0);
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
    return PillBadge(label: text, color: color);
  }
}
