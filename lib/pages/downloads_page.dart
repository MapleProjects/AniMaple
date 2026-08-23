import 'dart:io';

import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import 'detail_page.dart';
import 'episode_page.dart';

/// Pestaña "Descargas" de Mi Lista.
///
/// Grid de contenedores por anime (portada local + título + N caps + tamaño).
/// Al entrar se muestra la vista offline del anime: solo capítulos
/// descargados, con marca de visto (desde el historial) y borrado individual.
/// Funciona 100% sin conexión.
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

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

  /// Llamado desde MainShell cuando el tab se vuelve visible.
  void refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteAnime(String slug, String title, int eps) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF110e1a),
        title: const Text('Eliminar descargas',
            style: TextStyle(color: Color(0xFFe8e4f0))),
        content: Text(
            '¿Eliminar las $eps descargas de "$title"? Se liberará su espacio.',
            style: const TextStyle(color: Color(0xFFa99fc0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancelar', style: TextStyle(color: Color(0xFF6d6488))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Eliminar', style: TextStyle(color: Color(0xFFef4444))),
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
    // Animes que solo están en cola (sin nada completo aún).
    final queuedOnly = <String>{};
    for (final key in progress.keys) {
      final slug = key.split('#').first;
      if (!_dl.downloadedSlugs().contains(slug)) queuedOnly.add(slug);
    }
    final totalBytes = _dl.totalBytesAll();

    if (slugs.isEmpty && progress.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_for_offline_outlined,
                size: 56, color: Colors.grey[700]),
            SizedBox(height: 12),
            Text('Sin descargas',
                style: TextStyle(color: Colors.grey[600], fontSize: 15)),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Descarga capítulos desde un anime para verlos sin conexión',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (totalBytes > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Icon(Icons.storage_rounded, size: 15, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text('${slugs.length} animes · ${_fmtBytes(totalBytes)} en uso',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: slugs.length,
            itemBuilder: (ctx, i) => _animeCard(slugs[i]),
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
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => OfflineAnimePage(slug: slug),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF110e1a),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1e1832)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterFile != null)
                    Image.file(File(posterFile), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _posterFallback())
                  else
                    _posterFallback(),
                  // Badge de descarga
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF22c55e).withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.download_done_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                  // Borrar todo
                  Positioned(
                    top: 4, right: 4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () =>
                            _confirmDeleteAnime(slug, title as String, eps),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.delete_outline,
                              color: Color(0xFFef4444), size: 15),
                        ),
                      ),
                    ),
                  ),
                  // Progreso si hay cola activa para este anime
                  if (activeProgress != null)
                    Positioned(
                      bottom: 8, left: 8, right: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: activeProgress,
                          minHeight: 5,
                          backgroundColor: Colors.black54,
                          color: const Color(0xFFf59e0b),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFe8e4f0))),
          const SizedBox(height: 2),
          Text(
            '$eps ${eps == 1 ? 'capítulo' : 'capítulos'} · ${_fmtBytes(bytes)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6d6488)),
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
        color: const Color(0xFF181328),
        child: const Center(
          child: Icon(Icons.movie_outlined, color: Color(0xFF3d3560), size: 42),
        ),
      );
}

