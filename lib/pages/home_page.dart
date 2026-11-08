import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/tv_service.dart';
import '../ui/tokens.dart';
import '../ui/widgets/ambient_page.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/glass_header.dart';
import '../ui/widgets/pill_badge.dart';
import '../ui/widgets/poster_card.dart';
import '../ui/widgets/section_header.dart';
import '../ui/widgets/skeletons.dart';
import '../widgets/error_dialog.dart';
import '../widgets/sync_button.dart';
import '../widgets/tv_focusable.dart';
import '../widgets/update_badge_button.dart';
import 'detail_page.dart';
import 'episode_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<RecentEpisode> _recent = [];
  List<HistoryEntry> _history = [];
  List<FollowedAnime> _following = [];
  Set<String> _followedSlugs = {};

  bool _loading = true;
  bool _hadError = false;

  @override
  void initState() {
    super.initState();
    _load();
    SyncService.stateVersion.addListener(_refreshLocal);
  }

  @override
  void dispose() {
    SyncService.stateVersion.removeListener(_refreshLocal);
    super.dispose();
  }

  /// Refresco inmediato de listas locales tras seguir, dejar de seguir o borrar.
  Future<void> _refreshLocal() async {
    try {
      final results = await Future.wait<Object>([
        ApiService.fetchHistory().catchError((_) => <HistoryEntry>[]),
        ApiService.fetchFollowed().catchError((_) => <FollowedAnime>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as List<HistoryEntry>;
        _following = results[1] as List<FollowedAnime>;
        _followedSlugs = _following.map((f) => f.animeSlug).toSet();
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    const maxRetries = 8;
    for (var attempt = 0; attempt < maxRetries && mounted; attempt++) {
      try {
        final results = await Future.wait<Object>([
          ApiService.fetchRecentEpisodes(),
          ApiService.fetchHistory().catchError((_) => <HistoryEntry>[]),
          ApiService.fetchFollowed().catchError((_) => <FollowedAnime>[]),
        ]);

        final recent = results[0] as List<RecentEpisode>;
        final history = results[1] as List<HistoryEntry>;
        final following = results[2] as List<FollowedAnime>;

        if (!mounted) return;
        setState(() {
          _recent = recent;
          _history = history;
          _following = following;
          _followedSlugs = following.map((f) => f.animeSlug).toSet();
          _loading = false;
          _hadError = false;
        });
        return;
      } catch (e, st) {
        debugPrint('HOME RETRY: $e');
        if (attempt == 0 && mounted && !isConnectivityError(e)) {
          showErrorSheet(context, e, st);
        }
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _hadError = true;
    });
  }

  void _openAnime(String slug) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailPage(slug: slug)),
    );
  }

  void _openEpisode(RecentEpisode ep) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EpisodePage(
          animeSlug: ep.animeSlug,
          episodeNumber: ep.episodeNumber,
          animeTitle: ep.animeTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide =
        TvService.isTvMode ||
        Platform.isLinux ||
        Platform.isWindows ||
        MediaQuery.sizeOf(context).width > 800;

    final headerHeight = GlassHeader.heightOf(context, height: 44);
    final header = GlassHeader(
      height: 44,
      actions: const [UpdateBadgeButton(), SyncButton()],
    );
    return AmbientPage(
      imageUrl: _ambientImage,
      opacity: 0.60,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: _loading
                  ? _buildSkeleton(isWide)
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      child: _isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.only(top: headerHeight),
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.55,
                                  child: EmptyState(
                                    icon: Icons.cloud_off_outlined,
                                    title: _hadError
                                        ? 'No se pudo cargar el inicio'
                                        : 'Todavía no hay episodios',
                                    message: _hadError
                                        ? 'Revisa tu conexión y vuelve a intentarlo.'
                                        : 'Los estrenos aparecerán aquí en cuanto se publiquen.',
                                    actionLabel: 'Reintentar',
                                    onAction: () {
                                      setState(() => _loading = true);
                                      _load();
                                    },
                                  ),
                                ),
                              ],
                            )
                          : CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: SizedBox(height: headerHeight),
                                ),
                                if (_recent.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _HeroCarousel(
                                      episodes: _takeHero(_recent),
                                      followedSlugs: _followedSlugs,
                                      isWide: isWide,
                                      onWatch: _openEpisode,
                                      onOpen: (ep) => _openAnime(ep.animeSlug),
                                    ),
                                  ),
                                if (_history.isNotEmpty) ...[
                                  const SliverToBoxAdapter(
                                    child: SectionHeader(
                                      title: 'Continuar viendo',
                                      kicker: 'Tu historial',
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child: _MediaRow(
                                      items: _history.take(20).map((h) {
                                        return _RowItem(
                                          title: h.animeTitle,
                                          imageUrl: h.posterUrl,
                                          badge: 'Ep ${h.episodeNumber}',
                                          subtitle:
                                              'Visto ${_shortDate(h.watchedAt)}',
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => EpisodePage(
                                                animeSlug: h.animeSlug,
                                                episodeNumber: h.episodeNumber,
                                                animeTitle: h.animeTitle,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                                const SliverToBoxAdapter(
                                  child: SectionHeader(
                                    title: 'Estrenos',
                                    kicker: 'Recién actualizado',
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: _MediaRow(
                                    items: _recent.map((ep) {
                                      final followed = _followedSlugs.contains(
                                        ep.animeSlug,
                                      );
                                      return _RowItem(
                                        title: ep.animeTitle,
                                        imageUrl:
                                            ep.thumbnail ??
                                            'https://cdn.animeav1.com/covers/${ep.animeId}.jpg',
                                        badge: 'Ep ${ep.episodeNumber}',
                                        subtitle: ep.timeAgo,
                                        favorite: followed,
                                        onTap: () => followed
                                            ? _openEpisode(ep)
                                            : _openAnime(ep.animeSlug),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                if (_following.isNotEmpty) ...[
                                  const SliverToBoxAdapter(
                                    child: SectionHeader(
                                      title: 'Mi lista',
                                      kicker: 'Seguimiento',
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child: _MediaRow(
                                      items: _following.map((f) {
                                        return _RowItem(
                                          title: f.animeTitle,
                                          imageUrl: f.posterUrl,
                                          subtitle: 'En tu lista',
                                          favorite: true,
                                          onTap: () => _openAnime(f.animeSlug),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                                const SliverToBoxAdapter(
                                  child: SizedBox(
                                    height: AppLayout.bottomGutter,
                                  ),
                                ),
                              ],
                            ),
                    ),
            ),
            Positioned(top: 0, left: 0, right: 0, child: header),
          ],
        ),
      ),
    );
  }

  bool get _isEmpty =>
      _recent.isEmpty && _history.isEmpty && _following.isEmpty;

  /// Portada que alimenta el fondo ambiental del inicio.
  String? get _ambientImage {
    if (_recent.isNotEmpty) {
      return _recent.first.thumbnail ??
          'https://cdn.animeav1.com/covers/${_recent.first.animeId}.jpg';
    }
    if (_following.isNotEmpty) return _following.first.posterUrl;
    if (_history.isNotEmpty) return _history.first.posterUrl;
    return null;
  }

  Widget _buildSkeleton(bool isWide) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: GlassHeader.heightOf(context, height: 44)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: SkeletonScope(
              child: SkeletonBox(
                height: isWide
                    ? AppLayout.heroHeightWide
                    : AppLayout.heroHeightCompact,
                radius: AppRadius.lg,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.sm,
              AppSpace.page,
              0,
            ),
            child: SkeletonBox(width: 170, height: 16, radius: AppRadius.xs),
          ),
          const SizedBox(height: AppSpace.md),
          const SkeletonRow(),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.xl,
              AppSpace.page,
              0,
            ),
            child: SkeletonBox(width: 130, height: 16, radius: AppRadius.xs),
          ),
          const SizedBox(height: AppSpace.md),
          const SkeletonRow(),
        ],
      ),
    );
  }

  /// Hasta cinco títulos distintos para el héroe, sin repetir anime.
  List<RecentEpisode> _takeHero(List<RecentEpisode> episodes) {
    final seen = <String>{};
    final out = <RecentEpisode>[];
    for (final ep in episodes) {
      if (seen.add(ep.animeSlug)) out.add(ep);
      if (out.length == 5) break;
    }
    return out;
  }

  static String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Héroe
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({
    required this.episodes,
    required this.followedSlugs,
    required this.isWide,
    required this.onWatch,
    required this.onOpen,
  });

  final List<RecentEpisode> episodes;
  final Set<String> followedSlugs;
  final bool isWide;
  final ValueChanged<RecentEpisode> onWatch;
  final ValueChanged<RecentEpisode> onOpen;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  static const _rotation = Duration(seconds: 9);

  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episodes.length != widget.episodes.length) {
      _index = 0;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    if (!_controller.hasClients) return;
    final next = (_index + delta).clamp(0, widget.episodes.length - 1);
    if (next == _index) return;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: AppMotion.curve,
    );
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.episodes.length < 2) return;
    _timer = Timer.periodic(_rotation, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.episodes.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: AppMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.isWide
        ? AppLayout.heroHeightWide
        : AppLayout.heroHeightCompact;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.episodes.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _startTimer();
                },
                itemBuilder: (context, i) {
                  final ep = widget.episodes[i];
                  return _HeroSlide(
                    episode: ep,
                    isFollowed: widget.followedSlugs.contains(ep.animeSlug),
                    isWide: widget.isWide,
                    onWatch: () => widget.onWatch(ep),
                    onOpen: () => widget.onOpen(ep),
                  );
                },
              ),
              if (widget.episodes.length > 1)
                Positioned(
                  right: AppSpace.lg,
                  top: AppSpace.lg,
                  child: _Dots(count: widget.episodes.length, index: _index),
                ),
              if (widget.isWide && widget.episodes.length > 1) ...[
                Positioned(
                  left: AppSpace.md,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrow(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _step(-1),
                    ),
                  ),
                ),
                Positioned(
                  right: AppSpace.md,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _HeroArrow(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _step(1),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({
    required this.episode,
    required this.isFollowed,
    required this.isWide,
    required this.onWatch,
    required this.onOpen,
  });

  final RecentEpisode episode;
  final bool isFollowed;
  final bool isWide;
  final VoidCallback onWatch;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final decodeWidth = (width * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(360, 960);

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl:
              episode.thumbnail ??
              'https://cdn.animeav1.com/covers/${episode.animeId}.jpg',
          fit: BoxFit.cover,
          memCacheWidth: decodeWidth,
          filterQuality: FilterQuality.medium,
          fadeInDuration: AppMotion.slow,
          placeholder: (_, __) =>
              const ColoredBox(color: AppColors.surfaceHigh),
          errorWidget: (_, __, ___) =>
              const ColoredBox(color: AppColors.surfaceHigh),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: isWide
                ? AppGradients.imageVeilWide
                : AppGradients.imageVeil,
          ),
        ),
        Positioned(
          left: isWide ? AppSpace.xxl : AppSpace.lg,
          right: isWide ? width * 0.45 : AppSpace.lg,
          bottom: isWide ? AppSpace.xxl : AppSpace.lg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PillBadge(
                    label: 'Nuevo episodio',
                    tone: BadgeTone.solid,
                  ),
                  if (isFollowed) ...[
                    const SizedBox(width: AppSpace.sm),
                    const PillBadge(
                      label: 'En tu lista',
                      color: AppColors.dangerSoft,
                      icon: Icons.favorite,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.sm + 2),
              Text(
                episode.animeTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.displaySmall,
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                children: [
                  PillBadge(
                    label: 'Episodio ${episode.episodeNumber}',
                    color: AppColors.primaryBright,
                    icon: Icons.play_arrow_rounded,
                  ),
                  if (episode.timeAgo.isNotEmpty)
                    PillBadge(
                      label: episode.timeAgo,
                      color: AppColors.info,
                      icon: Icons.schedule,
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onWatch,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Ver ahora'),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  OutlinedButton(
                    onPressed: onOpen,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.veil.withValues(alpha: 0.25),
                    ),
                    child: const Text('Detalles'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.veil.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (i) {
          final active = i == index;
          return AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: active ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? AppColors.primaryBright : AppColors.textMuted,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carrusel horizontal
// ─────────────────────────────────────────────────────────────────────────────

class _RowItem {
  const _RowItem({
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.badge,
    this.subtitle,
    this.favorite = false,
  });

  final String title;
  final String imageUrl;
  final VoidCallback onTap;
  final String? badge;
  final String? subtitle;
  final bool favorite;
}

class _MediaRow extends StatefulWidget {
  const _MediaRow({required this.items});

  final List<_RowItem> items;

  @override
  State<_MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<_MediaRow> {
  final ScrollController _controller = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncEdges);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final left = pos.pixels > 4;
    final right = pos.pixels < pos.maxScrollExtent - 4;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _scrollBy(double dx) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + dx).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: AppMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showControls =
        TvService.isTvMode || MediaQuery.sizeOf(context).width > 800;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final cardWidth = AppLayout.rowCardWidthFor(available);

        WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());

        return SizedBox(
          height: AppLayout.rowHeightFor(cardWidth),
          child: Stack(
            children: [
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && _controller.hasClients) {
                    final delta = event.scrollDelta.dy + event.scrollDelta.dx;
                    final target = (_controller.offset + delta).clamp(
                      0.0,
                      _controller.position.maxScrollExtent,
                    );
                    _controller.jumpTo(target);
                  }
                },
                child: ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.page,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpace.md),
                  itemBuilder: (context, i) {
                    final item = widget.items[i];
                    return SizedBox(
                      width: cardWidth,
                      child: PosterCard(
                        title: item.title,
                        imageUrl: item.imageUrl,
                        badge: item.badge,
                        subtitle: item.subtitle,
                        favorite: item.favorite,
                        onTap: item.onTap,
                      ),
                    );
                  },
                ),
              ),
              if (_canLeft) const _RowFade(alignment: Alignment.centerLeft),
              if (_canRight) const _RowFade(alignment: Alignment.centerRight),
              if (showControls && _canLeft)
                _RowArrow(left: true, onTap: () => _scrollBy(-cardWidth * 2)),
              if (showControls && _canRight)
                _RowArrow(left: false, onTap: () => _scrollBy(cardWidth * 2)),
            ],
          ),
        );
      },
    );
  }
}

