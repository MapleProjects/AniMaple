import 'package:flutter/material.dart';

import '../tokens.dart';

/// Estilo visual de una etiqueta.
enum BadgeTone { soft, solid, outline }

/// Etiqueta compacta para metadatos: episodio, estado, género o tiempo.
class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.tone = BadgeTone.soft,
    this.icon,
  });

  final String label;
  final Color color;
  final BadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (tone) {
      BadgeTone.soft => (
        color.withValues(alpha: 0.16),
        color,
        color.withValues(alpha: 0.28),
      ),
      BadgeTone.solid => (color, Colors.white, Colors.transparent),
      BadgeTone.outline => (
        Colors.transparent,
        color,
        color.withValues(alpha: 0.55),
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? AppSpace.sm : AppSpace.sm + 1,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: AppSpace.xs),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
