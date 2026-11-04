import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../tokens.dart';

/// Bloque gris animado que representa contenido en carga.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Aplica un único efecto shimmer a todo el subárbol.
///
/// Un solo `Shimmer` por pantalla: instanciarlo por tarjeta multiplica los
/// shaders y provoca jank en GPUs móviles.
class SkeletonScope extends StatelessWidget {
  const SkeletonScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceHigh,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// Rejilla de pósters en carga.
class SkeletonPosterGrid extends StatelessWidget {
  const SkeletonPosterGrid({
    super.key,
    this.itemCount = 12,
    this.extent = AppLayout.posterExtent,
    this.aspect = AppLayout.posterAspect,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.page),
  });

  final int itemCount;
  final double extent;
  final double aspect;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: extent,
          childAspectRatio: aspect,
          crossAxisSpacing: AppSpace.md,
          mainAxisSpacing: AppSpace.lg,
        ),
        itemCount: itemCount,
        itemBuilder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(child: SkeletonBox(radius: AppRadius.md)),
            SizedBox(height: AppSpace.sm),
            SkeletonBox(height: 10, radius: AppRadius.xs),
            SizedBox(height: AppSpace.xs),
            SkeletonBox(width: 76, height: 8, radius: AppRadius.xs),
          ],
        ),
      ),
    );
  }
}

/// Carrusel horizontal en carga.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({
    super.key,
    this.itemCount = 5,
    this.cardWidth = AppLayout.rowCardWidth,
    this.height = AppLayout.rowHeight,
  });

  final int itemCount;
  final double cardWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SkeletonScope(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          itemCount: itemCount,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
          itemBuilder: (_, __) => SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(child: SkeletonBox(radius: AppRadius.md)),
                SizedBox(height: AppSpace.sm),
                SkeletonBox(height: 10, radius: AppRadius.xs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloque de texto en carga.
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.lines = 3, this.spacing = AppSpace.sm});

  final int lines;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(lines, (i) {
          final last = i == lines - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : spacing),
            child: SkeletonBox(
              width: last ? 180 : null,
              height: 10,
              radius: AppRadius.xs,
            ),
          );
        }),
      ),
    );
  }
}
