import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';
import '../../widgets/tv_focusable.dart';

/// Tarjeta de póster única de la aplicación.
///
/// Reemplaza las implementaciones duplicadas de inicio, catálogo, historial,
/// favoritos y calendario. Requiere una altura acotada por el padre (celda de
/// rejilla o carrusel) porque la imagen ocupa el espacio restante.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.subtitle,
    this.badge,
    this.badgeColor,
    this.progress,
    this.favorite = false,
    this.placeholderIcon = Icons.movie_outlined,
    this.autofocus = false,
    this.onLongPress,
    this.titleMaxLines = 2,
    this.action,
  });

  final String title;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? subtitle;

  /// Etiqueta sobre la portada, por ejemplo `Ep 12`.
  final String? badge;
  final Color? badgeColor;

  /// Progreso de visionado entre 0 y 1. Se omite si es nulo.
  final double? progress;

  /// Muestra el corazón de favorito en la esquina superior derecha.
  final bool favorite;

  final IconData placeholderIcon;
  final bool autofocus;
  final VoidCallback? onLongPress;
  final int titleMaxLines;

  /// Acción superpuesta en la esquina superior derecha (por ejemplo, borrar).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cellWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 180.0;
        final decodeWidth = (cellWidth * dpr).round().clamp(96, 720);

        return TvFocusable(
          onTap: onTap,
          onLongPress: onLongPress,
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(AppRadius.md),
          scaleOnFocus: 1.03,
          enableGlow: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RepaintBoundary(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _PosterImage(
                          url: imageUrl,
                          decodeWidth: decodeWidth,
                          placeholderIcon: placeholderIcon,
                          label: title,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppGradients.imageVeil,
                          ),
                        ),
                        if (badge != null)
                          Positioned(
                            left: AppSpace.sm,
                            bottom: AppSpace.sm,
                            child: _Badge(
                              text: badge!,
                              color: badgeColor ?? AppColors.primary,
                            ),
                          ),
                        if (favorite)
                          Positioned(
                            left: AppSpace.sm,
                            top: AppSpace.sm,
                            child: Container(
                              padding: const EdgeInsets.all(AppSpace.xs),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.favorite,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        if (action != null)
                          Positioned(
                            right: AppSpace.xs,
                            top: AppSpace.xs,
                            child: action!,
                          ),
                        if (progress != null && progress! > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _ProgressBar(
                              value: progress!.clamp(0.0, 1.0),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                title,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall,
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({
    required this.url,
    required this.decodeWidth,
    required this.placeholderIcon,
    required this.label,
  });

  final String? url;
  final int decodeWidth;
  final IconData placeholderIcon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fallback = _PosterFallback(icon: placeholderIcon, label: label);

    if (url == null || url!.isEmpty) return fallback;

    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: decodeWidth,
      filterQuality: FilterQuality.medium,
      fadeInDuration: AppMotion.slow,
      fadeInCurve: AppMotion.curve,
      placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceHigh),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}

/// Portada ausente: degradado de marca con las iniciales del título.
class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.icon, required this.label});

  final IconData icon;
  final String label;

  String get _initials {
    final words = label
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2);
    final out = words.map((w) => w.substring(0, 1).toUpperCase()).join();
    return out.isEmpty ? '?' : out;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.surfaceSheen),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textDisabled, size: 26),
            const SizedBox(height: AppSpace.xs),
            Text(
              _initials,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Row(
        children: [
          Expanded(
            flex: (value * 1000).round(),
            child: const ColoredBox(color: AppColors.primaryBright),
          ),
          Expanded(
            flex: ((1 - value) * 1000).round(),
            child: const ColoredBox(color: AppColors.outlineStrong),
          ),
        ],
      ),
    );
  }
}
