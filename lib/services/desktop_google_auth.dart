import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show AniMapleApp;
import 'gdrive_config.dart';

/// Auth de escritorio y Android TV para Google.
///
/// Soporta dos flujos principales:
/// 1. Flujo Loopback (Windows / Linux):
///    Authorization Code + PKCE + loopback redirect en 127.0.0.1
/// 2. Flujo Device Authorization Grant (Android TV / RFC 8628):
///    Genera código corto (google.com/device) y realiza polling en segundo plano,
///    sin abrir navegadores externos ni provocar que la app sea cerrada por el LMK.
class DesktopGoogleAuth {
  DesktopGoogleAuth._();

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _deviceEndpoint = 'https://oauth2.googleapis.com/device/code';
  static const _userInfoEndpoint =
      'https://www.googleapis.com/oauth2/v2/userinfo';
  static const _scope =
      'openid email profile https://www.googleapis.com/auth/drive.appdata https://www.googleapis.com/auth/drive.file';
  static const _tvScope =
      'openid email profile https://www.googleapis.com/auth/drive.file';

  // Claves de persistencia (SharedPreferences).
  static const _pkAccessToken = 'desktop_oauth_access_token';
  static const _pkRefreshToken = 'desktop_oauth_refresh_token';
  static const _pkExpires = 'desktop_oauth_expires_at';
  static const _pkEmail = 'desktop_oauth_email';
  static const _pkName = 'desktop_oauth_name';
  static const _pkPhoto = 'desktop_oauth_photo';
  static const _pkIsTvClient = 'desktop_oauth_is_tv_client';

  static String? _accessToken;
  static String? _refreshToken;
  static int? _expiresAt; // epoch ms
  static String? _email;
  static String? _name;
  static String? _photoUrl;
  static bool _isTvClient = false;

  // Getters para la UI (espejo de SyncService).
  static bool get isSignedIn => _accessToken != null;
  static String? get accountEmail => _email;
  static String? get accountDisplayName => _name;
  static String? get accountPhotoUrl => _photoUrl;

  /// Config del OAuth client para desktop o TV.
  static String get _clientId {
    if (_isTvClient) return GDriveConfig.tvClientId;
    const envVal = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
    return envVal.isNotEmpty ? envVal : GDriveConfig.webServerClientId;
  }

  static String get _clientSecret {
    if (_isTvClient) return GDriveConfig.tvClientSecret;
    const envVal = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
    return envVal.isNotEmpty ? envVal : GDriveConfig.clientSecret;
  }

