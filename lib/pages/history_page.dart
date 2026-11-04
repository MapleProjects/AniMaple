import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../ui/tokens.dart';
import '../ui/widgets/ambient_page.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/overlay_icon_button.dart';
import '../ui/widgets/poster_card.dart';
import '../ui/widgets/skeletons.dart';
import '../widgets/error_dialog.dart';
import 'episode_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => HistoryPageState();
}

class HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    SyncService.stateVersion.addListener(_load);
  }

  @override
  void dispose() {
    SyncService.stateVersion.removeListener(_load);
    super.dispose();
  }

  void refresh() => _load();

  Future<void> _load() async {
    try {
      final h = await ApiService.fetchHistory();
      if (!mounted) return;
      setState(() {
        _history = h;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('HISTORY ERROR: $e');
      if (mounted && !isConnectivityError(e)) {
        showErrorSheet(context, e, st);
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteWithConfirm(HistoryEntry h) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar del historial'),
        content: Text(
          '¿Eliminar el capítulo ${h.episodeNumber} de "${h.animeTitle}" del historial?',
        ),
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
      setState(
        () => _history.removeWhere(
          (x) =>
              x.animeSlug == h.animeSlug && x.episodeNumber == h.episodeNumber,
        ),
      );
      await ApiService.deleteHistory(h.animeSlug, h.episodeNumber);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmbientPage(
      imageUrl: _history.isNotEmpty ? _history.first.posterUrl : null,
      opacity: 0.50,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverAppBar(
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: AppColors.bg.withValues(alpha: 0.62),
                surfaceTintColor: Colors.transparent,
                title: const Text('Historial'),
                actions: [
                  if (_history.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpace.md),
                      child: Center(
                        child: Text(
                          '${_history.length} títulos',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                ],
              ),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: AppSpace.md),
                    child: SkeletonPosterGrid(),
                  ),
                )
              else if (_history.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.history,
                    title: 'Sin historial',
                    message:
                        'Los capítulos que veas aparecerán aquí para retomarlos.',
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
                      final h = _history[i];
                      return PosterCard(
                        title: h.animeTitle,
                        imageUrl: h.posterUrl,
                        badge: 'Ep ${h.episodeNumber}',
                        subtitle: _relativeDate(h.watchedAt),
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
                        action: OverlayIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Quitar del historial',
                          onPressed: () => _deleteWithConfirm(h),
                        ),
                      );
                    }, childCount: _history.length),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 30) return 'hace ${diff.inDays} d';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}