/// Degradado lateral que indica que hay más tarjetas.
class _RowFade extends StatelessWidget {
  const _RowFade({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final fromLeft = alignment == Alignment.centerLeft;
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fromLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: fromLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                AppColors.bg.withValues(alpha: 0.92),
                AppColors.bg.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Flecha de desplazamiento para ratón, teclado y control remoto.
class _RowArrow extends StatefulWidget {
  const _RowArrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  State<_RowArrow> createState() => _RowArrowState();
}

class _RowArrowState extends State<_RowArrow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.left ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        child: TvFocusable(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Focus(
            onFocusChange: (f) => setState(() => _focused = f),
            child: AnimatedContainer(
              duration: AppMotion.base,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(
                  alpha: _focused ? 0.95 : 0.70,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _focused
                      ? AppColors.primaryBright
                      : Colors.white.withValues(alpha: 0.12),
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Icon(
                widget.left
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: _focused ? AppColors.primaryBright : AppColors.text,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroArrow extends StatefulWidget {
  const _HeroArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeroArrow> createState() => _HeroArrowState();
}

class _HeroArrowState extends State<_HeroArrow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: AnimatedContainer(
          duration: AppMotion.base,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.veil.withValues(alpha: _focused ? 0.85 : 0.55),
            shape: BoxShape.circle,
            border: Border.all(
              color: _focused
                  ? AppColors.primaryBright
                  : Colors.white.withValues(alpha: 0.14),
              width: _focused ? 2 : 1,
            ),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
