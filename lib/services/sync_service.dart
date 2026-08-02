import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../models/anime.dart';
import 'api_service.dart';
import 'gdrive_config.dart';

/// SyncService — sincroniza historial y favoritos contra el almacenamiento
/// personal del usuario en Google Drive (appDataFolder).
///
/// La app usa la cuenta de Drive del propio usuario (BYO cloud):
/// - Login con Google Sign-In (scope drive.appdata, non-sensitive)
/// - Los datos viven en el appDataFolder privado de la app dentro de la
///   cuenta del usuario. Google garantiza que solo la app puede accederlo.
/// - Cero hosting propio. Cada usuario usa su propia nube.
///
/// Estrategia de merge: last-write-wins por registro con timestamp.
/// Cada entrada (historial, favorito) lleva su timestamp, así nunca se
/// pierde un cambio reciente entre dispositivos.
///
/// Basado en google_sign_in 7.x: singleton [GoogleSignIn.instance],
/// [GoogleSignIn.initialize] una vez, y access token OAuth por
/// [GoogleSignInAccount.authorizationClient].
class SyncService {
  SyncService._();

  static const _fileName = 'animaple_sync.json';
  static const _scopeDriveAppdata =
      'https://www.googleapis.com/auth/drive.appdata';
  static const _driveApiBase = 'https://www.googleapis.com/drive/v3';

  static GoogleSignInAccount? _account;
  static Map<String, String>? _authHeaders;
  static String? _fileId; // id del archivo en Drive (se cachea)
  static bool _busy = false;
  static Timer? _debounce;

  /// Último error visible para la UI (patrón de la app: errores siempre visibles).
  static String? lastError;
  static bool get hasError => lastError != null;

  static GoogleSignInAccount? get account => _account;
  static bool get isSignedIn => _account != null;
  static String? get accountEmail => _account?.email;

  /// Inicializa el singleton de Google Sign-In.
  /// Debe llamarse una sola vez, antes de cualquier otro método.
  static Future<void> initialize() async {
    await GoogleSignIn.instance.initialize(
      clientId: GDriveConfig.androidClientId.isEmpty
          ? null
          : GDriveConfig.androidClientId,
      serverClientId: GDriveConfig.webServerClientId.isEmpty
          ? null
          : GDriveConfig.webServerClientId,
    );
  }

  /// Reintenta restaurar una sesión previa (silencioso, sin UI).
  /// Devuelve true si quedó autenticado con token usable.
  static Future<bool> tryRestoreSession() async {
    try {
      final restored = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (restored == null) return false;
      if (!await _cacheAuthHeaders(prompt: false)) return false;
      _account = restored;
      return true;
    } catch (e) {
      // Sin red o sin sesión aún — no es un error fatal.
      debugPrint('Sync: restore session skipped: $e');
      return false;
    }
  }

