import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/download_service.dart';
import '../ui/tokens.dart';

/// Gestor modal de descargas con pestañas de cola y elementos completados.
Future<void> showDownloadsManager(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const DownloadsManagerSheet(),
  );
}

class DownloadsManagerSheet extends StatefulWidget {
  const DownloadsManagerSheet({super.key});

  @override
  State<DownloadsManagerSheet> createState() => _DownloadsManagerSheetState();
}

class _DownloadsManagerSheetState extends State<DownloadsManagerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  Ticker? _ticker;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    // Actualiza la lista de elementos periódicamente.
    _ticker = createTicker((_) {
      if (mounted && _tick++ % 30 == 0) {
        setState(() {});
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker?.stop();
    _tabs.dispose();
    super.dispose();
  }

  static String _fmtBytes(int b) {
    if (b <= 0) return '';
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).round()} MB';
    return '${(b / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.instance;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Descargas',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            TabBar(
              controller: _tabs,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Descargando'),
                Tab(text: 'Completados'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_buildActiveTab(svc), _buildCompletedTab(svc)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab(DownloadService svc) {
    final queue = svc.queueSnapshot();
    final failures = svc.failures.value;

    if (queue.isEmpty && failures.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_done_rounded,
              size: 44,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 8),
            Text(
              'Sin descargas activas.\nLos episodios en cola aparecen aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final failedKeys = failures.keys.toList();
    final rows = <Widget>[
      for (final item in queue)
        _QueueRow(
          key: ValueKey('q_${item['key']}'),
          slug: item['slug']!,
          episode: int.parse(item['episode']!),
        ),
      if (failedKeys.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 15,
                color: AppColors.danger,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '${failedKeys.length} con error',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    DownloadService.instance.retryFailed(failedKeys),
                child: const Text('Reintentar todo'),
              ),
            ],
          ),
        ),
        for (final k in failedKeys)
          ListTile(
            dense: true,
            leading: const Icon(Icons.error_outline, color: AppColors.danger),
            title: Text(
              '${svc.titleFor(k.substring(0, k.indexOf('#')))} — Ep ${k.substring(k.indexOf('#') + 1)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.text, fontSize: 13.5),
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppColors.primaryBright,
                size: 21,
              ),
              tooltip: 'Reintentar',
              onPressed: () => DownloadService.instance.retryFailed([k]),
            ),
          ),
      ],
    ];

    return ListView(children: rows);
  }

  Widget _buildCompletedTab(DownloadService svc) {
    final done = svc.recentCompleted.value;
    if (done.isEmpty) {
      return Center(
        child: Text(
          'Aquí aparecerán los episodios\ndescargados en esta sesión.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            height: 1.5,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: done.length,
      itemExtent: 64,
      itemBuilder: (context, i) {
        final e = done[i];
        final poster = svc.posterPathFor(e['slug'] as String);
        final posterFile = poster != null && File(poster).existsSync()
            ? File(poster)
            : null;
        return ListTile(
          dense: true,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 52,
              child: posterFile != null
                  ? Image.file(
                      posterFile,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const _DoneIcon(),
                    )
                  : const _DoneIcon(),
            ),
          ),
          title: Text(
            '${e['title']} — Ep ${e['episode']}${e['dub'] == true ? ' · DUB' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.text, fontSize: 13.5),
          ),
          subtitle: Text(
            'Guardado · ${_fmtBytes((e['bytes'] as num?)?.toInt() ?? 0)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.textMuted,
              size: 20,
            ),
            tooltip: 'Eliminar descarga',
            onPressed: () async {
              await DownloadService.instance.deleteEpisode(
                e['slug'] as String,
                e['episode'] as int,
              );
              if (mounted) setState(() {});
            },
          ),
        );
      },
    );
  }
}

class _DoneIcon extends StatelessWidget {
  const _DoneIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: const Icon(
        Icons.check_circle_rounded,
        color: AppColors.success,
        size: 22,
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.slug, required this.episode});

  final String slug;
  final int episode;

  @override
  Widget build(BuildContext context) {
    final svc = DownloadService.instance;
    final key = '$slug#$episode';
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: svc.progress,
      builder: (context, progress, _) {
        final active = progress.containsKey(key);
        final frac = progress[key] ?? 0.0;
        final posterPath = svc.posterPathFor(slug);
        final posterFile = posterPath != null && File(posterPath).existsSync()
            ? File(posterPath)
            : null;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: ClipOval(
                    child: posterFile != null
                        ? Image.file(
                            posterFile,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                const _QueueFallback(),
                          )
                        : const _QueueFallback(),
                  ),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: frac > 0 && frac <= 1 ? frac : null,
                    strokeWidth: 2.6,
                    color: AppColors.primary,
                    backgroundColor: Colors.white12,
                    strokeCap: StrokeCap.round,
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            '${svc.titleFor(slug)} — Ep $episode',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.text, fontSize: 13.5),
          ),
          subtitle: active
              ? Text(
                  '${(frac * 100).floor()}%',
                  style: const TextStyle(
                    color: AppColors.primaryBright,
                    fontSize: 11.5,
                  ),
                )
              : const Text(
                  'En espera…',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
          trailing: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
            tooltip: 'Cancelar',
            onPressed: () => svc.cancelQueued(slug, episode: episode),
          ),
        );
      },
    );
  }
}

class _QueueFallback extends StatelessWidget {
  const _QueueFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.outline,
      child: const Icon(
        Icons.movie_rounded,
        size: 18,
        color: AppColors.primaryBright,
      ),
    );
  }
}
