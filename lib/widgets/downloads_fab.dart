import 'dart:io';

import 'package:flutter/material.dart';

import '../services/download_service.dart';
import 'downloads_manager_sheet.dart';

/// Botón flotante global de descargas.
///
/// Muestra la imagen del anime descargándose dentro del anillo de progreso.
/// Optimización: SOLO este widget se reconstruye con la cola; el progreso
/// en vivo vive dentro del sheet del gestor.
class DownloadsFab extends StatelessWidget {
  const DownloadsFab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: DownloadService.instance.progress,
      builder: (context, progress, _) {
        final queue = DownloadService.instance.queueSnapshot();
        if (queue.isEmpty) return const SizedBox.shrink();
        // Progreso promedio para el anillo; cálculo barato.
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
              // Imagen del anime en curso, recortada en círculo.
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
              // Anillo de progreso por encima.
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
