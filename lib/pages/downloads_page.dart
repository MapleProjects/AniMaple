import 'dart:io';

import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../ui/tokens.dart';
import '../widgets/tv_focusable.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/glass_app_bar.dart';
import 'detail_page.dart';
import 'episode_page.dart';

/// Vista de animes descargados localmente.
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key, this.embedded = false});

  /// Cuando se inserta dentro de un scroll sliver ya posicionado.
  final bool embedded;

  @override
  State<DownloadsPage> createState() => DownloadsPageState();
}

class DownloadsPageState extends State<DownloadsPage> {
  final DownloadService _dl = DownloadService.instance;

  @override
  void initState() {
    super.initState();
    _dl.version.addListener(_onChanged);
  }

  @override
  void dispose() {
    _dl.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteAnime(String slug, String title, int eps) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Eliminar descargas',
          style: TextStyle(color: AppColors.text),
        ),
        content: Text(
          '¿Eliminar las $eps descargas de "$title"? Se liberará su espacio.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _dl.deleteAnime(slug);
  }

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final slugs = _dl.downloadedSlugs().toList()..sort();
    final progress = _dl.progress.value;
    final totalBytes = _dl.totalBytesAll();

    if (slugs.isEmpty && progress.isEmpty) {
      return const EmptyState(
        icon: Icons.download_for_offline_outlined,
        title: 'Sin descargas',
        message: 'Descarga capítulos desde un anime para verlos sin conexión.',
      );
    }

