import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'cover_palette.dart';

/// Fondo ambiental índigo con movimiento lento tipo aurora.
///
/// Las manchas son degradados radiales que se desvanecen a transparente en su
/// borde, así que al desplazarse nunca exponen un corte. Cada mancha se
/// rasteriza una vez en un `RepaintBoundary` y solo se reposiciona: el
/// movimiento lo resuelve el compositor, sin repintar la pantalla.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({
    super.key,
    this.imageUrl,
    this.fallbackUrl,
    this.opacity = 0.55,
  });

  /// Portada de la que se toma un matiz secundario.
  final String? imageUrl;

  /// Segunda opción si la principal no tiene paleta válida.
  final String? fallbackUrl;

  /// Intensidad del efecto, de 0 a 1.
  final double opacity;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  /// En Windows el renderizador rasteriza las capas grandes en cada fotograma
  /// y el consumo de memoria se dispara. El fondo queda estático ahí; el
  /// degradado se conserva.
  static final bool _animated = !Platform.isWindows;

  CoverPalette _palette = CoverPalette.fallback;
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
    _resolve();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_animated) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AmbientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolve();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _palette = CoverPalette.fallback);
      return;
    }

    final cached = CoverPaletteStore.peek(url);
    if (cached != null) {
      setState(() => _palette = cached);
      return;
    }

    final palette = await CoverPaletteStore.of(url);
    if (!mounted) return;
    if (palette == CoverPalette.fallback &&
        widget.fallbackUrl != null &&
        widget.fallbackUrl != url) {
      final alt = await CoverPaletteStore.of(widget.fallbackUrl);
      if (!mounted) return;
      setState(() => _palette = alt);
      return;
    }
    setState(() => _palette = palette);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.opacity.clamp(0.0, 1.0);

    // En Windows las manchas de degradado a pantalla completa cuestan cientos
    // de MB en el rasterizador. Se usa solo el degradado base.
    if (Platform.isWindows) {
      return const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D0D24), AppColors.bgDeep],
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final blob = w * (_animated ? 1.15 : 0.95);

          // Matiz de la portada, siempre dentro de la gama índigo.
          final tint = Color.lerp(
            AppColors.primaryDeep,
            _palette.accentA,
            0.35,
          )!;

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0D0D24), AppColors.bgDeep],
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _drift,
                  builder: (context, child) {
                    final t = _animated ? _drift.value * 2 * math.pi : 0.9;
                    final leftA =
                        (-blob * 0.30 + math.sin(t) * w * 0.10).roundToDouble();
                    final topA =
                        (-blob * 0.35 + math.cos(t * 0.9) * h * 0.05)
                            .roundToDouble();
                    final rightB =
                        (-blob * 0.25 - math.sin(t * 0.8) * w * 0.08)
                            .roundToDouble();
                    final topB =
                        (h * 0.30 + math.cos(t) * h * 0.07).roundToDouble();
                    final leftC =
                        (w * 0.05 + math.cos(t * 0.6) * w * 0.06)
                            .roundToDouble();
                    final bottomC =
                        (-blob * 0.45 - math.sin(t * 0.7) * h * 0.04)
                            .roundToDouble();
                    return Stack(
                      children: [
                        Positioned(
                          left: leftA,
                          top: topA,
                          child: _Blob(
                            size: blob,
                            color: AppColors.primary,
                            alpha: 0.42 * a,
                          ),
                        ),
                        Positioned(
                          right: rightB,
                          top: topB,
                          child: _Blob(
                            size: blob * 1.1,
                            color: tint,
                            alpha: 0.40 * a,
                          ),
                        ),
                        Positioned(
                          left: leftC,
                          bottom: bottomC,
                          child: _Blob(
                            size: blob * 0.95,
                            color: AppColors.accent,
                            alpha: 0.12 * a,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Velo vertical de contraste para el contenido.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.bg.withValues(alpha: 0.05),
                        AppColors.bg.withValues(alpha: 0.30),
                        AppColors.bg.withValues(alpha: 0.80),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Mancha circular que se desvanece a transparente en el borde.
class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color, required this.alpha});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: alpha * 0.45),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