  /// Login interactivo con la cuenta Google del usuario.
  /// Devuelve true si quedó autenticado con token usable.
  static Future<bool> signIn() async {
    lastError = null;
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [_scopeDriveAppdata],
      );
      _account = account;
      if (!await _cacheAuthHeaders(prompt: true)) {
        lastError = 'No se pudo obtener el token de acceso de Google Drive.';
        return false;
      }
      debugPrint('Sync: signed in as ${account.email}');
      return true;
    } on GoogleSignInException catch (e) {
      lastError = 'Error al iniciar sesión con Google: ${e.description}';
      debugPrint('Sync signIn error: ${e.code} ${e.description}');
      return false;
    } catch (e) {
      lastError = 'Error al iniciar sesión con Google: $e';
      debugPrint('Sync signIn error: $e');
      return false;
    }
  }

  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _account = null;
    _authHeaders = null;
    _fileId = null;
    lastError = null;
  }

  /// Obtiene (o refresca) los headers de autorización para drive.appdata.
  /// Con [prompt]=true permite mostrar UI de consentimiento si hace falta.
  static Future<bool> _cacheAuthHeaders({required bool prompt}) async {
    final account = _account;
    if (account == null) return false;
    try {
      final headers = await account.authorizationClient.authorizationHeaders(
        const [_scopeDriveAppdata],
        promptIfNecessary: prompt,
      );
      if (headers == null) return false;
      _authHeaders = headers;
      return true;
    } catch (e) {
      debugPrint('Sync auth headers error: $e');
      return false;
    }
  }

  /// Punto de entrada: llama tras los cambios locales.
  /// Debounce de 2s para no subir por cada tap.
  static Future<void> notifyLocalChanged() async {
    if (!isSignedIn || _authHeaders == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      push();
    });
  }

  /// Serializa el estado local (historial + favoritos) a un Map.
  static Future<Map<String, dynamic>> _collectLocalState() async {
    final history = await ApiService.fetchHistory();
    final followed = await ApiService.fetchFollowed();
    return {
      'version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'history': history
          .map(
            (h) => {
              'anime_id': h.animeId,
              'anime_slug': h.animeSlug,
              'anime_title': h.animeTitle,
              'episode_number': h.episodeNumber,
              'watched_at': h.watchedAt,
            },
          )
          .toList(),
      'followed': followed
          .map(
            (f) => {
              'anime_id': f.animeId,
              'anime_title': f.animeTitle,
              'anime_slug': f.animeSlug,
              'followed_at': f.followedAt,
            },
          )
          .toList(),
    };
  }

  /// Sube el estado local completo a Drive AppData.
  static Future<bool> push() async {
    if (_busy || !isSignedIn || _authHeaders == null) return false;
    if (kIsWeb) return false;
    _busy = true;
    lastError = null;
    try {
      final state = await _collectLocalState();
      final body = jsonEncode(state);
      final fileId = await _ensureFileId();

      if (fileId == null) {
        final createRes = await _driveRequest(
          'POST',
          '/files?uploadType=media',
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
        _fileId = (createRes?['id'] as String?) ?? await _findFileId();
      } else {
        await _driveRequest(
          'PATCH',
          '/files/$fileId?uploadType=media',
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
      }
      debugPrint('Sync: push OK, ${utf8.encode(body).length} bytes');
      return true;
    } catch (e) {
      _authHeaders = null; // forzar re-autorización la próxima
      lastError = 'Error al subir datos a Drive: $e';
      debugPrint('Sync push error: $e');
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Descarga el estado remoto y hace merge contra el local.
  static Future<bool> pull() async {
    if (!isSignedIn || _authHeaders == null) return false;
    _busy = true;
    lastError = null;
    try {
      final fileId = await _findFileId();
      if (fileId == null) {
        debugPrint('Sync: no remote file yet');
        return false;
      }
      _fileId = fileId;

      final res = await _driveRequest('GET', '/files/$fileId?alt=media');
      if (res == null) return false;

      final remote = res is Map<String, dynamic> ? res : null;
      if (remote == null || remote['version'] == null) return false;

      final remoteHistory = (remote['history'] as List? ?? [])
          .map((e) => HistoryEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final remoteFollowed = (remote['followed'] as List? ?? [])
          .map(
            (e) => FollowedAnime.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList();

      return await _mergeIntoLocal(remoteHistory, remoteFollowed);
    } catch (e) {
      _authHeaders = null;
      lastError = 'Error al bajar datos de Drive: $e';
      debugPrint('Sync pull error: $e');
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Merge last-write-wins por registro.
  static Future<bool> _mergeIntoLocal(
    List<HistoryEntry> remoteHistory,
    List<FollowedAnime> remoteFollowed,
  ) async {
    final localHistory = await ApiService.fetchHistory();
    final localFollowed = await ApiService.fetchFollowed();

    // ── Merge historial ──
    final mergedHistory = <String, HistoryEntry>{};
    for (final h in [...localHistory, ...remoteHistory]) {
      final key = '${h.animeSlug}#${h.episodeNumber}';
      final existing = mergedHistory[key];
      if (existing == null) {
        mergedHistory[key] = h;
      } else if (_isNewer(h.watchedAt, existing.watchedAt)) {
        mergedHistory[key] = h;
      }
    }
    final sortedHistory = mergedHistory.values.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    if (sortedHistory.length > 200) {
      sortedHistory.removeRange(200, sortedHistory.length);
    }

    // ── Merge favoritos ──
    final mergedFollowed = <int, FollowedAnime>{};
    for (final f in [...localFollowed, ...remoteFollowed]) {
      final existing = mergedFollowed[f.animeId];
      if (existing == null) {
        mergedFollowed[f.animeId] = f;
      } else if (_isNewer(f.followedAt, existing.followedAt)) {
        mergedFollowed[f.animeId] = f;
      }
    }
    final sortedFollowed = mergedFollowed.values.toList()
      ..sort((a, b) => b.followedAt.compareTo(a.followedAt));

    // ── Ver si cambió ──
    final sameHistory = _sameEntries(localHistory, sortedHistory);
    final sameFollowed = _sameEntries(localFollowed, sortedFollowed);
    if (sameHistory && sameFollowed) {
      debugPrint('Sync: merge sin cambios');
      return false;
    }

    await ApiService.replaceAllState(sortedHistory, sortedFollowed);
    debugPrint(
      'Sync: merge aplicado — history=${sortedHistory.length}, '
      'followed=${sortedFollowed.length}',
    );
    return true;
  }

  static bool _isNewer(String a, String b) {
    final at = DateTime.tryParse(a);
    final bt = DateTime.tryParse(b);
    if (at == null || bt == null) return a.compareTo(b) > 0;
    return at.isAfter(bt);
  }

  static bool _sameEntries<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toString() != b[i].toString()) return false;
    }
    return true;
  }

  /// Crea el archivo en appDataFolder si no existe. Devuelve su id.
  static Future<String?> _ensureFileId() async {
    if (_fileId != null) return _fileId;
    final existing = await _findFileId();
    if (existing != null) return existing;
    final res = await _driveRequest(
      'POST',
      '/files',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': _fileName,
        'parents': ['appDataFolder'],
      }),
    );
    final id = res?['id'] as String?;
    if (id != null) _fileId = id;
    return id;
  }

  /// Busca el archivo en el appDataFolder por nombre.
  static Future<String?> _findFileId() async {
    if (!isSignedIn || _authHeaders == null) return null;
    try {
      final q = Uri.encodeComponent("name='$_fileName'");
      final res = await _driveRequest(
        'GET',
        '/files?spaces=appDataFolder&q=$q&fields=files(id,name)',
      );
      final files = res?['files'] as List? ?? [];
      return files.isNotEmpty ? (files.first as Map)['id'] as String? : null;
    } catch (e) {
      debugPrint('Sync _findFileId error: $e');
      return null;
    }
  }

  /// Llama genérica a la REST API de Drive v3 con los headers de autorización.
  static Future<dynamic> _driveRequest(
    String method,
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final auth = _authHeaders;
    if (auth == null) throw StateError('no auth');

    final uri = Uri.parse('$_driveApiBase$path');
    final req = http.Request(method, uri)
      ..headers.addAll({...auth, if (headers != null) ...headers})
      ..body = body ?? '';

    final streamed = await http.Client()
        .send(req)
        .timeout(const Duration(seconds: 30));
    final res = String.fromCharCodes(await streamed.stream.toBytes());

    debugPrint('Sync: $method $path → ${streamed.statusCode}');
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('Drive API $method $path → ${streamed.statusCode}: $res');
    }
    if (res.isEmpty) return null;
    return jsonDecode(res);
  }
}
