import 'package:flutter/material.dart';

import 'ambient_backdrop.dart';

/// Página con fondo ambiental detrás de todo, incluida la cabecera.
///
/// El `Scaffold` interno debe usar `backgroundColor: Colors.transparent` para
/// que el color de la portada se vea también bajo la barra de estado, la
/// cabecera y la navegación inferior.
class AmbientPage extends StatelessWidget {
  const AmbientPage({
    super.key,
    required this.child,
    this.imageUrl,
    this.fallbackUrl,
    this.opacity = 0.55,
  });

  final Widget child;
  final String? imageUrl;
  final String? fallbackUrl;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AmbientBackdrop(
          imageUrl: imageUrl,
          fallbackUrl: fallbackUrl,
          opacity: opacity,
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}
