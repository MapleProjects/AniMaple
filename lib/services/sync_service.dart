import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';
import 'api_service.dart';
import 'gdrive_config.dart';
import 'desktop_google_auth.dart';
import 'tv_service.dart';

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
  static const _scopeDriveFile =
      'https://www.googleapis.com/auth/drive.file';
  static const _driveApiBase = 'https://www.googleapis.com/drive/v3';
  // El endpoint de subida de contenido real es /upload/drive/v3 (no /drive/v3).
  // Con uploadType=media, Google SOLO lo acepta en la URL con /upload/; si se
  // llama al endpoint normal interpreta el body como metadata del recurso y
  // rechaza los campos del archivo con 403 fieldNotWritable.
  static const _driveUploadBase = 'https://www.googleapis.com/upload/drive/v3';

  static GoogleSignInAccount? _account;
  static Map<String, String>? _authHeaders;
  static String? _fileId; // id del archivo en Drive (se cachea)
  static int? _lastRemoteVersion; // última versión remota vista
  static bool _busy = false;
  // Hay cambios locales (borrados, historial, seguidos) que aún no se
  // publicaron con éxito. El poll periódico lo reintenta hasta lograrlo,
  // así una falla de red/sesión no deja un cambio local olvidado.
  static bool _localDirty = false;
  static Timer? _debounce;
  static Timer? _autoSyncTimer;
  static StreamSubscription<List<ConnectivityResult>>? _connSub;
  static bool _wasOffline = false;

  /// Marca de tiempo ISO de la última sincronización exitosa (o null).
  static String? lastSyncedAt;

  /// URL del archivo en Drive (para diagnóstico en la UI).
  static String? get syncFileId => _fileId;
  static String? get lastErrorForUi => lastError;
  static bool get isBusy => _busy;

  /// Se incrementa cada vez que el estado local (historial/Mi lista) cambia.
  /// Las páginas lo escuchan para refrescar en vivo sin resync manual.
  static final ValueNotifier<int> stateVersion = ValueNotifier<int>(0);

  /// Profile info (photo, nombre) para el avatar del AppBar.
  /// Se resuelve desde _account o DesktopGoogleAuth (TV / Windows / Linux).
  static String? get accountDisplayName =>
      _account?.displayName ?? DesktopGoogleAuth.accountDisplayName;
  static String? get accountPhotoUrl =>
      _account?.photoUrl ?? DesktopGoogleAuth.accountPhotoUrl;

  /// Último error visible para la UI (patrón de la app: errores siempre visibles).
  static String? lastError;
  static bool get hasError => lastError != null;

  static GoogleSignInAccount? get account => _account;
  static bool get isSignedIn =>
      _account != null || DesktopGoogleAuth.isSignedIn;
  static String? get accountEmail =>
      _account?.email ?? DesktopGoogleAuth.accountEmail;

  /// ¿Google Sign-In usa el SDK nativo (google_sign_in)? Solo lo hay en
  /// Android/iOS/macOS/web. En Windows (y Linux) usamos DesktopGoogleAuth.
  static bool get googleSignInSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static GoogleSignIn? _googleSignIn;

  static GoogleSignIn _getGoogleSignIn() {
    return _googleSignIn ??= GoogleSignIn(
      scopes: const [_scopeDriveAppdata, _scopeDriveFile],
      // En Android, clientId no está soportado y si se pasa sobreescribe serverClientId.
      // serverClientId DEBE ser el Web Application Client ID para que Google Play Services
      // pueda emitir tokens de Google Drive API.
      clientId: null,
      serverClientId: GDriveConfig.webServerClientId.isEmpty
          ? null
          : GDriveConfig.webServerClientId,
    );
  }

  /// Stream de cambios de cuenta para la UI.
  static Stream<GoogleSignInAccount?> get onCurrentUserChanged =>
      _getGoogleSignIn().onCurrentUserChanged;

  /// Inicializa el singleton de Google Sign-In (o carga la sesión desktop).
  /// Debe llamarse una sola vez, antes de cualquier otro método.
  static Future<void> initialize() async {
    await DesktopGoogleAuth.load();
    if (googleSignInSupported) {
      _getGoogleSignIn();
    }
  }

  /// Restaura una sesión previa (silencioso, sin UI emergente).
  /// En 6.x: signInSilently() consulta a Google Play Services en segundo plano
  /// SIN mostrar ningún diálogo emergente ni ventana del sistema.
  static Future<bool> tryRestoreSession() async {
    // En modo TV o en plataformas sin SDK nativo, priorizar DesktopGoogleAuth.
    if (TvService.isTvMode || !googleSignInSupported) {
      final desktopOk = await DesktopGoogleAuth.tryRestore();
      if (desktopOk) {
        _lastRemoteVersion = null;
        await _cacheAuthHeaders(prompt: false);
        _notifySessionChanged();
        return true;
      }
      if (TvService.isTvMode) return false;
    }
    if (DesktopGoogleAuth.isSignedIn) {
      final desktopOk = await DesktopGoogleAuth.tryRestore();
      if (desktopOk) {
        _lastRemoteVersion = null;
        await _cacheAuthHeaders(prompt: false);
        _notifySessionChanged();
        return true;
      }
    }
    if (googleSignInSupported) {
      try {
        final restored = await _getGoogleSignIn().signInSilently(reAuthenticate: false);
        if (restored != null) {
          _account = restored;
          _lastRemoteVersion = null;
          await _cacheAuthHeaders(prompt: false);
          _notifySessionChanged();
          return true;
        }
      } catch (e) {
        // Sin red o sin sesión aún — no es un error fatal.
        debugPrint('Sync: restore session skipped: $e');
      }
    }
    if (!DesktopGoogleAuth.isSignedIn) {
      final desktopOk = await DesktopGoogleAuth.tryRestore();
      if (desktopOk) {
        _lastRemoteVersion = null;
        await _cacheAuthHeaders(prompt: false);
        _notifySessionChanged();
        return true;
      }
    }
    return false;
  }

  /// Fuerza recalcular auth headers si la sesión existe pero no hay token.
  /// Se usa en pull/push cuando _authHeaders == null.
  static Future<bool> _ensureAuthHeaders({bool prompt = true}) async {
    if (!isSignedIn) return false;
    if (_authHeaders != null) return true;
    return _cacheAuthHeaders(prompt: prompt);
  }

  /// Avisa a la UI de que cambió el estado de sesión (login/logout/restore).
  static void _notifySessionChanged() {
    stateVersion.value++;
  }

  /// Login interactivo con la cuenta Google del usuario.
  /// Devuelve true si quedó autenticado con token usable.
  static Future<bool> signIn({BuildContext? context}) async {
    lastError = null;

    // En televisores Android TV: NUNCA abrir navegadores externos mediante loopback
    // porque el sistema operativo liquida la app por falta de RAM al pasar a segundo plano.
    // Usamos el flujo nativo de TVs (Device Authorization Grant - RFC 8628).
    if (TvService.isTvMode) {
      final ok = await DesktopGoogleAuth.signInDeviceFlow(context: context);
      if (ok) {
        _lastRemoteVersion = null;
        if (!await _cacheAuthHeaders(prompt: false)) {
          lastError = 'No se pudo obtener el token de acceso de Google Drive.';
          return false;
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              _rememberedAccountKey, accountEmail ?? 'signed-in');
        } catch (_) {}
        startAutoSync();
        _notifySessionChanged();
        await sync(forcePush: true);
        debugPrint('Sync: signed in via TV Device Flow as $accountEmail');
        return true;
      }
      lastError = 'No se completó la vinculación con Google.';
      return false;
    }

    if (!googleSignInSupported) {
      final ok = await DesktopGoogleAuth.signIn();
      if (ok) {
        _lastRemoteVersion = null;
        if (!await _cacheAuthHeaders(prompt: false)) {
          lastError = 'No se pudo obtener el token de acceso de Google Drive.';
          return false;
        }
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              _rememberedAccountKey, accountEmail ?? 'signed-in');
        } catch (_) {}
        startAutoSync();
        _notifySessionChanged();
        await sync(forcePush: true);
        debugPrint('Sync: signed in (desktop) as $accountEmail');
        return true;
      }
      lastError = 'No se pudo iniciar sesión con Google.';
      return false;
    }
    try {
      final account = await _getGoogleSignIn().signIn();
      if (account == null) {
        return false;
      }
      _account = account;
      _lastRemoteVersion = null;
      if (!await _cacheAuthHeaders(prompt: true)) {
        lastError = 'No se pudo obtener el token de acceso de Google Drive.';
        return false;
      }
      startAutoSync(); // arrancar sincronización automática
      _notifySessionChanged();
      debugPrint('Sync: signed in as ${account.email}');
      return true;
    } catch (e) {
      debugPrint('Sync native signIn error: $e');
      // Si el login nativo falla (p.ej. error 12500 de Play Services),
      // recurrir al Device Flow seguro sin cerrar la app
      if (context != null && !context.mounted) return false;
      try {
        final deviceOk = await DesktopGoogleAuth.signInDeviceFlow(context: context);
        if (deviceOk) {
          _lastRemoteVersion = null;
          if (await _cacheAuthHeaders(prompt: false)) {
            startAutoSync();
            _notifySessionChanged();
            debugPrint('Sync: signed in via Device Flow fallback as $accountEmail');
            return true;
          }
        }
      } catch (fallbackErr) {
        debugPrint('Sync device fallback error: $fallbackErr');
      }
      lastError = 'Error al iniciar sesión con Google: $e';
      return false;
    }
  }

  static Future<void> signOut() async {
    stopAutoSync();
    if (googleSignInSupported) {
      try {
        await _getGoogleSignIn().signOut();
      } catch (_) {}
    }
    await DesktopGoogleAuth.signOut();
    _account = null;
    _authHeaders = null;
    _fileId = null;
    _lastRemoteVersion = null;
    // Olvidar la cuenta recordada: el usuario cerró sesión a propósito.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_rememberedAccountKey);
    } catch (_) {}
    lastError = null;
    stateVersion.value++;
  }

  /// Obtiene (o refresca) los headers de autorización para drive.appdata.
  /// Con [prompt]=true permite mostrar UI de consentimiento si hace falta.
  static Future<bool> _cacheAuthHeaders({required bool prompt}) async {
    if (_account == null && DesktopGoogleAuth.isSignedIn) {
      final headers = await DesktopGoogleAuth.authorizationHeaders();
      if (headers == null) return false;
      _authHeaders = headers;
      return true;
    }
    final account = _account;
    if (account != null) {
      try {
        final headers = await account.authHeaders;
        if (headers.isNotEmpty) {
          _authHeaders = headers;
          return true;
        }
      } catch (e) {
        debugPrint('Sync auth headers error: $e');
      }
    }
    if (DesktopGoogleAuth.isSignedIn) {
      final headers = await DesktopGoogleAuth.authorizationHeaders();
      if (headers != null) {
        _authHeaders = headers;
        return true;
      }
    }
    return false;
  }

  /// Sincronización completa bidireccional (se usa en arranque, polling y
  /// tras cambios locales):
  /// 1. pull: merge remoto → local (last-write-wins por registro)
  /// 2. push: sube el resultado del merge a Drive para que el OTRO
  ///    dispositivo lo vea — así la unión se propaga entre ambos.
  /// [forcePush] sube aunque no haya cambios del merge (arranque / cambio
  /// local) para publicar por primera vez el historial local existente.
  static Future<void> sync({bool forcePush = false}) async {
    if (_busy || !isSignedIn) return;
    _busy = true;
    try {
      final changed = await _pullIntoLocal();
      // Subir también si hay cambios locales aún no publicados (red/sesión
      // fallaron antes): el pull-merge no debe descartarlos.
      if (changed || forcePush || _localDirty) {
        await _pushLocal();
      }
    } finally {
      _busy = false;
    }
  }

  /// Punto de entrada: llama tras los cambios locales.
  /// Debounce de 2s para no subir por cada tap. Antes de subir hace un
  /// pull-merge, así no pisa cambios remotos que otro dispositivo publicó.
  static Future<void> notifyLocalChanged() async {
    // Hay cambios locales que publicar. Se marca aunque la sesión no esté
    // lista todavía: el poll reintentará cuando vuelva la red/sesión.
    _localDirty = true;
    if (!isSignedIn) return;
    if (!await _ensureAuthHeaders()) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      sync(forcePush: true);
    });
  }

  /// Arranca el polling de cambios remotos (≈ tiempo real, sin resync manual).
  /// Un GET ligero de `version` cada 10s; descarga solo si el remoto cambió.
  static void startAutoSync() {
    if (_autoSyncTimer != null) return; // ya activo
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _pollRemote();
    });
    // Verificación inmediata al arrancar.
    _pollRemote();
  }

  static void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Vigila la conectividad: cuando la red se restablece (o al arranque si ya
  /// hay red) dispara un poll inmediato, para que la sincronización se
  /// recupere en ≤10s tras un fallo de conexión sin que el usuario haga nada.
  /// Si la sesión aún no se restauró (app iniciada sin Internet), reintenta
  /// la restauración al volver la red.
  static void watchConnectivity() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && _wasOffline) {
        debugPrint('Sync: red restablecida → intentar sync');
        if (!isSignedIn) {
          attemptRestoreAndSync();
        } else {
          _pollRemote();
        }
      }
      _wasOffline = !online;
    });
    Connectivity().checkConnectivity().then((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      _wasOffline = !online;
      if (online && isSignedIn) _pollRemote();
    });
  }

  /// Restaura la sesión (si es posible) y sincroniza. Se llama al arranque y
  /// desde el watcher de conectividad cuando la red vuelve. No muestra UI:
  /// si no hay credencial guardada termina silenciosamente (login manual).
  ///
  /// Anti-martillo: sin Internet, el reintento de restauración ocurre cada
  /// ≥10 s (no en cada tick del polling). La sesión recordada se marca en
  /// SharedPreferences para que el arranque SIN red sepa que hay cuenta y
  /// muestre el avatar aunque la restauración silenciosa aún no logre
  /// contactar a Google.
  static const _rememberedAccountKey = 'sync_remembered_account';

  static Future<void> attemptRestoreAndSync() async {
    if (isSignedIn) {
      sync(forcePush: true); // ya hay sesión → publicar/traer de inmediato
      return;
    }
    // Martillado: como máximo un intento de restore cada 10 s. El polling
    // de 10 s y el watcher de conectividad llaman aquí; sin este guard, un
    // arranque offline dispararía intentos en ráfaga cada segundo.
    final now = DateTime.now();
    if (_lastRestoreAttempt != null &&
        now.difference(_lastRestoreAttempt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastRestoreAttempt = now;

    final restored = await tryRestoreSession().catchError((_) => false);
    if (restored == true) {
      // Recordar la cuenta para futuros arranques (persistente).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            _rememberedAccountKey, accountEmail ?? 'signed-in');
      } catch (_) {}
      sync(forcePush: true);
    }
  }

  static DateTime? _lastRestoreAttempt;

  /// ¿Hay una cuenta recordada de una sesión anterior? Fuente persistente
  /// para la UI mientras la sesión real aún no se restaura (p.ej. arranque
  /// sin Internet: el avatar aparece con sesión desde el primer frame).
  static Future<bool> hasRememberedAccount() async {
    if (isSignedIn) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_rememberedAccountKey);
      return v != null && v.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Revisa la versión remota y hace pull si cambió desde la última vista.
  /// Respeta límites de Drive: nunca descarga si `version` no cambió.
  static Future<void> _pollRemote() async {
    if (_busy) return;
    // Si hay cambios locales pendientes y la sesión no está, intentar
    // restaurarla: sin esto, un borrado hecho con sesión caducada quedaría
    // sin subir hasta que el usuario hiciera algo (loop de 10s lo recupera).
    if (!isSignedIn) {
      if (_localDirty) {
        attemptRestoreAndSync();
      }
      return;
    }
    if (_authHeaders == null && !await _ensureAuthHeaders()) return;
    try {
      // Búsqueda fresca (sin cache) — además re-ejecuta el dedup de
      // duplicados si dos dispositivos crearon el archivo a la vez.
      final fileId = await _findFileId();
      if (fileId == null) return; // nada que sincronizar todavía
      _fileId = fileId;

      final res = await _driveRequest('GET', '/files/$fileId?fields=version');
      final version = res is Map<String, dynamic> ? res['version'] : null;
      final v = version is int ? version : int.tryParse('$version');

      // Sin cambio remoto → no tocar Drive de nuevo.
      // PERO si hay cambios locales pendientes de publicar (falló antes la
      // red/sesión), hay que reintentarlo aunque la versión no cambió: si no,
      // un borrado o edición local podría quedarse sin subir días hasta que
      // otro cambio disparara el push. Reintento: mark seen = v, y sync lo
      // publica (sync usa _localDirty).
      if (v == null || v == _lastRemoteVersion) {
        if (_localDirty) {
          debugPrint('Sync: pendiente local → reintentar publicar');
          await sync();
        }
        return;
      }

      // Cambió → sync completo (merge + push para propagar la unión).
      await sync();
      debugPrint('Sync: auto-sync aplicó cambios (version $v)');
      // Marcar como vista aunque el merge no cambiara nada (mismo contenido).
      _lastRemoteVersion = v;
    } catch (e) {
      if (e is InsufficientScopesException) {
        _handleInsufficientScopes();
      } else if (_isAuthError(e)) {
        _authHeaders = null;
      }
      debugPrint('Sync: poll skip: $e');
    }
  }

  static bool _isAuthError(Object e) =>
      e.toString().contains('401') || e.toString().contains('403');

  /// Serializa el estado local (historial + favoritos + tombstones) a un Map.
  static Future<Map<String, dynamic>> _collectLocalState() async {
    final history = await ApiService.fetchHistory();
    final followed = await ApiService.fetchFollowed();
    final deletedHistory = await ApiService.fetchDeletedHistory();
    final deletedFollowed = await ApiService.fetchDeletedFollowed();
    return {
      'version': 2,
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
      'deleted_history': deletedHistory,
      'deleted_followed': deletedFollowed,
    };
  }

  /// Sube el estado local completo a Drive AppData.
  static Future<bool> push() async {
    if (_busy || !isSignedIn) return false;
    _busy = true;
    try {
      return await _pushLocal();
    } finally {
      _busy = false;
    }
  }

  static Future<bool> _pushLocal() async {
    if (kIsWeb) return false;
    if (!await _ensureAuthHeaders()) return false;
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
      // Registrar la versión recién publicada para no re-pull de nosotros mismos.
      await _cacheRemoteVersion();
      // Cambios locales ya publicados con éxito → limpiar el pendiente.
      _localDirty = false;
      lastSyncedAt = DateTime.now().toUtc().toIso8601String();
      debugPrint('Sync: push OK, ${utf8.encode(body).length} bytes');
      return true;
    } catch (e) {
      if (e is InsufficientScopesException) {
        _handleInsufficientScopes();
      } else {
        _authHeaders = null; // forzar re-autorización la próxima
        lastError = 'Error al subir datos a Drive: $e';
      }
      debugPrint('Sync push error: $e');
      return false;
    }
  }

  /// Descarga el estado remoto y hace merge contra el local.
  /// Devuelve true si hubo cambios aplicados en el dispositivo.
  static Future<bool> pull() async {
    if (_busy || !isSignedIn) return false;
    _busy = true;
    try {
      return await _pullIntoLocal();
    } finally {
      _busy = false;
    }
  }

  static Future<bool> _pullIntoLocal() async {
    if (!await _ensureAuthHeaders()) return false;
    lastError = null;
    try {
      // Búsqueda fresca (sin cache) también re-ejecuta el dedup de duplicados.
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
      final remoteDeletedHistory = _decodeStrMap(remote['deleted_history']);
      final remoteDeletedFollowed = _decodeStrMap(remote['deleted_followed']);

      final changed = await _mergeIntoLocal(
        remoteHistory,
        remoteFollowed,
        remoteDeletedHistory,
        remoteDeletedFollowed,
      );
      if (changed) {
        // Los datos locales cambiaron → avisar a las páginas para refresh en vivo.
        stateVersion.value++;
      }
      lastSyncedAt = DateTime.now().toUtc().toIso8601String();
      return changed;
    } catch (e) {
      if (e is InsufficientScopesException) {
        _handleInsufficientScopes();
      } else {
        _authHeaders = null;
        lastError = 'Error al bajar datos de Drive: $e';
      }
      debugPrint('Sync pull error: $e');
      return false;
    }
  }

  /// Parsea un mapa clave → valor tolerando valores null (remoto v1).
  static Map<String, String> _decodeStrMap(dynamic v) {
    if (v is! Map) return {};
    return v.map((k, val) => MapEntry('$k', '$val'));
  }

  /// Marca _lastRemoteVersion con la versión actual del archivo (tras push).
  static Future<void> _cacheRemoteVersion() async {
    try {
      final fileId = _fileId;
      if (fileId == null) return;
      final res = await _driveRequest('GET', '/files/$fileId?fields=version');
      if (res is Map<String, dynamic> && res['version'] != null) {
        _lastRemoteVersion = res['version'] as int;
      }
    } catch (e) {
      debugPrint('Sync cache version skip: $e');
    }
  }

  /// Merge last-write-wins por registro + tombstones de borrado.
  ///
  /// Los tombstones garantizan que eliminar en un dispositivo se propague:
  /// si la clave está en deleted_* y su deleted_at es más reciente que el
  /// dato vivo, la entrada se descarta aunque aparezca en el remoto.
  /// Una entrada viva con timestamp más nuevo que el tombstone revoca el
  /// borrado (re-marcar/re-seguir vuelve a traer el dato).
  ///
  /// El orden final es determinista (timestamp UTC desc + id/épisode de
  /// desempate) para que todos los dispositivos converjan a la misma lista,
  /// incluso con datos antiguos cuyo timestamp venía sin normalizar.
  static Future<bool> _mergeIntoLocal(
    List<HistoryEntry> remoteHistory,
    List<FollowedAnime> remoteFollowed,
    Map<String, String> remoteDeletedHistory,
    Map<String, String> remoteDeletedFollowed,
  ) async {
    final localHistory = await ApiService.fetchHistory();
    final localFollowed = await ApiService.fetchFollowed();
    final localDeletedHistory = await ApiService.fetchDeletedHistory();
    final localDeletedFollowed = await ApiService.fetchDeletedFollowed();

    // ── Merge tombstones: last-write-wins por clave ──
    final deletedHistory = _mergeTombstones(
      localDeletedHistory,
      remoteDeletedHistory,
    );
    final deletedFollowed = _mergeTombstones(
      localDeletedFollowed,
      remoteDeletedFollowed,
    );

    // ── Merge historial (dedup por slug#episodio) ──
    final mergedHistory = <String, HistoryEntry>{};
    for (final h in [...localHistory, ...remoteHistory]) {
      final key = _historyKey(h);
      final existing = mergedHistory[key];
      if (existing == null) {
        mergedHistory[key] = h;
      } else if (_isNewer(h.watchedAt, existing.watchedAt)) {
        mergedHistory[key] = h;
      }
    }
    // Aplicar tombstones: descartar capítulos borrados más recientemente.
    // Un dato re-marcado (watched_at > tombstone) sobrevive automáticamente:
    // _isTombstoned lo mantiene y el tombstone queda inerte en el mapa.
    mergedHistory.removeWhere(
      (key, h) => _isTombstoned(deletedHistory[key], h.watchedAt),
    );
    final sortedHistory = mergedHistory.values.toList()
      ..sort((a, b) => _compareHistoryDesc(a, b));
    if (sortedHistory.length > 200) {
      sortedHistory.removeRange(200, sortedHistory.length);
    }

    // ── Merge favoritos (dedup por anime_id) ──
    final mergedFollowed = <int, FollowedAnime>{};
    for (final f in [...localFollowed, ...remoteFollowed]) {
      final existing = mergedFollowed[f.animeId];
      if (existing == null) {
        mergedFollowed[f.animeId] = f;
      } else if (_isNewer(f.followedAt, existing.followedAt)) {
        mergedFollowed[f.animeId] = f;
      }
    }
    mergedFollowed.removeWhere(
      (id, f) => _isTombstoned(deletedFollowed['$id'], f.followedAt),
    );
    final sortedFollowed = mergedFollowed.values.toList()
      ..sort((a, b) => _compareFollowedDesc(a, b));

    // ── Ver si cambió (por contenido y orden reales) ──
    final sameHistory = _sameHistory(localHistory, sortedHistory);
    final sameFollowed = _sameFollowed(localFollowed, sortedFollowed);
    final sameTombstones =
        _mapsEqual(localDeletedHistory, deletedHistory) &&
        _mapsEqual(localDeletedFollowed, deletedFollowed);
    if (sameHistory && sameFollowed && sameTombstones) {
      debugPrint('Sync: merge sin cambios');
      return false;
    }

    await ApiService.replaceAllState(sortedHistory, sortedFollowed);
    await ApiService.saveDeletedHistory(deletedHistory);
    await ApiService.saveDeletedFollowed(deletedFollowed);
    debugPrint(
      'Sync: merge aplicado — history=${sortedHistory.length}, '
      'followed=${sortedFollowed.length}, '
      'delHist=${deletedHistory.length}, delFol=${deletedFollowed.length}',
    );
    return true;
  }

  static String _historyKey(HistoryEntry h) =>
      '${h.animeSlug}#${h.episodeNumber}';

  /// Union de mapas de tombstones: para cada clave gana el deleted_at mayor.
  static Map<String, String> _mergeTombstones(
    Map<String, String> a,
    Map<String, String> b,
  ) {
    final out = <String, String>{...a};
    for (final e in b.entries) {
      final cur = out[e.key];
      if (cur == null || _isNewer(e.value, cur)) out[e.key] = e.value;
    }
    return out;
  }

  /// true si el tombstone [deletedAt] es más reciente que el timestamp del dato.
  static bool _isTombstoned(String? deletedAt, String dataTs) {
    if (deletedAt == null) return false;
    return !_isNewer(dataTs, deletedAt);
  }

  /// Compara dos timestamps como instantes (tolerante a formatos mezclados).
  static int _timestampCompare(String a, String b) {
    final at = DateTime.tryParse(a);
    final bt = DateTime.tryParse(b);
    if (at == null || bt == null) return a.compareTo(b);
    return at.compareTo(bt);
  }

  /// Order determinista, más reciente primero. Desempate por slug + episodio
  /// para que dos dispositivos con timestamps iguales coincidan.
  static int _compareHistoryDesc(HistoryEntry a, HistoryEntry b) {
    final t = _timestampCompare(b.watchedAt, a.watchedAt);
    if (t != 0) return t;
    final s = a.animeSlug.compareTo(b.animeSlug);
    if (s != 0) return s;
    return a.episodeNumber.compareTo(b.episodeNumber);
  }

  static int _compareFollowedDesc(FollowedAnime a, FollowedAnime b) {
    final t = _timestampCompare(b.followedAt, a.followedAt);
    if (t != 0) return t;
    return a.animeId.compareTo(b.animeId);
  }

  static bool _sameHistory(List<HistoryEntry> a, List<HistoryEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.animeId != y.animeId ||
          x.animeSlug != y.animeSlug ||
          x.animeTitle != y.animeTitle ||
          x.episodeNumber != y.episodeNumber ||
          x.watchedAt != y.watchedAt) {
        return false;
      }
    }
    return true;
  }

  static bool _sameFollowed(List<FollowedAnime> a, List<FollowedAnime> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.animeId != y.animeId ||
          x.animeTitle != y.animeTitle ||
          x.animeSlug != y.animeSlug ||
          x.followedAt != y.followedAt) {
        return false;
      }
    }
    return true;
  }

  static bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static bool _isNewer(String a, String b) {
    final at = DateTime.tryParse(a);
    final bt = DateTime.tryParse(b);
    if (at == null || bt == null) return a.compareTo(b) > 0;
    return at.isAfter(bt);
  }

  /// Crea el archivo de sincronización en el Drive del usuario (accesible por TV, Desktop y Mobile).
  static Future<String?> _ensureFileId() async {
    if (_fileId != null) return _fileId;
    final existing = await _findFileId();
    if (existing != null) return existing;

    try {
      final res = await _driveRequest(
        'POST',
        '/files',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _fileName,
        }),
      );
      final id = res?['id'] as String?;
      if (id != null) _fileId = id;
      return id;
    } on InsufficientScopesException catch (e) {
      debugPrint('Sync: permisos insuficientes para crear archivo: $e');
      _handleInsufficientScopes();
      return null;
    } catch (e) {
      debugPrint('Sync: error al crear archivo en Drive: $e');
      return null;
    }
  }

  /// Busca el archivo de sincronización.
  /// Consulta primero en el Drive compartido del usuario (drive.file).
  /// Si no existe y no es TV, migra desde appDataFolder a la raíz de Drive.
  /// Elimina duplicados si los hubiere conservando el archivo con más datos.
  static Future<String?> _findFileId() async {
    if (!isSignedIn || _authHeaders == null) return null;
    try {
      final q = Uri.encodeComponent("name='$_fileName' and trashed=false");
      List<Map> files = [];

      // 1. Buscar en el Drive del usuario (accesible con drive.file en TV, Desktop y Mobile)
      try {
        final res = await _driveRequest(
          'GET',
          '/files?q=$q&fields=files(id,name,size,modifiedTime)',
        );
        files = (res?['files'] as List? ?? []).cast<Map>().toList();
      } on InsufficientScopesException catch (e) {
        debugPrint('Sync: permisos insuficientes para buscar en Drive: $e');
        _handleInsufficientScopes();
        return null;
      } catch (e) {
        debugPrint('Sync: Drive search skip: $e');
      }

      // 2. Si no se encontró en Drive y el cliente tiene acceso a appDataFolder (no TV),
      // buscar si existe una versión previa en appDataFolder y migrarla a Drive raíz.
      if (files.isEmpty && !TvService.isTvMode) {
        try {
          final res = await _driveRequest(
            'GET',
            '/files?spaces=appDataFolder&q=$q&fields=files(id,name,size)',
          );
          final appDataFiles = (res?['files'] as List? ?? []).cast<Map>().toList();
          if (appDataFiles.isNotEmpty) {
            final appDataId = appDataFiles.first['id'] as String?;
            if (appDataId != null) {
              debugPrint('Sync: migrando archivo desde appDataFolder ($appDataId) a raíz de Drive...');
              final oldContent = await _driveRequest('GET', '/files/$appDataId?alt=media');
              if (oldContent != null) {
                final createRes = await _driveRequest(
                  'POST',
                  '/files',
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({'name': _fileName}),
                );
                final newId = createRes?['id'] as String?;
                if (newId != null) {
                  await _driveRequest(
                    'PATCH',
                    '/files/$newId?uploadType=media',
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(oldContent),
                  );
                  debugPrint('Sync: migración completada exitosamente a raíz id=$newId');
                  files = [{'id': newId, 'name': _fileName, 'size': utf8.encode(jsonEncode(oldContent)).length}];
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Sync: appDataFolder migration check skip: $e');
        }
      }

      if (files.isEmpty) return null;

      // Ordenar por tamaño descendente para priorizar el archivo con datos reales
      files.sort((a, b) => (int.tryParse('${b['size'] ?? 0}') ?? 0).compareTo(int.tryParse('${a['size'] ?? 0}') ?? 0));

      final first = files.first['id'] as String?;
      // Eliminar duplicados (mismo nombre) para mantener una sola fuente.
      for (final dup in files.skip(1)) {
        final dupId = dup['id'] as String?;
        if (dupId != null && dupId != first) {
          try {
            await _driveRequest('DELETE', '/files/$dupId');
            debugPrint('Sync: eliminado archivo duplicado $dupId');
          } catch (e) {
            debugPrint('Sync: no se pudo borrar duplicado $dupId: $e');
          }
        }
      }
      return first;
    } catch (e) {
      debugPrint('Sync _findFileId error: $e');
      return null;
    }
  }

  /// Llama genérica a la REST API de Drive v3 con los headers de autorización.
  /// Si el path incluye `uploadType=media`, usa el endpoint de subida
  /// (/upload/drive/v3) — el único donde Google acepta bodies de contenido.
  static Future<dynamic> _driveRequest(
    String method,
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final auth = _authHeaders;
    if (auth == null) throw StateError('no auth');

    final base = path.contains('uploadType=media')
        ? _driveUploadBase
        : _driveApiBase;
    final uri = Uri.parse('$base$path');
    final req = http.Request(method, uri)
      ..headers.addAll({...auth, if (headers != null) ...headers});
    if (body != null) {
      req.headers['content-type'] = 'application/json; charset=utf-8';
      req.bodyBytes = utf8.encode(body);
    }

    final streamed = await http.Client()
        .send(req)
        .timeout(const Duration(seconds: 30));
    final bytes = await streamed.stream.toBytes();
    final res = utf8.decode(bytes, allowMalformed: true);

    debugPrint('Sync: $method $path → ${streamed.statusCode}');
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      if (streamed.statusCode == 403 && res.contains('insufficientScopes')) {
        throw InsufficientScopesException('Drive API insufficientScopes: $res');
      }
      throw Exception('Drive API $method $path → ${streamed.statusCode}: $res');
    }
    if (res.isEmpty) return null;
    return jsonDecode(res);
  }

  static void _handleInsufficientScopes() {
    _authHeaders = null;
    lastError = 'Tu sesión requiere volver a vincularse para sincronizar con Google Drive.';
    if (!googleSignInSupported) {
      DesktopGoogleAuth.signOut();
    }
    stateVersion.value++;
  }
}

class InsufficientScopesException implements Exception {
  final String message;
  InsufficientScopesException(this.message);
  @override
  String toString() => message;
}
