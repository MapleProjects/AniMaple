import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'gdrive_config.dart';

/// Auth de escritorio para Google (Windows/Linux).
///
/// `google_sign_in` NO tiene implementación para Windows/Linux, así que en
/// desktop usamos el flujo estándar de "Installed App":
///   Authorization Code  +  PKCE  +  loopback redirect en 127.0.0.1
///
/// Flujo:
/// 1. La app levanta un HttpServer en `127.0.0.1:<puerto aleatorio>`.
/// 2. Abre el navegador a accounts.google.com con client_id, scope
///    drive.appdata, code_challenge (PKCE) y access_type=offline.
/// 3. Google redirige a `http://127.0.0.1:<puerto>/?code=...` → servidor local
///    captura el authorization code y cierra.
/// 4. La app canjea code → access_token + refresh_token (guardados en disco).
/// 5. Con el access_token construye el header `Authorization: Bearer ...`.
///
/// El redirect a loopback 127.0.0.1 es aceptado por Google y NO requiere
/// registrar cada puerto (basta con que el OAuth client permita "desktop" o
/// tenga habilitado http://127.0.0.1 en "Authorized redirect URIs").
class DesktopGoogleAuth {
  DesktopGoogleAuth._();

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userInfoEndpoint =
      'https://www.googleapis.com/oauth2/v2/userinfo';
  static const _scope =
      'openid email profile https://www.googleapis.com/auth/drive.appdata';

  // Claves de persistencia (SharedPreferences).
  static const _pkAccessToken = 'desktop_oauth_access_token';
  static const _pkRefreshToken = 'desktop_oauth_refresh_token';
  static const _pkExpires = 'desktop_oauth_expires_at';
  static const _pkEmail = 'desktop_oauth_email';
  static const _pkName = 'desktop_oauth_name';
  static const _pkPhoto = 'desktop_oauth_photo';

  static String? _accessToken;
  static String? _refreshToken;
  static int? _expiresAt; // epoch ms
  static String? _email;
  static String? _name;
  static String? _photoUrl;

  // Getters para la UI (espejo de SyncService).
  static bool get isSignedIn => _accessToken != null;
  static String? get accountEmail => _email;
  static String? get accountDisplayName => _name;
  static String? get accountPhotoUrl => _photoUrl;

  /// Config del OAuth client para desktop.
  /// Por defecto usa el Web Server Client ID y Secret de la app; se puede
  /// sobreescribir con --dart-define=GOOGLE_DESKTOP_CLIENT_ID=...
  /// y --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...
  static String get _clientId {
    const envVal = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
    return envVal.isNotEmpty ? envVal : GDriveConfig.webServerClientId;
  }

  static String get _clientSecret {
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
    return true;
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
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _email = null;
    _name = null;
    _photoUrl = null;
  }

  static String _base64UrlNoPad(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');
}
