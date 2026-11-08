import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'cover_palette.dart';

/// Fondo ambiental índigo con movimiento lento tipo aurora.
///
/// El degradado completo se rasteriza una sola vez a baja resolución y se
/// dibuja como textura. Una textura de 480x270 ocupa 0,5 MB, frente a los
/// cientos de MB que costaba pintar las manchas a tamaño completo. El
/// movimiento se aplica con una transformación de compositor, así que la
/// apariencia se mantiene sin repintar.
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
    with WidgetsBindingObserver {
  static const int _textureWidth = 480;
  static const int _textureHeight = 270;

  /// El desplazamiento es muy lento: dos actualizaciones por segundo bastan y
  /// evitan pedir frames a 60 fps para un movimiento casi imperceptible.
  static const Duration _driftStep = Duration(milliseconds: 500);

  CoverPalette _palette = CoverPalette.fallback;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Timer? _driftTimer;
  bool _reduceMotion = false;
  ui.Image? _texture;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDrift();
    _resolve();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sin foco no se anima: cero frames mientras la ventana está en segundo
    // plano.
    if (state == AppLifecycleState.resumed) {
      _startDrift();
    } else {
      _stopDrift();
    }
  }

  void _startDrift() {
    if (_driftTimer != null) return;
    _driftTimer = Timer.periodic(_driftStep, (_) {
      if (_reduceMotion) return;
      // Ciclo completo en 24 s.
      _phase.value = (_phase.value + _driftStep.inMilliseconds / 24000) % 1.0;
    });
  }

  void _stopDrift() {
    _driftTimer?.cancel();
    _driftTimer = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      _stopDrift();
    } else {
      _startDrift();
    }
  }

  @override
  void didUpdateWidget(covariant AmbientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolve();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDrift();
    _phase.dispose();
    _texture?.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _palette = CoverPalette.fallback);
      await _rebuildTexture();
      return;
    }

    final cached = CoverPaletteStore.peek(url);
    if (cached != null) {
      setState(() => _palette = cached);
      await _rebuildTexture();
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
      await _rebuildTexture();
      return;
    }
    setState(() => _palette = palette);
    await _rebuildTexture();
  }

  Future<void> _rebuildTexture() async {
    if (_rendering) return;
    _rendering = true;
    try {
      final image = await _renderAurora(
        width: _textureWidth,
        height: _textureHeight,
        palette: _palette,
        opacity: widget.opacity.clamp(0.0, 1.0),
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      final previous = _texture;
      setState(() => _texture = image);
      previous?.dispose();
    } finally {
      _rendering = false;
    }
  }

  /// Dibuja la aurora completa en un lienzo pequeño. Al escalarla se ve igual
  /// porque son degradados suaves, sin detalle que perder.
  static Future<ui.Image> _renderAurora({
    required int width,
    required int height,
    required CoverPalette palette,
    required double opacity,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = width.toDouble();
    final h = height.toDouble();
    final rect = Rect.fromLTWH(0, 0, w, h);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          const [Color(0xFF0D0D24), AppColors.bgDeep],
        ),
    );

    final tint = Color.lerp(AppColors.primaryDeep, palette.accentA, 0.35)!;
    final blob = w * 1.15;

    void drawBlob(Offset center, double size, Color color, double alpha) {
      if (alpha <= 0) return;
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, size / 2, [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.45),
          color.withValues(alpha: 0.0),
        ], const [0.0, 0.55, 1.0]);
      canvas.drawCircle(center, size / 2, paint);
    }

    drawBlob(
      Offset(-blob * 0.30 + w * 0.06, -blob * 0.35 + h * 0.03),
      blob,
      AppColors.primary,
      0.42 * opacity,
    );
    drawBlob(
      Offset(w - blob * 0.25 + w * 0.04, h * 0.30 - h * 0.05),
      blob * 1.1,
      tint,
      0.40 * opacity,
    );
    drawBlob(
      Offset(w * 0.05 - w * 0.03, h - blob * 0.45 + h * 0.03),
      blob * 0.95,
      AppColors.accent,
      0.12 * opacity,
    );

    // Velo vertical de contraste para el contenido.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          [
            AppColors.bg.withValues(alpha: 0.05),
            AppColors.bg.withValues(alpha: 0.30),
            AppColors.bg.withValues(alpha: 0.80),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final image = _texture;

          if (image == null) {
            return const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0D0D24), AppColors.bgDeep],
                ),
              ),
            );
          }

          return ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: _phase,
              builder: (context, phase, child) {
                final t = phase * 2 * math.pi;
                // Traslación de compositor: no vuelve a rasterizar la textura.
                return Transform.translate(
                  offset: Offset(
                    math.sin(t) * w * 0.012,
                    math.cos(t * 0.9) * h * 0.012,
                  ),
                  child: child,
                );
              },
              child: RawImage(
                image: image,
                fit: BoxFit.cover,
                width: w,
                height: h,
                filterQuality: FilterQuality.medium,
              ),
            ),
          );
        },
      ),
    );
  }
}