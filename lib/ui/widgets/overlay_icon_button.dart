import 'package:flutter/material.dart';

import '../tokens.dart';
import '../../widgets/tv_focusable.dart';

/// Botón circular oscuro para superponer sobre una portada.
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TvFocusable(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.veil.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xs + 1),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
