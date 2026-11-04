import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Panel de vidrio para controles flotantes y hojas.
///
/// Usa `BackdropFilter`, que se re-blurea cada frame. Reservado para pocos
/// elementos fijos por pantalla; nunca dentro de listas que hacen scroll.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 14,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.borderRadius,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final double blur;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.lg);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? AppColors.glass,
              borderRadius: radius,
              border: Border.all(color: borderColor ?? AppColors.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