    final storageInfo = totalBytes > 0
        ? Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.sm,
              AppSpace.page,
              AppSpace.xs,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpace.sm),
                Text(
                  '${slugs.length} animes · ${_fmtBytes(totalBytes)} en uso',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          storageInfo,
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page,
              AppSpace.xs,
              AppSpace.page,
              AppLayout.bottomGutter,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: AppLayout.posterExtent,
              childAspectRatio: AppLayout.posterAspect,
              crossAxisSpacing: AppSpace.md,
              mainAxisSpacing: AppSpace.lg,
            ),
            itemCount: slugs.length,
            itemBuilder: (ctx, i) => _animeCard(slugs[i]),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(height: GlassAppBar.contentInset(extra: 44)),
        storageInfo,
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 900;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.sm,
                  AppSpace.page,
                  AppLayout.bottomGutter,
                ),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: wide
                      ? AppLayout.posterExtentWide
                      : AppLayout.posterExtent,
                  childAspectRatio: AppLayout.posterAspect,
                  crossAxisSpacing: AppSpace.md,
                  mainAxisSpacing: AppSpace.lg,
                ),
                itemCount: slugs.length,
                itemBuilder: (ctx, i) => _animeCard(slugs[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _animeCard(String slug) {
    final entry = _dl.indexEntryFor(slug);
    final title = entry?['title'] ?? slug;
    final posterFile = _dl.posterFileFor(slug);
    final eps = _dl.downloadedEpisodes(slug).length;
    final bytes = _dl.totalBytesFor(slug);
    final activeProgress = _activeProgressFor(slug);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OfflineAnimePage(slug: slug)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterFile != null)
                    Image.file(
                      File(posterFile),
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => _posterFallback(),
                    )
                  else
                    _posterFallback(),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.download_done_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: TvFocusable(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: () =>
                          _confirmDeleteAnime(slug, title as String, eps),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: AppColors.danger,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                  if (activeProgress != null)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: activeProgress,
                          minHeight: 5,
                          backgroundColor: Colors.black54,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            '$eps ${eps == 1 ? 'capítulo' : 'capítulos'} · ${_fmtBytes(bytes)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  double? _activeProgressFor(String slug) {
    final entries = _dl.progress.value;
    double sum = 0;
    var count = 0;
    for (final e in entries.entries) {
      if (e.key.startsWith('$slug#')) {
        sum += e.value.clamp(0.0, 1.0);
        count++;
      }
    }
    return count == 0 ? null : sum / count;
  }

  Widget _posterFallback() => Container(
    color: AppColors.surfaceHigh,
    child: const Center(
      child: Icon(
        Icons.movie_outlined,
        color: AppColors.outlineStrong,
        size: 42,
      ),
    ),
  );
}

/// Vista local de un anime con capítulos descargados.
class OfflineAnimePage extends StatefulWidget {
  final String slug;
  const OfflineAnimePage({super.key, required this.slug});

  @override
  State<OfflineAnimePage> createState() => _OfflineAnimePageState();
}

class _OfflineAnimePageState extends State<OfflineAnimePage> {
  final DownloadService _dl = DownloadService.instance;
  Map<String, dynamic>? _meta;
  Set<int> _watched = {};
  AnimeDetail? _online;

  @override
  void initState() {
    super.initState();
    _dl.version.addListener(_onChanged);
    _loadMeta();
    _loadWatched();
    _loadOnline();
  }

  Future<void> _loadOnline() async {
    try {
      final d = await ApiService.fetchAnimeDetail(widget.slug);
      if (mounted) setState(() => _online = d);
    } catch (_) {}
  }

  @override
  void dispose() {
    _dl.version.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMeta() async {
    final meta = await _dl.metaFor(widget.slug);
    if (mounted) setState(() => _meta = meta);
  }

  /// Historial local (SharedPreferences): funciona sin conexión.
  Future<void> _loadWatched() async {
    try {
      final history = await ApiService.fetchHistory();
      final w = history
          .where((h) => h.animeSlug == widget.slug)
          .map((h) => h.episodeNumber)
          .toSet();
      if (mounted) setState(() => _watched = w);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final online = _online;
    final title = (meta?['title'] as String?) ?? widget.slug;
    final synopsis = (meta?['synopsis'] as String?) ?? '';
    final posterFile = _dl.posterFileFor(widget.slug);
    final eps = _dl.downloadedEpisodes(widget.slug).toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: AppColors.text)),
        backgroundColor: AppColors.bg,
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (posterFile != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(posterFile),
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Offline',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Etiquetas idénticas al detail page online.
                        if (online != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _labelChip(online.category, AppColors.primary),
                              if (online.status.isNotEmpty &&
                                  online.status != 'unknown')
                                _labelChip(
                                  online.status,
                                  online.status.contains('Finalizado')
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              _labelChip(
                                '${online.episodesCount} eps',
                                AppColors.info,
                              ),
                              ...online.genres.map(
                                (g) => _labelChip(g.name, AppColors.info),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${eps.length} ${eps.length == 1 ? 'capítulo descargado' : 'capítulos descargados'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dl.fmtBytesFor(widget.slug),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if (online == null) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Etiquetas al reconectar',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailPage(slug: widget.slug),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.wifi_rounded,
                            size: 17,
                            color: AppColors.primaryBright,
                          ),
                          label: const Text(
                            'Ver online / gestionar',
                            style: TextStyle(color: AppColors.primaryBright),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (synopsis.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  synopsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Descargados',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 80,
                childAspectRatio: 1,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final ep = eps[i];
                final watched = _watched.contains(ep);
                final progress = _dl.progress.value['${widget.slug}#$ep'];
                final isQueued = _dl.isQueued(widget.slug, ep);
                return _epTile(ep, watched, progress, isQueued);
              }, childCount: eps.length),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _labelChip(String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _epTile(int ep, bool watched, double? progress, bool queued) {
    if (queued || (progress != null && progress < 1)) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning, width: 2),
        ),
        child: Center(
          child: CircularProgressIndicator(
            value: (progress != null && progress > 0 && progress <= 1)
                ? progress
                : null,
            strokeWidth: 2.4,
            color: AppColors.warning,
          ),
        ),
      );
    }
    return TvFocusable(
      onTap: () async {
        ApiService.addHistory(
          (_meta?['anime_id'] as num?)?.toInt() ?? 0,
          widget.slug,
          (_meta?['title'] as String?) ?? widget.slug,
          ep,
        );
        setState(() => _watched.add(ep));
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EpisodePage(
              animeSlug: widget.slug,
              episodeNumber: ep,
              animeTitle: (_meta?['title'] as String?) ?? widget.slug,
              offlineLibrary: true,
            ),
          ),
        );
        _loadWatched();
      },
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Eliminar descarga',
              style: TextStyle(color: AppColors.text),
            ),
            content: Text(
              '¿Eliminar el episodio $ep descargado?',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Eliminar',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        );
        if (ok == true) await _dl.deleteEpisode(widget.slug, ep);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: watched ? AppColors.success : AppColors.outline,
            width: watched ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$ep',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: watched ? AppColors.success : AppColors.text,
              ),
            ),
            Positioned(
              bottom: 3,
              right: 3,
              child: Icon(
                Icons.download_done_rounded,
                size: 13,
                color: watched ? AppColors.success : AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
