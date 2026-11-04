import 'package:flutter/material.dart';

/// Paleta canónica de AniMaple.
///
/// Es la única fuente de color de la aplicación: ningún widget debe declarar
/// literales `Color(0x...)`. La gama conserva el morado profundo original.
abstract final class AppColors {
  // ── Fondos ──────────────────────────────────────────────────────────────
  /// Fondo base de la aplicación.
  static const bg = Color(0xFF0A0A18);

  /// Fondo más profundo, usado en el reproductor.
  static const bgDeep = Color(0xFF070710);

  /// Superficie de tarjetas, hojas y diálogos.
  static const surface = Color(0xFF111120);

  /// Superficie elevada (cabeceras, paneles).
  static const surfaceHigh = Color(0xFF1A1A32);

  /// Superficie de máximo contraste dentro del tema oscuro.
  static const surfaceHighest = Color(0xFF262646);

  /// Bordes y divisores de bajo contraste.
  static const outline = Color(0xFF1E1E36);

  /// Bordes de elementos interactivos.
  static const outlineStrong = Color(0xFF3C3C5E);

  // ── Marca ───────────────────────────────────────────────────────────────
  static const primary = Color(0xFF7C6CFF);
  static const primaryBright = Color(0xFFA99BFF);
  static const primaryDeep = Color(0xFF5B4BD6);
  static const accent = Color(0xFFEC4899);

  // ── Texto ───────────────────────────────────────────────────────────────
  static const text = Color(0xFFE8E4F0);
  static const textStrong = Color(0xFFF3F0FA);
  static const textSecondary = Color(0xFFA99FC0);
  static const textMuted = Color(0xFF6D6488);
  static const textDisabled = Color(0xFF4A4260);

  // ── Estados ─────────────────────────────────────────────────────────────
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const dangerSoft = Color(0xFFF87171);
  static const info = Color(0xFF3B82F6);

  // ── Vidrio, scrim y transparencias ──────────────────────────────────────
  /// Relleno de panel de vidrio (blanco al 8 %).
  static const glass = Color(0x14FFFFFF);

  /// Relleno de vidrio sobre contenido claro (blanco al 14 %).
  static const glassStrong = Color(0x24FFFFFF);

  /// Borde de panel de vidrio (blanco al 12 %).
  static const glassBorder = Color(0x1FFFFFFF);

  /// Velo para texto sobre imagen (negro al 60 %).
  static const veil = Color(0x99000000);

  /// Scrim de fondo al 80 % de opacidad.
  static const scrim = Color(0xCC0A0A18);

  /// Scrim de fondo al 60 % de opacidad.
  static const scrimSoft = Color(0x990A0A18);

  /// Fondo casi opaco para degradados de héroe.
  static const bgStrong = Color(0xE60A0A18);

  /// Fondo opaco con mínima transparencia.
  static const bgOpaque = Color(0xF20A0A18);

  /// Fondo completamente transparente (extremo de degradado).
  static const bgClear = Color(0x000A0A18);

  /// Sombra base de tarjetas y hojas.
  static const shadow = Color(0x66000000);
}

/// Degradados reutilizables. Todos parten de la misma gama morada.
abstract final class AppGradients {
  /// Identidad de marca: morado a rosa.
  static const brand = LinearGradient(
    colors: [AppColors.primary, AppColors.accent],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Velo inferior sobre imágenes para garantizar contraste del texto.
  static const imageVeil = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x000A0812), Color(0x660A0812), Color(0xE60A0812)],
    stops: [0.35, 0.68, 1.0],
  );

  /// Velo lateral para héroes anchos.
  static const imageVeilWide = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xF20A0812), Color(0x990A0812), Color(0x000A0812)],
    stops: [0.0, 0.45, 1.0],
  );

  /// Superficie elevada con brillo superior.
  static const surfaceSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.surfaceHigh, AppColors.surface],
  );

  /// Borde iluminado para el foco de TV.
  static const focusRing = LinearGradient(
    colors: [AppColors.primaryBright, AppColors.accent],
  );
}

/// Escala de espaciado en múltiplos de 4.
abstract final class AppSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Margen horizontal estándar de página.
  static const page = 16.0;

  /// Margen horizontal en diseños anchos.
  static const pageWide = 32.0;
}

/// Radios de esquina.
abstract final class AppRadius {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

/// Duraciones de animación.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const backdrop = Duration(milliseconds: 420);

  static const curve = Curves.easeOutCubic;
}

/// Puntos de quiebre de layout.
abstract final class AppBreakpoints {
  /// Móvil vertical.
  static const compact = 600.0;

  /// Tableta o ventana pequeña.
  static const medium = 900.0;

  /// Escritorio o TV.
  static const expanded = 1280.0;

  /// Ancho máximo del contenido para no estirar grillas en pantallas grandes.
  static const contentMax = 1440.0;
}

/// Tamaños de texto de la escala tipográfica.
abstract final class AppTextSize {
  static const display = 32.0;
  static const h1 = 26.0;
  static const h2 = 21.0;
  static const h3 = 17.0;
  static const body = 14.0;
  static const bodySm = 13.0;
  static const label = 12.0;
  static const caption = 11.0;
  static const micro = 10.0;
}

/// Geometría compartida de rejillas y carruseles.
abstract final class AppLayout {
  /// Ancho máximo de una tarjeta de póster en rejilla (móvil).
  static const posterExtent = 180.0;

  /// Ancho máximo de una tarjeta de póster en rejilla (TV/escritorio).
  static const posterExtentWide = 210.0;

  /// Relación de aspecto de un póster 2:3.
  static const posterAspect = 0.64;

  /// Ancho de tarjeta en carrusel horizontal.
  static const rowCardWidth = 142.0;

  /// Relación de aspecto de la imagen dentro de un carrusel.
  static const rowCardAspect = 0.68;

  /// Altura reservada para el carrusel completo (imagen + textos).
  static const rowHeight = 268.0;

  /// Altura del héroe en móvil.
  static const heroHeightCompact = 320.0;

  /// Altura del héroe en TV/escritorio.
  static const heroHeightWide = 420.0;

  /// Espacio inferior para que el FAB no tape el último elemento.
  static const bottomGutter = 96.0;

  /// Ancho máximo de tarjeta en rejilla según el ancho disponible.
  static double posterExtentFor(BuildContext context) =>
      MediaQuery.sizeOf(context).width > 1100 ? 210.0 : 180.0;

  /// Ancho de tarjeta en carrusel, escalado para tablet, escritorio y TV.
  static double rowCardWidthFor(double screenWidth) =>
      (screenWidth * 0.105).clamp(132.0, 196.0);

  /// Altura de carrusel coherente con el ancho de tarjeta.
  static double rowHeightFor(double cardWidth) => cardWidth * 1.72 + 30;
}
