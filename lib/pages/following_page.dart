import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/sync_service.dart';
import '../ui/tokens.dart';
import '../ui/widgets/ambient_page.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/overlay_icon_button.dart';
import '../ui/widgets/poster_card.dart';
import '../ui/widgets/skeletons.dart';
import 'detail_page.dart';
import 'downloads_page.dart';

class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => FollowingPageState();
}

/// Lista de seguimiento con pestañas de favoritos y descargas locales.
class FollowingPageState extends State<FollowingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<FollowedAnime> _following = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
    SyncService.stateVersion.addListener(_load);
  }

  @override
  void dispose() {
    SyncService.stateVersion.removeListener(_load);
    _tabCtrl.dispose();
    super.dispose();
  }

  void refresh() => _load();

  Future<void> _load() async {
    try {
      final f = await ApiService.fetchFollowed();
      if (!mounted) return;
      setState(() {
        _following = f;
        _loading = false;
      });
    } catch (e) {
      debugPrint('FOLLOWING ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unfollowWithConfirm(FollowedAnime f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar de favoritos'),
        content: Text('¿Eliminar "${f.animeTitle}" de tu lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      // Actualización optimista: la tarjeta desaparece al instante.
      setState(() => _following.removeWhere((x) => x.animeId == f.animeId));
      await ApiService.unfollow(f.animeId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmbientPage(
      imageUrl: _following.isNotEmpty ? _following.first.posterUrl : null,
      opacity: 0.50,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: AppColors.bg.withValues(alpha: 0.62),
                surfaceTintColor: Colors.transparent,
                title: const Text('Mi lista'),
                bottom: TabBar(
                  controller: _tabCtrl,
                  tabs: const [
                    Tab(height: 44, child: Text('Favoritos')),
                    Tab(height: 44, child: Text('Descargas')),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabCtrl,
            children: [_buildFavoritesTab(), _buildDownloadsTab()],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesTab() {
    return Builder(
      builder: (context) {
        final queued = _queuedOnlySlugs();
        return RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: AppSpace.sm),
                    child: SkeletonPosterGrid(),
                  ),
                )
              else if (_following.isEmpty && queued.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.favorite_outline,
                    title: 'Sin animes seguidos',
                    message:
                        'Marca un anime como favorito para verlo aquí y recibir avisos.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.page,
                    AppSpace.md,
                    AppSpace.page,
                    AppLayout.bottomGutter,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: AppLayout.posterExtentFor(context),
                      childAspectRatio: AppLayout.posterAspect,
                      crossAxisSpacing: AppSpace.md,
                      mainAxisSpacing: AppSpace.lg,
                    ),
                    delegate: SliverChildBuilderDelegate((ctx, i) {
                      if (i >= _following.length) {
                        return _QueuedCard(slug: queued[i - _following.length]);
                      }
                      final f = _following[i];
                      return PosterCard(
                        title: f.animeTitle,
                        imageUrl: f.posterUrl,
                        subtitle: 'En tu lista',
                        favorite: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailPage(slug: f.animeSlug),
                          ),
                        ),
                        action: OverlayIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Quitar de favoritos',
                          onPressed: () => _unfollowWithConfirm(f),
                        ),
                      );
                    }, childCount: _following.length + queued.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDownloadsTab() {
    return Builder(
      builder: (context) => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: AppSpace.sm),
              child: DownloadsPage(embedded: true),
            ),
          ),
        ],
      ),
    );
  }

  // Animes con descargas en progreso sin archivos locales completados.
  DownloadService get _dl => DownloadService.instance;

  List<String> _queuedOnlySlugs() {
    final out = <String>[];
    for (final key in _dl.progress.value.keys) {
      final slug = key.split('#').first;
      if (!_dl.downloadedSlugs().contains(slug) && !out.contains(slug)) {
        out.add(slug);
      }
    }
    return out;
  }
}

class _QueuedCard extends StatelessWidget {
  const _QueuedCard({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.5),
              ),
            ),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.warning,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Descargando…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: AppColors.warning),
        ),
      ],
    );
  }
}
