import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'cover_palette.dart';

/// Fondo ambiental índigo, estático, con textura de papel.
///
/// La aurora se rasteriza una sola vez a baja resolución y se dibuja como
/// textura. Encima se aplica un grano fino repetido, generado por código, que
/// quita la planitud del degradado sin costo de memoria apreciable.
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

class _AmbientBackdropState extends State<AmbientBackdrop> {
  static const int _textureWidth = 480;
  static const int _textureHeight = 270;
  static const int _grainSize = 256;

  CoverPalette _palette = CoverPalette.fallback;
  ui.Image? _texture;
  ui.Image? _grain;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _resolve();
    _loadGrain();
  }

  @override
  void didUpdateWidget(covariant AmbientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _resolve();
  }

  @override
  void dispose() {
    _texture?.dispose();
    super.dispose();
  }

  Future<void> _loadGrain() async {
    final grain = await _GrainTile.of();
    if (!mounted) return;
    setState(() => _grain = grain);
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                RawImage(
                  image: image,
                  fit: BoxFit.cover,
                  width: w,
                  height: h,
                  filterQuality: FilterQuality.medium,
                ),
                if (_grain != null)
                  CustomPaint(
                    painter: _GrainPainter(_grain!, 0.55),
                    size: Size(w, h),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Grano de papel generado una sola vez y compartido por todas las instancias.
abstract final class _GrainTile {
  static ui.Image? _image;
  static Future<ui.Image>? _pending;

  static Future<ui.Image> of() {
    final ready = _image;
    if (ready != null) return Future.value(ready);
    return _pending ??= _generate();
  }

  static Future<ui.Image> _generate() async {
    const size = _AmbientBackdropState._grainSize;
    final pixels = Uint8List(size * size * 4);
    final rng = math.Random(17);

    for (var y = 0; y < size; y++) {
      // Fibras horizontales tenues cada 23 px, como el grano del papel.
      final fiber = (y % 23 == 0) ? 16 : 0;
      for (var x = 0; x < size; x++) {
        final base = 110 + rng.nextInt(70);
        final value = (base + fiber).clamp(0, 255);
        final offset = (y * size + x) * 4;
        pixels[offset] = value;
        pixels[offset + 1] = value;
        pixels[offset + 2] = value;
        pixels[offset + 3] = 20;
      }
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: size,
      height: size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    descriptor.dispose();
    buffer.dispose();
    _image = frame.image;
    return frame.image;
  }
}

/// Pinta el grano repetido sobre toda la superficie con un shader de imagen.
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.grain, this.strength);

  final ui.Image grain;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = Float64List.fromList(<double>[
      1, 0, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1, //
    ]);
    final paint = Paint()
      ..shader = ui.ImageShader(
        grain,
        TileMode.repeated,
        TileMode.repeated,
        matrix,
      )
      ..color = Color.fromRGBO(255, 255, 255, strength);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) =>
      oldDelegate.grain != grain || oldDelegate.strength != strength;
}