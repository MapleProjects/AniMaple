import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Paleta extraída de una portada.
class CoverPalette {
  const CoverPalette({
    required this.base,
    required this.accentA,
    required this.accentB,
  });

  /// Color profundo que hace de fondo.
  final Color base;

  /// Primer acento, derivado del color dominante.
  final Color accentA;

  /// Segundo acento, derivado del color secundario.
  final Color accentB;

  static const fallback = CoverPalette(
    base: AppColors.bg,
    accentA: AppColors.primaryDeep,
    accentB: AppColors.accent,
  );
}

/// Extrae y memoriza los colores dominantes de una portada.
///
/// Decodifica la imagen a 16 px, cuenta los píxeles por cubo de color y
/// devuelve dos acentos más un fondo profundo. El resultado se cachea por URL,
/// así que cada portada se procesa una sola vez por sesión.
abstract final class CoverPaletteStore {
  static final Map<String, CoverPalette> _cache = {};
  static final Map<String, Future<CoverPalette>> _pending = {};

  /// Devuelve la paleta ya calculada, si existe.
  static CoverPalette? peek(String? url) {
    if (url == null || url.isEmpty) return null;
    return _cache[url];
  }

  static Future<CoverPalette> of(String? url) {
    if (url == null || url.isEmpty) return Future.value(CoverPalette.fallback);
    final cached = _cache[url];
    if (cached != null) return Future.value(cached);
    final pending = _pending[url];
    if (pending != null) return pending;

    final future = _extract(url)
        .then((palette) {
          _cache[url] = palette;
          return palette;
        })
        .catchError((_) => CoverPalette.fallback)
        .whenComplete(() => _pending.remove(url));
    _pending[url] = future;
    return future;
  }

  static Future<CoverPalette> _extract(String url) async {
    final provider = ResizeImage.resizeIfNeeded(
      16,
      null,
      CachedNetworkImageProvider(url),
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ui.Image>();

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    final image = await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('palette'),
    );

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return CoverPalette.fallback;
      return _quantize(data.buffer.asUint8List(), image.width * image.height);
    } finally {
      image.dispose();
    }
  }

  static CoverPalette _quantize(List<int> rgba, int pixels) {
    final buckets = <int, int>{};
    final sums = <int, List<int>>{};

    for (var i = 0; i < pixels; i++) {
      final o = i * 4;
      if (o + 3 >= rgba.length) break;
      final a = rgba[o + 3];
      if (a < 160) continue;
      final r = rgba[o];
      final g = rgba[o + 1];
      final b = rgba[o + 2];

      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      // Descarta negros, blancos y grises planos: no aportan identidad.
      if (hsv.value < 0.12 || hsv.value > 0.96) continue;
      if (hsv.saturation < 0.12) continue;

      final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      buckets[key] = (buckets[key] ?? 0) + 1;
      final acc = sums.putIfAbsent(key, () => [0, 0, 0, 0]);
      acc[0] += r;
      acc[1] += g;
      acc[2] += b;
      acc[3] += 1;
    }

    if (buckets.isEmpty) return CoverPalette.fallback;

    final ranked = buckets.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));

    Color colorOf(int key) {
      final acc = sums[key]!;
      final n = acc[3].clamp(1, 1 << 20);
      return Color.fromARGB(255, acc[0] ~/ n, acc[1] ~/ n, acc[2] ~/ n);
    }

    final first = colorOf(ranked.first.key);
    var second = colorOf(ranked.length > 1 ? ranked[1].key : ranked.first.key);

    // Si el segundo es casi el mismo tono, busca el siguiente distinto.
    final firstHue = HSVColor.fromColor(first).hue;
    for (var i = 1; i < ranked.length && i < 8; i++) {
      final candidate = colorOf(ranked[i].key);
      final delta = (HSVColor.fromColor(candidate).hue - firstHue).abs();
      if (delta > 25 && delta < 335) {
        second = candidate;
        break;
      }
    }

    return CoverPalette(
      base: _indigo(first, saturation: 0.62, value: 0.15),
      accentA: _indigo(first, saturation: 0.80, value: 0.60),
      accentB: _indigo(second, saturation: 0.72, value: 0.48),
    );
  }

  /// Lleva el tono hacia índigo (morado azulado) para un fondo coherente.
  static Color _indigo(
    Color color, {
    required double saturation,
    required double value,
  }) {
    final hsv = HSVColor.fromColor(color);
    const target = 258.0;
    final delta = ((target - hsv.hue + 540) % 360) - 180;
    final hue = (hsv.hue + delta * 0.65 + 360) % 360;
    return HSVColor.fromAHSV(
      1,
      hue,
      saturation.clamp(0.0, 1.0),
      value.clamp(0.0, 1.0),
    ).toColor();
  }
}
