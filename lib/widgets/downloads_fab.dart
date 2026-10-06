import 'dart:io';

import 'package:flutter/material.dart';

import '../services/download_service.dart';
import 'downloads_manager_sheet.dart';

/// Botón flotante para consultar el progreso global de descargas.
class DownloadsFab extends StatelessWidget {
  const DownloadsFab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: DownloadService.instance.progress,
      builder: (context, progress, _) {
        final queue = DownloadService.instance.queueSnapshot();
        if (queue.isEmpty) return const SizedBox.shrink();
        var sum = 0.0;
        for (final v in progress.values) {
          sum += v.clamp(0.0, 1.0);
        }
        final avg = progress.isEmpty ? 0.0 : sum / progress.length;
        final poster =
            DownloadService.instance.posterPathFor(queue.first['slug']!);
        return FloatingActionButton(
          heroTag: 'downloads_fab',
          backgroundColor: const Color(0xFF110e1a),
          elevation: 4,
          onPressed: () => showDownloadsManager(context),
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: ClipOval(
                  child: poster != null && File(poster).existsSync()
                      ? Image.file(
                          File(poster),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              const _FallbackIcon(),
                        )
                      : const _FallbackIcon(),
                ),
              ),
              SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(
                  value: avg <= 0 ? null : avg,
                  strokeWidth: 3,
                  color: const Color(0xFF8b5cf6),
                  backgroundColor: Colors.white24,
                  strokeCap: StrokeCap.round,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1e1832),
      child: const Icon(
        Icons.download_rounded,
        size: 22,
        color: Color(0xFFa78bfa),
      ),
    );
  }
}
