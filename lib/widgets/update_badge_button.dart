import 'package:flutter/material.dart';
import '../services/update_service.dart';

/// Botón-badge que aparece junto al avatar de cuenta cuando hay una
/// actualización disponible. Al tocarlo muestra el mismo diálogo de
/// Actualizar/Posponer que al arranque, para que el usuario no olvide
/// actualizar si pospuso la ventana inicial.
class UpdateBadgeButton extends StatelessWidget {
  const UpdateBadgeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: UpdateService.hasUpdate,
      builder: (context, hasUpdate, _) {
        if (!hasUpdate) return const SizedBox.shrink();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: GestureDetector(
                onTap: () async {
                  final update = await UpdateService.showUpdateDialog(context);
                  if (update == true && context.mounted) {
                    await UpdateService.downloadAndInstall(context);
                  }
                },
                child: const Icon(
                  Icons.system_update_alt,
                  size: 24,
                  color: Color(0xFFa78bfa),
                ),
              ),
            ),
            const Positioned(
              top: 0,
              right: 0,
              child: _Dot(),
            ),
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFF8b5cf6),
        shape: BoxShape.circle,
      ),
    );
  }
}