/// Vista offline de UN anime descargado: portada, sinopsis y SOLO los
/// capítulos guardados en disco. No toca red salvo que el usuario pida
/// explícitamente abrir la página online.
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

  // Metadatos online (géneros, categoría, estado) para la cabecera completa.
  // Solo se piden si hay conexión; sin red la vista funciona igual con lo
  // guardado localmente (título, sinopsis, póster).
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
    } catch (_) {
      // Sin conexión: la cabecera queda con los datos locales.
    }
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
      backgroundColor: const Color(0xFF0a0812),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Color(0xFFe8e4f0))),
        backgroundColor: const Color(0xFF0a0812),
        iconTheme: const IconThemeData(color: Color(0xFFe8e4f0)),
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
                      child: Image.file(File(posterFile),
                          width: 100, height: 150, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22c55e).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Offline',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF22c55e))),
                          ),
                        ]),
                        // Etiquetas idénticas al detail page online.
                        if (online != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _labelChip(online.category,
                                  const Color(0xFF8b5cf6)),
                              if (online.status.isNotEmpty &&
                                  online.status != 'unknown')
                                _labelChip(
                                    online.status,
                                    online.status
                                            .contains('Finalizado')
                                        ? const Color(0xFF22c55e)
                                        : const Color(0xFFf59e0b)),
                              _labelChip('${online.episodesCount} eps',
                                  const Color(0xFF3b82f6)),
                              ...online.genres
                                  .map((g) => _labelChip(
                                      g.name, const Color(0xFF3b82f6))),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${eps.length} ${eps.length == 1 ? 'capítulo descargado' : 'capítulos descargados'}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: Color(0xFFe8e4f0)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dl.fmtBytesFor(widget.slug),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6d6488)),
                        ),
                        if (online == null) ...[
                          // Solo cuando no hay conexión para traer etiquetas.
                          const SizedBox(height: 6),
                          const Text('Etiquetas al reconectar',
                              style: TextStyle(
                                  fontSize: 11.5, color: Color(0xFF4a4260))),
                        ],
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => DetailPage(slug: widget.slug),
                            ));
                          },
                          icon: const Icon(Icons.wifi_rounded, size: 17,
                              color: Color(0xFFa78bfa)),
                          label: const Text('Ver online / gestionar',
                              style: TextStyle(color: Color(0xFFa78bfa))),
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
                child: Text(synopsis,
                    style: const TextStyle(
                        fontSize: 13.5, color: Color(0xFFa99fc0), height: 1.5)),
              ),
            ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Descargados',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: Color(0xFFe8e4f0))),
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
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final ep = eps[i];
                  final watched = _watched.contains(ep);
                  final progress =
                      _dl.progress.value['${widget.slug}#$ep'];
                  final isQueued = _dl.isQueued(widget.slug, ep);
                  return _epTile(ep, watched, progress, isQueued);
                },
                childCount: eps.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Chip idéntico al de detail_page (categoría, estado, géneros).
  static Widget _labelChip(String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _epTile(int ep, bool watched, double? progress, bool queued) {
    if (queued || (progress != null && progress < 1)) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF110e1a),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFf59e0b), width: 2),
        ),
        child: Center(
          child: CircularProgressIndicator(
            value: (progress != null && progress > 0 && progress <= 1)
                ? progress
                : null,
            strokeWidth: 2.4,
            color: const Color(0xFFf59e0b),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () async {
        // Reproducción offline: EpisodePage detecta el archivo local solo.
        ApiService.addHistory(
          (_meta?['anime_id'] as num?)?.toInt() ?? 0,
          widget.slug,
          (_meta?['title'] as String?) ?? widget.slug,
          ep,
        );
        setState(() => _watched.add(ep));
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => EpisodePage(
            animeSlug: widget.slug,
            episodeNumber: ep,
            animeTitle:
                (_meta?['title'] as String?) ?? widget.slug,
            offlineLibrary: true,
          ),
        ));
        _loadWatched();
      },
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF110e1a),
            title: const Text('Eliminar descarga',
                style: TextStyle(color: Color(0xFFe8e4f0))),
            content: Text('¿Eliminar el episodio $ep descargado?',
                style: const TextStyle(color: Color(0xFFa99fc0))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar',
                    style: TextStyle(color: Color(0xFF6d6488))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar',
                    style: TextStyle(color: Color(0xFFef4444))),
              ),
            ],
          ),
        );
        if (ok == true) await _dl.deleteEpisode(widget.slug, ep);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF110e1a),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: watched ? const Color(0xFF22c55e) : const Color(0xFF1e1832),
            width: watched ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text('$ep',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: watched
                        ? const Color(0xFF22c55e)
                        : const Color(0xFFe8e4f0))),
            Positioned(
              bottom: 3, right: 3,
              child: Icon(Icons.download_done_rounded,
                  size: 13,
                  color: watched
                      ? const Color(0xFF22c55e)
                      : const Color(0xFF4a4260)),
            ),
          ],
        ),
      ),
    );
  }
}
