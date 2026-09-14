import 'dart:async';

import 'package:flutter/material.dart';
import '../services/sync_service.dart';

/// Avatar de perfil en el AppBar.
/// - Sin sesión: avatar genérico → toca para iniciar sesión con Google.
/// - Con sesión: foto de perfil de Google + menú con "Cerrar sesión".
/// La sincronización ya es automática (polling 10s); el toque no hace pull.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key});

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton> {
  bool _signedIn = false;
  String? _email;
  String? _name;
  String? _photoUrl;

  /// Cuenta recordada de una sesión anterior (persistente). Mientras la
  /// sesión real no se restaure (p.ej. arranque sin Internet), el avatar
  /// aparece "con sesión": al tocar, en vez del login, reintenta la
  /// restauración silenciosa — igual que Windows, que carga directo.
  bool _remembered = false;

  @override
  void initState() {
    super.initState();
    _refreshFromService();
    _loadRemembered();

    // Escuchar eventos de auth/sign-out y cambios de estado en vivo.
    // google_sign_in no existe para Windows/Linux → solo en plataformas
    // soportadas; la app sigue funcionando local sin sincronización.
    if (SyncService.googleSignInSupported) {
      SyncService.onCurrentUserChanged.listen((account) {
        if (!mounted) return;
        _refreshFromService();
      });
    }
    SyncService.stateVersion.addListener(_onStateChanged);
  }

  Future<void> _loadRemembered() async {
    final has = await SyncService.hasRememberedAccount();
    if (mounted && has != _remembered) {
      setState(() => _remembered = has);
    }
  }

  @override
  void dispose() {
    SyncService.stateVersion.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    _refreshFromService();
    _loadRemembered();
  }

  void _refreshFromService() {
    setState(() {
      _signedIn = SyncService.isSignedIn;
      _email = SyncService.accountEmail;
      _name = SyncService.accountDisplayName;
      _photoUrl = SyncService.accountPhotoUrl;
    });
  }

  Future<void> _handleTap() async {
    if (!_signedIn && !_remembered) {
      // Iniciar sesión y arrancar la sincronización automática.
      final ok = await SyncService.signIn();
      if (!mounted) return;
      if (ok) {
        // Sube el historial local existente y trae el remoto (una sola sync).
        await SyncService.sync(forcePush: true);
        _refreshFromService();
        _showErrorOr(() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cuenta conectada. Sincronizando…'),
              backgroundColor: Color(0xFF8b5cf6),
              duration: Duration(seconds: 2),
            ),
          );
        });
      } else {
        _showErrorOnly();
      }
      return;
    }

    if (!_signedIn && _remembered) {
      // Cuenta recordada aún no restaurada (sin red al abrir, etc.):
      // reintentar la restauración silenciosa, sin pedir login de nuevo.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reconectando con tu cuenta…'),
          backgroundColor: Color(0xFF8b5cf6),
          duration: Duration(seconds: 2),
        ),
      );
      unawaited(SyncService.attemptRestoreAndSync().then((_) {
        if (mounted) _refreshFromService();
      }));
      return;
    }

    // Con sesión: menú de cuenta → cerrar sesión.
    _showAccountMenu();
  }

  void _showErrorOr(VoidCallback onOk) {
    final err = SyncService.lastError;
    if (err != null) {
      _showErrorOnly();
    } else {
      onOk();
    }
  }

  void _showErrorOnly() {
    final err = SyncService.lastError;
    if (err == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err), backgroundColor: Colors.red.shade800),
    );
  }

  Future<void> _showAccountMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16121f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF8b5cf6).withValues(alpha: 0.2),
              backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                  ? NetworkImage(_photoUrl!)
                  : null,
              child: (_photoUrl == null || _photoUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 32, color: Color(0xFFa78bfa))
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              _name ?? _email ?? 'Cuenta de Google',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFFe8e4f0),
              ),
            ),
            if (_email != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _email!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6d6488),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFF2a2438)),
            ListTile(
              leading: const Icon(Icons.sync, color: Color(0xFFa78bfa)),
              title: const Text(
                'Sincronización automática',
                style: TextStyle(fontSize: 14, color: Color(0xFFe8e4f0)),
              ),
              subtitle: const Text(
                'Tus datos se sincronizan automáticamente entre todos tus dispositivos',
                style: TextStyle(fontSize: 12, color: Color(0xFF6d6488)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFf87171)),
              title: const Text(
                'Cerrar sesión',
                style: TextStyle(fontSize: 14, color: Color(0xFFf87171)),
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await SyncService.signOut();
                if (mounted) _refreshFromService();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _handleTap,
      child: (_signedIn || _remembered)
          ? Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF8b5cf6).withValues(alpha: 0.2),
                backgroundImage: _photoUrl != null && _photoUrl!.isNotEmpty
                    ? NetworkImage(_photoUrl!)
                    : null,
                child: (_photoUrl == null || _photoUrl!.isEmpty)
                    ? const Icon(
                        Icons.person,
                        size: 16,
                        color: Color(0xFFa78bfa),
                      )
                    : null,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.account_circle_outlined,
                size: 26,
                color: (_signedIn
                    ? const Color(0xFFa78bfa)
                    : const Color(0xFF6d6488)),
              ),
            ),
    );
  }
}