  /// Carga la sesión persistida (si existe) en memoria.
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _accessToken = p.getString(_pkAccessToken);
    _refreshToken = p.getString(_pkRefreshToken);
    _expiresAt = p.getInt(_pkExpires);
    _email = p.getString(_pkEmail);
    _name = p.getString(_pkName);
    _photoUrl = p.getString(_pkPhoto);
    _isTvClient = p.getBool(_pkIsTvClient) ?? false;
  }

  /// Restaura una sesión persistida. Devuelve true si hay token (o lo
  /// refrescó exitosamente). No muestra UI.
  static Future<bool> tryRestore() async {
    await load();
    if (_accessToken != null) {
      if (_expiresAt != null &&
          _expiresAt! - 60000 < DateTime.now().millisecondsSinceEpoch) {
        if (_refreshToken != null && _refreshToken!.isNotEmpty) {
          return refreshAccessToken();
        }
      }
      return true;
    }
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      return refreshAccessToken();
    }
    return false;
  }

  /// Inicia el flujo interactivo: abre el navegador y captura el code.
  /// Devuelve true si quedó autenticado.
  static Future<bool> signIn() async {
    final p = await SharedPreferences.getInstance();
    // Verifier PKCE (usuario inicia sesión) → 64 bytes aleatorios.
    final random = Random.secure();
    final verifierBytes = List<int>.generate(48, (_) => random.nextInt(256));
    final verifier = _base64UrlNoPad(verifierBytes);
    final challenge = _base64UrlNoPad(
      sha256.convert(utf8.encode(verifier)).bytes,
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://127.0.0.1:$port';

    final params = <String, String>{
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent select_account',
      'state': verifier, // reusamos verifier como state (desechable)
    };
    final authUrl = Uri.parse(_authEndpoint).replace(queryParameters: params);

    try {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('DesktopAuth: no se pudo abrir el navegador: $e');
      await server.close(force: true);
      return false;
    }

    // Espera el redirect con el authorization code.
    final code = await _captureCode(server, redirectUri);
    await server.close(force: true);
    if (code == null) return false;

    // Canjea code → tokens.
    final ok = await _exchangeCode(code, redirectUri, verifier);
    if (!ok) return false;

    // Guarda token.id y metadatos.
    await p.setString(_pkAccessToken, _accessToken!);
    await p.setString(_pkRefreshToken, _refreshToken ?? '');
    await p.setInt(_pkExpires, _expiresAt ?? 0);
    await p.setString(_pkEmail, _email ?? '');
    await p.setString(_pkName, _name ?? '');
    await p.setString(_pkPhoto, _photoUrl ?? '');
    await p.setBool(_pkIsTvClient, false);
    return true;
  }

  /// Inicia el flujo de autenticación para TVs y dispositivos con memoria limitada
  /// (Device Authorization Grant - RFC 8628).
  ///
  /// Muestra un diálogo en pantalla con la URL (google.com/device) y el código corto,
  /// mientras realiza polling silencioso en segundo plano sin abrir navegadores externos.
  static Future<bool> signInDeviceFlow({BuildContext? context}) async {
    final ctx = context ?? AniMapleApp.navigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('TvAuth: contexto no disponible para mostrar diálogo');
      return false;
    }

    try {
      // 1. Solicitar código de dispositivo a Google
      final devResp = await http.post(
        Uri.parse(_deviceEndpoint),
        body: {
          'client_id': GDriveConfig.tvClientId,
          'scope': _tvScope,
        },
      ).timeout(const Duration(seconds: 15));

      if (devResp.statusCode != 200) {
        debugPrint('TvAuth device code error ${devResp.statusCode}: ${devResp.body}');
        return false;
      }

      final devData = jsonDecode(devResp.body) as Map<String, dynamic>;
      final deviceCode = devData['device_code'] as String?;
      final userCode = devData['user_code'] as String?;
      final verificationUrl =
          (devData['verification_url'] as String? ?? 'https://www.google.com/device')
              .replaceFirst('https://', '');
      final qrUrl = (devData['verification_url_complete'] as String?) ??
          'https://www.google.com/device?user_code=$userCode';
      final interval = (devData['interval'] as int?) ?? 5;
      final expiresIn = (devData['expires_in'] as int?) ?? 1800;

      if (deviceCode == null || userCode == null) {
        debugPrint('TvAuth: respuesta de Google sin códigos válidos');
        return false;
      }

      bool userCancelled = false;
      bool authSuccess = false;

      // 2. Iniciar polling en segundo plano
      final pollFuture = Future<bool>(() async {
        final deadline = DateTime.now().add(Duration(seconds: expiresIn));
        var currentInterval = interval;

        while (!userCancelled && DateTime.now().isBefore(deadline)) {
          await Future.delayed(Duration(seconds: currentInterval));
          if (userCancelled) break;

          try {
            final pollResp = await http.post(
              Uri.parse(_tokenEndpoint),
              body: {
                'client_id': GDriveConfig.tvClientId,
                'client_secret': GDriveConfig.tvClientSecret,
                'device_code': deviceCode,
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
              },
            ).timeout(const Duration(seconds: 15));

            if (pollResp.statusCode == 200) {
              final tokenData = jsonDecode(pollResp.body) as Map<String, dynamic>;
              _isTvClient = true;
              await _applyTokenResponse(tokenData);

              // Obtener perfil si no vino en id_token
              if (_email == null || _name == null) {
                await _fetchProfile();
              }

              final p = await SharedPreferences.getInstance();
              await p.setString(_pkAccessToken, _accessToken!);
              await p.setString(_pkRefreshToken, _refreshToken ?? '');
              await p.setInt(_pkExpires, _expiresAt ?? 0);
              await p.setString(_pkEmail, _email ?? '');
              await p.setString(_pkName, _name ?? '');
              await p.setString(_pkPhoto, _photoUrl ?? '');
              await p.setBool(_pkIsTvClient, true);

              authSuccess = true;
              break;
            }

            final pollErr = jsonDecode(pollResp.body) as Map<String, dynamic>;
            final errType = pollErr['error'] as String? ?? '';

            if (errType == 'authorization_pending') {
              continue;
            } else if (errType == 'slow_down') {
              currentInterval += 5;
              continue;
            } else if (errType == 'access_denied' || errType == 'expired_token') {
              debugPrint('TvAuth: autorización denegada o expirada ($errType)');
              break;
            } else {
              debugPrint('TvAuth: error en polling: $pollErr');
              break;
            }
          } catch (e) {
            debugPrint('TvAuth polling cycle skip: $e');
          }
        }
        return authSuccess;
      });

      // 3. Mostrar diálogo en pantalla adaptado para control remoto
      if (!ctx.mounted) return false;
      await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) {
          pollFuture.then((success) {
            if (dialogCtx.mounted) {
              Navigator.of(dialogCtx).pop(success);
            }
          });

          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              userCancelled = true;
            },
            child: AlertDialog(
              backgroundColor: const Color(0xFF140f22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFF2d2244), width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 580,
                  maxHeight: MediaQuery.of(dialogCtx).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8b5cf6).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.tv_rounded, color: Color(0xFFa78bfa), size: 26),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Vincular con tu Cuenta de Google',
                            style: TextStyle(
                              color: Color(0xFFf3f0fa),
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Escanea el código QR con tu celular para abrir el enlace con el código ya completado, o ingrésalo manualmente.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFa29cb6), fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Código QR con user_code ya incluido
                          Expanded(
                            flex: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1c162e),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF382b54)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: QrImageView(
                                      data: qrUrl,
                                      version: QrVersions.auto,
                                      size: 110.0,
                                      backgroundColor: Colors.white,
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Escanear con celular',
                                    style: TextStyle(
                                      color: Color(0xFFa78bfa),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Abre con código ya listo',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Color(0xFF8e86a4), fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // 2. Método Manual (código en pantalla)
                          Expanded(
                            flex: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1c162e),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF382b54)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'O entra desde navegador a:',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Color(0xFF8e86a4), fontSize: 11),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    verificationUrl,
                                    style: const TextStyle(
                                      color: Color(0xFFa78bfa),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Código de vinculación:',
                                    style: TextStyle(color: Color(0xFF8e86a4), fontSize: 11),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF281f3d),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.6),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: SelectableText(
                                      userCode,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFffffff),
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Estado de espera en contenedor diferenciado
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF191328),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF2d2244)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFa78bfa),
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Esperando confirmación en tu teléfono…',
                              style: TextStyle(color: Color(0xFFb8b2cb), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        autofocus: true,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF251d38),
                          foregroundColor: const Color(0xFFe2def0),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF3d2f5a)),
                          ),
                        ),
                        onPressed: () {
                          userCancelled = true;
                          Navigator.of(dialogCtx).pop(false);
                        },
                        child: const Text('Cancelar', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      userCancelled = true;
      return authSuccess;
    } catch (e) {
      debugPrint('TvAuth signInDeviceFlow error: $e');
      return false;
    }
  }

  /// Página HTML que se muestra en el navegador tras el redirect, indicando
  /// si se pudo completar la autorización o si hubo un error.
  static String _okPage(bool success) {
    final title = success ? 'AniMaple — Inicio de sesión completado' : 'Error';
    final msg = success
        ? 'Inicio de sesión con Google completado. Ya puedes volver a la app.'
        : 'No se recibió el código de autorización. Intenta de nuevo.';
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>$title</title>
<style>
body{background:#0a0812;color:#e8e4f0;font-family:sans-serif;display:flex;
align-items:center;justify-content:center;height:100vh;margin:0}
.card{text-align:center;padding:40px;border:1px solid #2a2438;border-radius:12px;
background:#110e1a}
.badge{font-size:48px;color:${success ? '#4ade80' : '#f87171'};margin-bottom:16px}
h1{font-size:20px;margin:0 0 8px}
p{color:#6d6488;margin:0}
</style></head>
<body><div class="card"><div class="badge">${success ? '✓' : '✕'}</div>
<h1>$title</h1><p>$msg</p></div></body></html>
    ''';
  }

  static Future<String?> _captureCode(
    HttpServer server,
    String redirectUri,
  ) async {
    final completer = Completer<String?>();
    server.listen((req) {
      if (req.uri.path == '/favicon.ico') {
        req.response
          ..statusCode = HttpStatus.notFound
          ..close();
        return;
      }
      final query = req.uri.queryParameters;
      final code = query['code'];
      final hasError = query.containsKey('error');

      req.response
        ..headers.contentType = ContentType.html
        ..write(_okPage(code != null))
        ..close();

      if (!completer.isCompleted) {
        if (code != null) {
          completer.complete(code);
        } else if (hasError) {
          debugPrint(
            'DesktopAuth: OAuth error: ${query['error']} (${query['error_description']})',
          );
          completer.complete(null);
        }
      }
    });
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return null;
      },
    );
  }

  /// Canjea el authorization code por access+refresh tokens.
  static Future<bool> _exchangeCode(
    String code,
    String redirectUri,
    String verifier,
  ) async {
    final body = <String, String>{
      'code': code,
      'client_id': _clientId,
      if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': verifier,
    };
    final resp = await http
        .post(Uri.parse(_tokenEndpoint), body: body)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      debugPrint(
        'DesktopAuth: exchange failed ${resp.statusCode}: ${resp.body}',
      );
      return false;
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await _applyTokenResponse(data);
    return _accessToken != null;
  }

  /// Refresca el access_token con el refresh_token. Silencioso si falla.
  static Future<bool> refreshAccessToken() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    final body = <String, String>{
      'refresh_token': refresh,
      'client_id': _clientId,
      if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
      'grant_type': 'refresh_token',
    };
    try {
      final resp = await http
          .post(Uri.parse(_tokenEndpoint), body: body)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        debugPrint(
          'DesktopAuth: refresh failed ${resp.statusCode}: ${resp.body}',
        );
        return false;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      await _applyTokenResponse(data);
      final p = await SharedPreferences.getInstance();
      await p.setString(_pkAccessToken, _accessToken ?? '');
      await p.setInt(_pkExpires, _expiresAt ?? 0);
      if (_refreshToken != null) {
        await p.setString(_pkRefreshToken, _refreshToken!);
      }
      if (_email != null) await p.setString(_pkEmail, _email!);
      if (_name != null) await p.setString(_pkName, _name!);
      if (_photoUrl != null) await p.setString(_pkPhoto, _photoUrl!);
      return _accessToken != null;
    } catch (e) {
      debugPrint('DesktopAuth: refresh skip: $e');
      return false;
    }
  }

  static Future<void> _applyTokenResponse(Map<String, dynamic> data) async {
    _accessToken = data['access_token'] as String?;
    final rt = data['refresh_token'] as String?;
    if (rt != null && rt.isNotEmpty) _refreshToken = rt;
    final exp = data['expires_in'] as int?;
    if (exp != null) {
      _expiresAt = DateTime.now().millisecondsSinceEpoch + exp * 1000;
    }
    final idToken = data['id_token'] as String?;
    if (idToken != null && idToken.isNotEmpty) {
      try {
        final parts = idToken.split('.');
        if (parts.length == 3) {
          final payload = utf8.decode(
            base64Url.decode(base64Url.normalize(parts[1])),
          );
          final map = jsonDecode(payload) as Map<String, dynamic>;
          _email ??= map['email'] as String?;
          _name ??= map['name'] as String?;
          _photoUrl ??= map['picture'] as String?;
        }
      } catch (e) {
        debugPrint('DesktopAuth: id_token parse skip: $e');
      }
    }
    // Perfil (email/name/photo) — si aún no se obtuvo.
    if (_email == null || _email!.isEmpty) {
      await _fetchProfile();
    }
  }

  static Future<void> _fetchProfile() async {
    if (_accessToken == null) return;
    try {
      final resp = await http
          .get(
            Uri.parse(_userInfoEndpoint),
            headers: {'Authorization': 'Bearer $_accessToken'},
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return;
      final u = jsonDecode(resp.body) as Map<String, dynamic>;
      _email = u['email'] as String?;
      _name = u['name'] as String?;
      _photoUrl = u['picture'] as String?;
    } catch (e) {
      debugPrint('DesktopAuth: profile fetch skip: $e');
    }
  }

  /// Header de autorización listo para la Drive API. Refresca si expiró.
  static Future<Map<String, String>?> authorizationHeaders() async {
    if (_accessToken == null) {
      if (_refreshToken != null && await refreshAccessToken()) {
        // ok, ya tenemos token
      } else {
        return null;
      }
    }
    // Expiró → refrescar.
    if (_expiresAt != null &&
        _expiresAt! - 60000 < DateTime.now().millisecondsSinceEpoch) {
      final ok = await refreshAccessToken();
      if (!ok) return null;
    }
    if (_accessToken == null) return null;
    return {'Authorization': 'Bearer $_accessToken'};
  }

  /// Cierra sesión: limpiar persistencia y memoria (opcionalmente revoca el
  /// refresh token en Google).
  static Future<void> signOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pkAccessToken);
    await p.remove(_pkRefreshToken);
    await p.remove(_pkExpires);
    await p.remove(_pkEmail);
    await p.remove(_pkName);
    await p.remove(_pkPhoto);
    await p.remove(_pkIsTvClient);
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _email = null;
    _name = null;
    _photoUrl = null;
    _isTvClient = false;
  }

  static String _base64UrlNoPad(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}
