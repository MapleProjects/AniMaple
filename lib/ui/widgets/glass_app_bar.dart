import 'package:flutter/material.dart';

import '../tokens.dart';

/// Cabecera translúcida sobre el contenido.
///
/// Usa un velo semitransparente y un borde inferior en lugar de
/// `BackdropFilter`: el resultado visual es vidrio, pero sin el costo de
/// re-desenfocar la pantalla en cada frame.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;

  /// Altura de la barra definida en AppTheme (toolbarHeight).
  static const double toolbarHeight = 60;

  /// Espacio que debe reservar el contenido para no quedar bajo la cabecera.
  static double inset(BuildContext context, {double extra = 0}) {
    final top =
        MediaQuery.paddingOf(context).top >
            MediaQuery.viewPaddingOf(context).top
        ? MediaQuery.paddingOf(context).top
        : MediaQuery.viewPaddingOf(context).top;
    return top + toolbarHeight + extra;
  }

  /// Altura a reservar cuando el cuerpo ya arranca debajo de la barra de estado.
  static double contentInset({double extra = 0}) => toolbarHeight + extra;

  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.bg.withValues(alpha: 0.72),
            AppColors.bg.withValues(alpha: 0.50),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: AppBar(
        title: title,
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: automaticallyImplyLeading,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: bottom,
      ),
    );
  }
}
