import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';

/// Hoja de selección de capítulos para descargar.
///
/// Comportamiento:
/// - NADA preseleccionado: el usuario elige qué bajar.
/// - "Descargar todo" como atajo explícito.
/// - Toggle "Doblaje" visible SOLO si al menos un capítulo tiene DUB
///   (sonda ligera en segundo plano). Con doblaje activo, cada capítulo
///   se baja con DUB cuando lo tiene y cae a SUB cuando no.
/// - Vistos: punto azul. Descargados: gris con X para borrar.
/// - En cola: ámbar con progreso. Error: rojo con reintento.
class DownloadSheet extends StatefulWidget {
  final AnimeDetail anime;

  /// Capítulos que vienen ya marcados al abrir (p.ej. el capítulo actual
  /// cuando se abre desde el reproductor). Se ignoran los descargados/en cola.
  final Set<int> preselected;

  const DownloadSheet({super.key, required this.anime, this.preselected = const {}});

  static Future<void> show(
    BuildContext context,
    AnimeDetail anime, {
    Set<int> preselected = const {},
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF110e1a),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => DownloadSheet(anime: anime, preselected: preselected),
    );
  }

  @override
  State<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<DownloadSheet> {
  late final DownloadService _dl;
  Set<int> _selected = {};
  bool _enqueued = false;
  bool _preferDub = false;

  // Sonda de doblaje (solo corre si hay caps sin descargar).
  bool _dubAvailable = false;
  bool _probingDub = false;
  int? _dubEpCached; // ep con DUB ya descargado → toggle directo

  @override
  void initState() {
    super.initState();
    _dl = DownloadService.instance;
    // Preselección: solo el capítulo desde donde se abrió (si aplica y es
    // válido). Sin preselección, la grilla abre totalmente vacía.
    _selected = widget.preselected
        .where((n) =>
            !_dl.isDownloaded(widget.anime.slug, n) &&
            !_dl.isQueued(widget.anime.slug, n))
        .toSet();
    _loadWatched();
    _probeDub();
  }

  Set<int> _watchedNumbers = {};

  /// Vistos según historial (para el punto azul en la grilla).
  Future<void> _loadWatched() async {
    try {
      final history = await ApiService.fetchHistory();
      final watched = history
          .where((h) => h.animeSlug == widget.anime.slug)
          .map((h) => h.episodeNumber)
          .toSet();
      if (mounted) setState(() => _watchedNumbers = watched);
    } catch (_) {}
  }

  Future<void> _probeDub() async {
    // DUB ya comprobado por descargas previas: toggle sin sondear red.
    if (_dl.downloadedDubEpisodes(widget.anime.slug).isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _dubAvailable = true;
        _preferDub = true;
      });
      return;
    }
    final slug = widget.anime.slug;
    // Caps candidatos: no descargados aún (los descargados ya tienen su
    // variante guardada y no afectan la decisión).
    final candidates = List<int>.generate(
      widget.anime.episodes.length,
      (i) => widget.anime.episodes[i].number,
    ).where((n) => !_dl.isDownloaded(slug, n)).toList()
      ..sort();
    if (candidates.isEmpty) return;
    if (!mounted) return;
    setState(() => _probingDub = true);
    final any = await _dl.probeAnyDub(slug, candidates);
    if (!mounted) return;
    setState(() {
      _dubAvailable = any;
      _probingDub = false;
      if (any) _preferDub = true; // Default: doblaje cuando existe.
    });
  }

  /// Selección de un episodio en la grilla (usado por [_EpTile]).
  void _toggleSelect(int ep) {
    if (!mounted) return;
    setState(() {
      if (_selected.contains(ep)) {
        _selected.remove(ep);
      } else {
        _selected.add(ep);
      }
    });
  }

  Future<void> _enqueue(Set<int> episodes) async {
    if (episodes.isEmpty || !mounted) return;
    await _dl.enqueueAnime(
      animeId: widget.anime.id,
      slug: widget.anime.slug,
      title: widget.anime.title,
      synopsis: widget.anime.synopsis,
      posterUrl: widget.anime.poster,
      episodeNumbers: episodes.toList()..sort(),
      preferDub: _preferDub,
      detail: widget.anime,
    );
    if (!mounted) return;
    setState(() {
      _enqueued = true;
      _selected = {};
    });
  }

  Future<void> _deleteEpisode(int ep) async {
    await _dl.deleteEpisode(widget.anime.slug, ep);
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDelete(int ep) async {
    final res = await showDialog<bool>(
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
            child:
                const Text('Eliminar', style: TextStyle(color: Color(0xFFef4444))),
          ),
        ],
      ),
    );
    return res == true;
  }

  static Widget _miniStat(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    final slug = widget.anime.slug;
    final eps = widget.anime.episodes;
    final downloaded = _dl.downloadedEpisodes(slug);
    final failures = _dl.failures.value;
    final pendingCount = eps
        .where((e) =>
            !downloaded.contains(e.number) && !_dl.isQueued(slug, e.number))
        .length;
    final showDubToggle = _dubAvailable || _dubEpCached != null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Descargar capítulos',
                            style: TextStyle(
                                color: Color(0xFFe8e4f0),
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        SizedBox(height: 2),
                        Text(widget.anime.title,
                            style: const TextStyle(
                                color: Color(0xFF6d6488), fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF6d6488)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1e1832), height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _miniStat('${downloaded.length} descargados',
                      const Color(0xFF22c55e)),
                  const SizedBox(width: 8),
                  _miniStat('$pendingCount disponibles', const Color(0xFF3b82f6)),
                  const Spacer(),
                  if (_probingDub)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (showDubToggle)
                    _DubToggle(
                      value: _preferDub,
                      onChanged: (v) => setState(() => _preferDub = v),
                    ),
                ],
              ),
            ),
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 84,
                  childAspectRatio: 1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: eps.length,
                itemBuilder: (ctx, i) => _EpTile(
                  key: ValueKey('dl_${slug}_${eps[i].number}'),
                  parent: this,
                  ep: eps[i].number,
                  downloaded: downloaded.contains(eps[i].number),
                  queued: _dl.isQueued(slug, eps[i].number),
                  failure: failures['$slug#${eps[i].number}'],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: Color(0xFF0a0812),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: downloaded.isEmpty
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF110e1a),
                                  title: const Text('Borrar todas las descargas',
                                      style: TextStyle(
                                          color: Color(0xFFe8e4f0))),
                                  content: Text(
                                      '¿Eliminar las ${downloaded.length} descargas de este anime?',
                                      style: const TextStyle(
                                          color: Color(0xFFa99fc0))),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancelar',
                                          style: TextStyle(
                                              color: Color(0xFF6d6488))),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Eliminar',
                                          style: TextStyle(
                                              color: Color(0xFFef4444))),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await _dl.deleteAnime(slug);
                                if (mounted) setState(() {});
                              }
                            },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Borrar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFef4444),
                        side: const BorderSide(color: Color(0xFF2a1520)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: pendingCount == 0
                          ? null
                          : () => _enqueue({
                                for (final e in eps)
                                  if (!downloaded.contains(e.number) &&
                                      !_dl.isQueued(slug, e.number))
                                    e.number
                              }),
                      icon: const Icon(Icons.select_all, size: 18),
                      label: const Text('Todo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFa78bfa),
                        side: const BorderSide(color: Color(0xFF3b2f5c)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_selected.isEmpty || _enqueued)
                              ? null
                              : () => _enqueue(_selected),
                      icon: Icon(_enqueued ? Icons.schedule : Icons.download),
                      label: Text(
                        _enqueued
                            ? 'En cola'
                            : _selected.isEmpty
                                ? 'Selecciona capítulos'
                                : 'Descargar ${_selected.length}',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8b5cf6),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF1e1832),
                        disabledForegroundColor: const Color(0xFF4a4260),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Switch compacto de doblaje para el header del sheet.
class _DubToggle extends StatelessWidget {
  const _DubToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: value
              ? const Color(0xFF8b5cf6).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value ? const Color(0xFF8b5cf6) : const Color(0xFF3a3350),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.record_voice_over_rounded,
                size: 13,
                color: value ? const Color(0xFFa78bfa) : const Color(0xFF6d6488)),
            const SizedBox(width: 4),
            Text(
              'Doblaje',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: value ? const Color(0xFFa78bfa) : const Color(0xFFa99fc0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile de episodio del selector. Estados:
/// - descargado: GRIS con número apagado + X roja para borrar.
/// - en cola: ámbar con spinner de progreso + X para cancelar.
/// - error: rojo con icono de reintento.
/// - visto (historial): punto azul arriba-izquierda.
/// - normal: checkbox de selección (empieza desmarcado).
class _EpTile extends StatelessWidget {
  const _EpTile({
    super.key,
    required this.parent,
    required this.ep,
    required this.downloaded,
    required this.queued,
    required this.failure,
  });

  final _DownloadSheetState parent;
  final int ep;
  final bool downloaded;
  final bool queued;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final widget = parent.widget;
    final dl = parent._dl;
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: dl.progress,
      builder: (context, progressMap, _) {
        final progress = progressMap['${widget.anime.slug}#$ep'];
        final selected = parent._selected.contains(ep);
        final watched = parent._watchedNumbers.contains(ep);

        Color border = const Color(0xFF1e1832);
        Color fill = const Color(0xFF110e1a);
        Widget content;

        if (downloaded) {
          // Ya está en disco: gris, no seleccionable, X para eliminar.
          border = const Color(0xFF2a2440);
          fill = const Color(0xFF1a1626);
          content = Stack(
            alignment: Alignment.center,
            children: [
              Text('$ep',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4a4260))),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () async {
                    if (await parent._confirmDelete(ep)) {
                      await parent._deleteEpisode(ep);
                    }
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 13, color: Color(0xFFef4444)),
                ),
              ),
            ],
          );
        } else if (queued) {
          border = const Color(0xFFf59e0b);
          fill = const Color(0xFF1a1530);
          content = Stack(
            alignment: Alignment.center,
            children: [
              if (progress != null)
                CircularProgressIndicator(
                  value: progress >= 0 && progress <= 1 ? progress : null,
                  strokeWidth: 2.4,
                  color: const Color(0xFFf59e0b),
                )
              else
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: const Color(0xFFf59e0b),
                  ),
                ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () => dl.cancelQueued(widget.anime.slug, episode: ep),
                  child: const Icon(Icons.close_rounded,
                      size: 13, color: Color(0xFFef4444)),
                ),
              ),
            ],
          );
        } else if (failure != null) {
          border = const Color(0xFFef4444);
          content = Stack(
            alignment: Alignment.center,
            children: [
              Text('$ep',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Positioned(
                bottom: 2,
                right: 2,
                child: GestureDetector(
                  onTap: () {
                    dl.enqueueAnime(
                      animeId: widget.anime.id,
                      slug: widget.anime.slug,
                      title: widget.anime.title,
                      synopsis: widget.anime.synopsis,
                      posterUrl: widget.anime.poster,
                      episodeNumbers: [ep],
                      preferDub: parent._preferDub,
                      detail: widget.anime,
                    );
                  },
                  child: const Icon(Icons.refresh_rounded,
                      size: 13, color: Color(0xFFf59e0b)),
                ),
              ),
            ],
          );
        } else {
          // Seleccionable normal (checkbox empieza vacío).
          if (selected) {
            border = const Color(0xFF8b5cf6);
            fill = const Color(0xFF241b45);
          }
          content = Stack(
            alignment: Alignment.center,
            children: [
              Text('$ep',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? Colors.white : const Color(0xFFa99fc0))),
              if (watched)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3b82f6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Positioned(
                top: 3,
                right: 3,
                child: Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 14,
                  color: selected
                      ? const Color(0xFFa78bfa)
                      : const Color(0xFF4a4260),
                ),
              ),
            ],
          );
        }

        return GestureDetector(
          onTap: downloaded || queued
              ? null
              : () => parent._toggleSelect(ep),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(9),
              border:
                  Border.all(color: border, width: downloaded || queued ? 2 : 1.4),
            ),
            padding: const EdgeInsets.all(4),
            child: content,
          ),
        );
      },
    );
  }
}
