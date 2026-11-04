import 'package:flutter/material.dart';

import '../tokens.dart';

/// Cabecera flotante translúcida.
///
/// Se coloca como capa superior dentro del cuerpo de la página, no como
/// `Scaffold.appBar`, para que el contenido se desplace por debajo y se vea a
/// través del velo.
class GlassHeader extends StatelessWidget {
  const GlassHeader({
    super.key,
    this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.height = 60,
  });

  final Widget? title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;

  /// Altura de la barra; 44 para cabeceras compactas.
  final double height;

  static const double toolbarHeight = 60;

  /// Altura total que debe reservar el contenido.
  static double heightOf(
    BuildContext context, {
    double extra = 0,
    double height = 60,
    bool withStatusBar = true,
  }) {
    final status = withStatusBar ? MediaQuery.paddingOf(context).top : 0.0;
    return status + height + extra;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.bg.withValues(alpha: 0.62),
            AppColors.bg.withValues(alpha: 0.34),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          SizedBox(
            height: height,
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppSpace.xs),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: title ?? const SizedBox.shrink(),
                  ),
                ),
                ...?actions,
                const SizedBox(width: AppSpace.sm),
              ],
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}
