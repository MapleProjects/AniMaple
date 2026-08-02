import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/sync_service.dart';

/// Botón de sincronización en el AppBar.
/// - Sin sesión: icono de nube → inicia login con Google.
/// - Con sesión: icono de nube sincronizando + email → tap fuerza pull.
/// - Menú con opción de cerrar sesión.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key});

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> {
  bool _busy = false;
  bool _signedIn = false;
  String? _email;

  @override
  void initState() {
    super.initState();
    _signedIn = SyncService.isSignedIn;
    _email = SyncService.accountEmail;

    // Escuchar eventos de auth/sign-out en vivo.
    GoogleSignIn.instance.authenticationEvents.listen((event) {
      if (!mounted) return;
      setState(() {
        _signedIn = SyncService.isSignedIn;
        _email = SyncService.accountEmail;
      });
    });
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    setState(() => _busy = true);

    if (!_signedIn) {
      final ok = await SyncService.signIn();
      if (ok) {
        await SyncService.pull();
      }
    } else {
      await SyncService.pull();
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _signedIn = SyncService.isSignedIn;
      _email = SyncService.accountEmail;
    });

    // Mostrar el resultado al usuario (errores siempre visibles).
    final err = SyncService.lastError;
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade800),
      );
    } else if (_signedIn && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sincronizado con la nube'),
          backgroundColor: Color(0xFF8b5cf6),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _signedIn
          ? 'Sincronizado con $_email — toca para sincronizar ahora'
          : 'Sincronizar con tu cuenta Google',
      onPressed: _handleTap,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFa78bfa),
              ),
            )
          : Icon(
              _signedIn ? Icons.cloud_done_outlined : Icons.cloud_outlined,
              color: _signedIn
                  ? const Color(0xFFa78bfa)
                  : const Color(0xFF6d6488),
            ),
    );
  }
}
