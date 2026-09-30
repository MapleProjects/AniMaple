import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/anime.dart';
import 'api_service.dart';

/// Descargas offline de AniMaple.
///
/// Layout en disco (directorio de soporte de la app):
/// ```
/// animaple_downloads/
///   <slug>/
///     meta.json            → {anime_id, title, synopsis, poster, saved_at}
///     poster.jpg           → portada local (para pintar sin conexión)
///     episodes/
///       ep_<n>.mp4         → video (HLS remuxado o MP4 progresivo)
///       ep_<n>.json        → {bytes, size, variant, server, saved_at, duration}
///   index.json             → índice rápido {slug: {title, eps[], bytes}}
/// ```
///
/// Cola secuencial: una descarga a la vez (evita saturar red/disco y
/// simplifica progreso). Escritura atómica: todo archivo se baja como
/// `.part` y se renombra al completar; los `.part` huérfanos se limpian
/// al iniciar la app. El índice se escribe al final de CADA operación con
/// rename atómico también.
class DownloadService {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  static const _rootName = 'animaple_downloads';
  static const _indexFile = 'index.json';
  static const _queueFile = 'queue.json';
  static const _partSuffix = '.part';

  static const MethodChannel _downloadChannel =
      MethodChannel('com.mapleprojects.animaple/downloads');

  static Future<void> _startNativeForeground(String title, int episode, String slug) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _downloadChannel.invokeMethod('startDownloadService', {
        'title': title,
        'episode': episode,
        'slug': slug,
      });
    } catch (e) {
      debugPrint('DownloadService native start error: $e');
    }
  }

  static DateTime? _lastNativeUpdate;
  static double? _lastNativeProgress;

  static Future<void> _updateNativeForeground(
    String title,
    int episode,
    int progressPercent,
    String status, {
    bool force = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final now = DateTime.now();
    if (!force &&
        _lastNativeUpdate != null &&
        now.difference(_lastNativeUpdate!).inMilliseconds < 400 &&
        _lastNativeProgress != null &&
        (progressPercent - _lastNativeProgress!).abs() < 2) {
      return;
    }
    _lastNativeUpdate = now;
    _lastNativeProgress = progressPercent.toDouble();
    try {
      await _downloadChannel.invokeMethod('updateDownloadProgress', {
        'title': title,
        'episode': episode,
        'progress': progressPercent,
        'status': status,
      });
    } catch (_) {}
  }

  static Future<void> _stopNativeForeground({String? completedTitle, int? completedEp}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    _lastNativeUpdate = null;
    _lastNativeProgress = null;
    try {
      await _downloadChannel.invokeMethod('stopDownloadService', {
        if (completedTitle != null) 'completedTitle': completedTitle,
        if (completedEp != null) 'completedEp': completedEp,
      });
    } catch (_) {}
  }

  Directory? _root;
  Map<String, Map<String, dynamic>> _index = {};
  bool _loaded = false;

  File _queuePath(Directory root) => File('${root.path}/$_queueFile');

  Future<void> _saveQueue() async {
    try {
      final root = await _ensureRoot();
      final list = <Map<String, dynamic>>[];
      if (_current != null && !_cancelRequested) {
        list.add(_current!.toJson());
      }
      for (final j in _queue) {
        list.add(j.toJson());
      }
      final file = _queuePath(root);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(list));
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('DownloadService error saving queue: $e');
    }
  }

  Future<void> _loadQueue(Directory root) async {
    try {
      final file = _queuePath(root);
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final job = _Job.fromJson(item.cast<String, dynamic>());
        if (isDownloaded(job.slug, job.episode)) continue;
        if (isQueued(job.slug, job.episode)) continue;
        _queue.add(job);
      }
    } catch (e) {
      debugPrint('DownloadService error loading queue: $e');
    }
  }

  // ── Estado reactivo para la UI ──────────────────────────────────────────
  /// Eventos de cambio: tras completar/borrar/encolar cualquier episodio.
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// Progreso de la descarga activa: slug#episodio → 0.0..1.0
  final ValueNotifier<Map<String, double>> progress =
      ValueNotifier<Map<String, double>>({});

  /// Clave `slug#ep` del elemento descargándose ahora (o null si idle).
  String? activeKey;

  /// Errores por clave `slug#ep` del último intento fallido. Se limpia al
  /// reencolar o borrar. La UI muestra icono de error + reintento.
  final ValueNotifier<Map<String, String>> failures =
      ValueNotifier<Map<String, String>>({});

  /// Completadas en esta sesión (para la pestaña "Completados" del gestor).
  /// En memoria a propósito: es feedback transitorio, no estado persistente.
  final ValueNotifier<List<Map<String, dynamic>>> recentCompleted =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  final List<_Job> _queue = [];

  /// Claves `slug#ep` que fallaron en su último intento y deben reencolarse
  /// al final de la cola (reintento con jerarquía). Se marca al fallar sin
  /// cancelación del usuario; _pump lo consume y vuelve a poner el job al
  /// final. Si falla de nuevo, se repite el ciclo (siempre al final).
  final Set<String> _failedJobs = {};

  _Job? _current;
  Timer? _stallTimer;

  // ════════════════════════════════════════════════════════════════════
  // Inicialización y almacenamiento
  // ════════════════════════════════════════════════════════════════════

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/$_rootName');
    if (!await root.exists()) await root.create(recursive: true);
    _root = root;
    return root;
  }

  Future<void> init() async {
    final root = await _ensureRoot();
    await _loadIndex(root);
    await _cleanupPartials(root);
    await _loadQueue(root);
    _loaded = true;
    version.value++;
    // Reanudar automáticamente si había elementos pendientes en la cola
    if (_queue.isNotEmpty) {
      _pump();
    }
  }

  void _touchLoaded() {
    if (_loaded) return;
    // Lazy init defensivo: si alguien llama antes de init(), cargar sync.
    // (init() se llama desde main; esto solo cubre hot-restart parcial).
    throw StateError('DownloadService.init() no fue llamado');
  }

  Directory _slugDir(Directory root, String slug) =>
      Directory('${root.path}/$slug');

  Directory _episodesDir(Directory root, String slug) =>
      Directory('${root.path}/$slug/episodes');

  File _metaFile(Directory root, String slug) =>
      File('${root.path}/$slug/meta.json');

  File _videoFile(Directory root, String slug, int ep) =>
      File('${root.path}/$slug/episodes/ep_$ep.mp4');

  File _sidecarFile(Directory root, String slug, int ep) =>
      File('${root.path}/$slug/episodes/ep_$ep.json');

  /// Escritura atómica: temp + rename sobre [target].
  Future<void> _atomicWrite(File target, List<int> bytes) async {
    final tmp = File('${target.path}${_partSuffix}w');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    } finally {
      if (await tmp.exists()) { await tmp.delete().catchError((_) => tmp); }
    }
  }

  Future<void> _cleanupPartials(Directory root) async {
    if (!await root.exists()) return;
    await for (final dir in root.list()) {
      if (dir is! Directory) continue;
      final eps = Directory('${dir.path}/episodes');
      if (!await eps.exists()) continue;
      await for (final f in eps.list()) {
        // Archivos parciales y carpetas HLS temporales de sesiones previas.
        if (f is File && f.path.endsWith(_partSuffix)) {
          try {
            await f.delete();
          } catch (_) {}
        } else if (f is Directory && f.path.contains(_partSuffix)) {
          try {
            await f.delete(recursive: true);
          } catch (_) {}
        }
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Índice
  // ════════════════════════════════════════════════════════════════════

  Future<void> _loadIndex(Directory root) async {
    final f = File('${root.path}/$_indexFile');
    if (!await f.exists()) {
      _index = {};
      return;
    }
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _index = decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      _index = {};
    }
  }

  Future<void> _saveIndex(Directory root) async {
    final f = File('${root.path}/$_indexFile');
    await _atomicWrite(f, utf8.encode(jsonEncode(_index)));
  }

  void _rebuildIndexFromDisk(Directory root, String slug) {
    // Recontar desde sidecars reales (fuente de verdad post-crash).
    final entries = <Map<String, dynamic>>[];
    var totalBytes = 0;
    final epsDir = _episodesDir(root, slug);
    if (epsDir.existsSync()) {
      for (final f in epsDir.listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          final ep = (j['episode'] as num?)?.toInt() ?? 0;
          final size = (j['size'] as num?)?.toInt() ?? 0;
          if (ep <= 0) continue;
          entries.add({
            'ep': ep,
            'bytes': size,
            'variant': j['variant'] ?? '',
            'dub': j['dub'] ?? false,
            'saved_at': j['saved_at'] ?? '',
          });
          totalBytes += size;
        } catch (_) {}
      }
    }
    entries.sort((a, b) => (a['ep'] as int).compareTo(b['ep'] as int));
    if (entries.isEmpty) {
      _index.remove(slug);
      return;
    }
    final meta = _readMetaSafe(root, slug);
    _index[slug] = {
      'title': meta?['title'] ?? slug,
      'poster': meta?['poster'] ?? '',
      'total_bytes': totalBytes,
      'eps': entries,
    };
  }

  Map<String, dynamic>? _readMetaSafe(Directory root, String slug) {
    try {
      final f = _metaFile(root, slug);
      if (!f.existsSync()) return null;
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Consultas públicas (sincrónicas, basadas en el índice)
  // ════════════════════════════════════════════════════════════════════

  /// Slugs con al menos un episodio completo descargado.
  Set<String> downloadedSlugs() => Set<String>.from(_index.keys);

  /// Episodios completados del anime [slug].
  Set<int> downloadedEpisodes(String slug) {
    final entry = _index[slug];
    if (entry == null) return {};
    final eps = (entry['eps'] as List? ?? []);
    return eps.map((e) => ((e as Map)['ep'] as num).toInt()).toSet();
  }

  bool isDownloaded(String slug, int episodeNumber) =>
      downloadedEpisodes(slug).contains(episodeNumber);

  /// Episodios descargados con doblaje (según sidecars).
  Set<int> downloadedDubEpisodes(String slug) {
    final entry = _index[slug];
    if (entry == null) return {};
    final eps = (entry['eps'] as List? ?? []);
    return eps
        .where((e) => (e as Map)['dub'] == true)
        .map((e) => ((e)['ep'] as num).toInt())
        .toSet();
  }

  bool isQueued(String slug, int episodeNumber) {
    final key = '$slug#$episodeNumber';
    if (_current?.key == key) return true;
    return _queue.any((j) => j.key == key);
  }

  /// Tamaño total en bytes ocupado por [slug] (0 si nada).
  int totalBytesFor(String slug) =>
      ((_index[slug]?['total_bytes'] as num?) ?? 0).toInt();

  int totalBytesAll() {
    var sum = 0;
    for (final e in _index.values) {
      sum += ((e['total_bytes'] as num?) ?? 0).toInt();
    }
    return sum;
  }

  /// Ruta del archivo de video si está descargado, null si no.
  Future<String?> videoPath(String slug, int episodeNumber) async {
    final root = await _ensureRoot();
    final f = _videoFile(root, slug, episodeNumber);
    if (await f.exists()) return f.path;
    final dir = _hlsDir(root, slug, episodeNumber);
    if (await dir.exists()) return '${dir.path}/index.m3u8';
    return null;
  }

  /// Directorio HLS local de un episodio (playlist + segs/).
  Directory _hlsDir(Directory root, String slug, int ep) =>
      Directory('${root.path}/$slug/episodes/ep_${ep}_hls');

  /// Tamaño total de un directorio (recursivo).
  static Future<int> _dirSize(Directory dir) async {
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// Snapshot de la cola para el FAB: [{slug, episode, key}] en orden.
  List<Map<String, String>> queueSnapshot() {
    final out = <Map<String, String>>[];
    final cur = _current;
    if (cur != null) {
      out.add({'slug': cur.slug, 'episode': '${cur.episode}', 'key': cur.key});
    }
    for (final j in _queue) {
      out.add({'slug': j.slug, 'episode': '${j.episode}', 'key': j.key});
    }
    return out;
  }

  /// Título de anime desde el índice (para listas del gestor).
  String titleFor(String slug) =>
      ((_index[slug]?['title'] as String?) ?? slug);

  /// Ruta absoluta del póster local de un anime, o null si no hay.
  /// Fallback en memoria para descargas en curso: el índice del anime solo
  /// existe tras completar el primer capítulo, pero el póster se guarda al
  /// ENCOLAR; sin este mapa el FAB mostraría icono hasta el primer OK.
  final Map<String, String> _posterOverrides = {};

  String? posterPathFor(String slug) {
    final p = _index[slug]?['poster'] as String?;
    final r = _root;
    if (p != null && p.isNotEmpty && r != null) {
      return '${r.path}/$slug/$p';
    }
    return _posterOverrides[slug];
  }

  // ── Helpers de lectura para la UI (sincrónicos, basados en índice/disco) ──

  /// Entrada de índice del anime: {title, poster, total_bytes, eps:[...]}.
  Map<String, dynamic>? indexEntryFor(String slug) => _index[slug];

  /// Ruta absoluta del poster local si existe.
  String? posterFileFor(String slug) {
    final root = _root;
    if (root == null) return null;
    final f = File('${root.path}/$slug/poster.jpg');
    return f.existsSync() ? f.path : null;
  }

  /// meta.json leído de disco (título, synopsis, anime_id, poster).
  Future<Map<String, dynamic>?> metaFor(String slug) async {
    final root = await _ensureRoot();
    return _readMetaSafe(root, slug);
  }

  /// Tamaño formateado del anime para mostrar en la UI.
  String fmtBytesFor(String slug) {
    final b = totalBytesFor(slug);
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB en disco';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).round()} MB en disco';
    if (b > 0) return '${(b / 1024).round()} KB en disco';
    return '0 B en disco';
  }

  // ════════════════════════════════════════════════════════════════════
  // API pública: encolar / cancelar / borrar
  // ════════════════════════════════════════════════════════════════════

  /// Reencola episodios fallidos (botón reintentar del gestor). Usa los
  /// metadatos ya guardados en disco; no re-descarga el póster.
  Future<void> retryFailed(Iterable<String> keys) async {
    final root = await _ensureRoot();
    final bySlug = <String, List<int>>{};
    for (final k in keys) {
      final i = k.indexOf('#');
      if (i <= 0) continue;
      final ep = int.tryParse(k.substring(i + 1));
      if (ep != null) {
        bySlug.putIfAbsent(k.substring(0, i), () => []).add(ep);
      }
    }
    for (final e in bySlug.entries) {
      final meta = _readMetaSafe(root, e.key);
      final prefs = _dubPrefs[e.key] ?? false;
      await enqueueAnime(
        animeId: ((meta?['anime_id'] as num?) ?? 0).toInt(),
        slug: e.key,
        title: (meta?['title'] as String?) ?? e.key,
        synopsis: (meta?['synopsis'] as String?) ?? '',
        posterUrl: null,
        episodeNumbers: e.value,
        preferDub: prefs,
      );
    }
  }

  /// Sonda ligera de doblaje: consulta el detalle de cada episodio y
  /// devuelve true si AL MENOS UNO tiene variante DUB. Detiene la sonda
  /// al primer positivo (animes completos con DUB no revisan todos).
  /// Resultado cacheado por slug para no repetir la sonda al reabrir.
  final Map<String, bool> _dubProbeCache = {};

  Future<bool> probeAnyDub(String slug, List<int> episodes,
      {void Function(int probed, int total)? onProgress}) async {
    if (_dubProbeCache.containsKey(slug)) return _dubProbeCache[slug]!;
    var any = false;
    for (var i = 0; i < episodes.length; i++) {
      try {
        final d = await ApiService.fetchEpisodeDetail(slug, episodes[i]);
        if (d.variants.any((v) => v.toUpperCase() == 'DUB')) {
          any = true;
          break;
        }
      } catch (_) {
        // Episodio sin respuesta: seguir con el resto.
      }
      onProgress?.call(i + 1, episodes.length);
    }
    _dubProbeCache[slug] = any;
    return any;
  }

  /// Metadatos del anime que se guardan junto a las descargas. Se resuelven
  /// una vez por anime (la primera descarga); el sheet las pasa explícitos.
  /// [preferDub]: si true, cada capítulo se baja con doblaje CUANDO LO TIENE;
  /// los caps sin DUB caen automáticamente al subtitulado. Si false, SUB.
  final Map<String, bool> _dubPrefs = {};

  /// Reconstruye un AnimeDetail desde meta.json para la UI offline:
  /// sinopsis, etiquetas (status/categoría/géneros) y grilla de capítulos
  /// sin llamar a la API. Devuelve null si no hay descargas del slug.
  Future<AnimeDetail?> animeDetailFor(String slug) async {
    final root = await _ensureRoot();
    final meta = _readMetaSafe(root, slug);
    if (meta == null) return null;

    // Lista completa de capítulos guardada al descargar. Fallback para
    // descargas antiguas (sin lista): usar solo lo que hay en el índice.
    var eps = <EpisodeBasic>[];
    for (final e in (meta['episodes'] as List? ?? [])) {
      final m = e as Map;
      eps.add(EpisodeBasic(
        id: ((m['id'] as num?) ?? 0).toInt(),
        number: ((m['number'] as num?) ?? 0).toInt(),
      ));
    }
    if (eps.isEmpty) {
      eps = downloadedEpisodes(slug)
          .map((n) => EpisodeBasic(id: 0, number: n))
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
    }

    final posterFile = File('${root.path}/$slug/poster.jpg');
    return AnimeDetail(
      id: ((meta['anime_id'] as num?) ?? 0).toInt(),
      title: (meta['title'] as String?) ?? slug,
      synopsis: (meta['synopsis'] as String?) ?? '',
      poster: posterFile.existsSync() ? posterFile.path : null,
      status: (meta['status'] as String?) ?? '',
      category: (meta['category'] as String?) ?? '',
      genres: (meta['genres'] as List? ?? [])
          .map((g) => Genre(id: 0, name: g.toString(), slug: g.toString()))
          .toList(),
      episodesCount: ((meta['episodes_count'] as num?) ?? eps.length).toInt(),
      slug: slug,
      episodes: eps,
      mature: false,
    );
  }

  Future<void> enqueueAnime({
    required int animeId,
    required String slug,
    required String title,
    required String synopsis,
    required String? posterUrl,
    required List<int> episodeNumbers,
    bool preferDub = false,
    AnimeDetail? detail,
  }) async {
    _touchLoaded();
    final root = await _ensureRoot();
    // Guardar/actualizar metadatos del anime + poster en la primera pasada.
    // Con [detail] se persiste además status/categoría/géneros/lista de
    // capítulos para reconstruir el detalle completo en modo offline.
    await _saveMeta(root, animeId, slug, title, synopsis, posterUrl,
        detail: detail);
    // Póster inmediato para el FAB/gestor aunque el índice aún no exista.
    if (posterUrl != null && posterUrl.isNotEmpty) {
      final f = File('${root.path}/$slug/poster.jpg');
      if (f.existsSync()) _posterOverrides[slug] = f.path;
    }
    if (episodeNumbers.isNotEmpty) _dubPrefs[slug] = preferDub;
    for (final ep in episodeNumbers) {
      final key = '$slug#$ep';
      if (isDownloaded(slug, ep)) continue;
      if (isQueued(slug, ep)) continue;
      _clearFailure(key);
      _queue.add(_Job(key: key, slug: slug, episode: ep, preferDub: preferDub, title: title));
    }
    _saveQueue();
    _notify();
    _pump();
  }

  /// Cancela lo pendiente/activo de un anime (no borra lo ya completado).
  void cancelQueued(String slug, {int? episode}) {
    _queue.removeWhere((j) {
      if (j.slug != slug) return false;
      return episode == null || j.episode == episode;
    });
    if (_current != null &&
        _current!.slug == slug &&
        (episode == null || _current!.episode == episode)) {
      _cancelRequested = true;
    }
    _saveQueue();
    if (_queue.isEmpty && _current == null) {
      _stopNativeForeground();
    }
    _notify();
  }

  bool _cancelRequested = false;

  /// Borra UN episodio descargado. Si era el activo, aborta la descarga.
  Future<void> deleteEpisode(String slug, int episodeNumber) async {
    final root = await _ensureRoot();
    cancelQueued(slug, episode: episodeNumber);
    _clearFailure('$slug#$episodeNumber');
    final v = _videoFile(root, slug, episodeNumber);
    final s = _sidecarFile(root, slug, episodeNumber);
    final hls = _hlsDir(root, slug, episodeNumber);
    for (final p in [v.path, s.path]) {
      final f = File(p);
      if (await f.exists()) await f.delete();
    }
    if (await hls.exists()) await hls.delete(recursive: true);
    _rebuildIndexFromDisk(root, slug);
    await _saveIndex(root);
    _saveQueue();
    _notify();
  }

  /// Borra TODAS las descargas de un anime (carpeta completa + índice).
  Future<void> deleteAnime(String slug) async {
    final root = await _ensureRoot();
    cancelQueued(slug);
    final dir = _slugDir(root, slug);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _index.remove(slug);
    await _saveIndex(root);
    _saveQueue();
    _notify();
  }

  /// Vacía toda la carpeta de descargas.
  Future<void> deleteAll() async {
    final root = await _ensureRoot();
    _queue.clear();
    _cancelRequested = _current != null;
    _stopNativeForeground();
    if (await root.exists()) {
      await for (final child in root.list()) {
        try {
          if (child is File && child.path.endsWith(_indexFile)) continue;
          await child.delete(recursive: true);
        } catch (_) {}
      }
    }
    _index.clear();
    await _saveIndex(root);
    _saveQueue();
    _notify();
  }

  void _notify() => version.value++;

  // ════════════════════════════════════════════════════════════════════
  // Cola
  // ════════════════════════════════════════════════════════════════════

  void _pump() {
    if (_current != null) return;
    if (_queue.isEmpty) {
      _stopNativeForeground();
      return;
    }
    final job = _queue.removeAt(0);
    _current = job;
    _cancelRequested = false;
    _saveQueue();
    final animeTitle = job.title.isNotEmpty ? job.title : job.slug;
    _startNativeForeground(animeTitle, job.episode, job.slug);
    _setProgress(job.key, 0.0);
    // El error del job ya quedó registrado en failures[]; aquí solo se
    // traga para no convertirse en excepción no manejada de la zona.
    () async {
      try {
        await _runJob(job);
        if (_queue.isEmpty) {
          _stopNativeForeground(
            completedTitle: job.title.isNotEmpty ? job.title : job.slug,
            completedEp: job.episode,
          );
        }
      } catch (e) {
        debugPrint('JOB DONE (fail): ${job.key}');
      } finally {
        if (_current?.key == job.key) _current = null;
        _setProgress(job.key, null);
        // Reintento con jerarquía: si el capítulo falló (sin cancelación
        // del usuario), vuelve a encolarse AL FINAL de su anime. Así el 6
        // fallido deja pasar al 7 y recupera su lugar cuando llegue su turno.
        if (_failedJobs.remove(job.key)) {
          _queue.add(job);
          debugPrint('REQUEUE RETRY: ${job.key}');
        }
        _saveQueue();
        _notify();
        _pump();
      }
    }();
  }

  void _setProgress(String key, double? value) {
    final m = Map<String, double>.from(progress.value);
    if (value == null) {
      m.remove(key);
    } else {
      final prev = m[key];
      // Throttle: notificar solo en saltos >= 1% o al terminar (1.0),
      // evita rebuilds por cada chunk de red.
      if (prev != null && value < 1.0 && (value - prev).abs() < 0.01) {
        return;
      }
      m[key] = value;
      if (_current != null && _current!.key == key) {
        final pct = (value * 100).clamp(0, 100).toInt();
        final title = _current!.title.isNotEmpty ? _current!.title : _current!.slug;
        _updateNativeForeground(title, _current!.episode, pct, '$pct%');
      }
    }
    progress.value = m;
  }

  void _markFailure(String key, String message) {
    final m = Map<String, String>.from(failures.value);
    m[key] = message;
    failures.value = m;
  }

  void _clearFailure(String key) {
    if (!failures.value.containsKey(key)) return;
    final m = Map<String, String>.from(failures.value);
    m.remove(key);
    failures.value = m;
  }

  Future<void> _runJob(_Job job) async {
    final root = await _ensureRoot();
    final videoTmp = File(
      '${_videoFile(root, job.slug, job.episode).path}$_partSuffix',
    );
    final tmpPlaylist = File(
      '${videoTmp.parent.path}/ep_${job.episode}_index$_partSuffix.m3u8',
    );
    final segsTmpDir = Directory(
      '${videoTmp.parent.path}/ep_${job.episode}_segs$_partSuffix',
    );
    IOSink? sink;
    try {
      await _ensureEpisodesDir(root, job.slug);

      // 1. Resolver detalle del episodio (embeds SUB/DUB).
      final detail = await ApiService.fetchEpisodeDetail(job.slug, job.episode);
      if (_cancelRequested) return;

      // Preferencia del usuario: DUB si el capítulo lo tiene; si no,
      // cae automáticamente al subtitulado. Con preferDub=false siempre SUB.
      final hasDub =
          detail.variants.any((v) => v.toUpperCase() == 'DUB');
      final variant = job.preferDub && hasDub
          ? 'DUB'
          : detail.variants.where((v) => v.toUpperCase() != 'DUB').isNotEmpty
              ? detail.variants
                  .where((v) => v.toUpperCase() != 'DUB')
                  .first
              : (detail.variants.isNotEmpty ? detail.variants.first : 'SUB');
      // Candidatos reproducibles: HLS, UPNShare, Voe, MP4Upload, Byse
      bool isDownloadable(ServerMirror s) {
        final name = s.server.toLowerCase();
        final url = s.url.toLowerCase();
        if (name.contains('hls')) return true;
        if (name.contains('mp4upload')) return true;
        if (name.contains('upnshare') || url.contains('uns.bio')) return true;
        if (name.contains('voe') || url.contains('voe.sx')) return true;
        if (name.contains('byse') || url.contains('byselapuix.com')) return true;
        if (url.contains('.m3u8') || url.contains('mp4upload.com') || url.contains('.mp4')) return true;
        return false;
      }

      final playable = <ServerMirror>[];
      for (final s in detail.embeds) {
        if (s.variant != variant) continue;
        if (isDownloadable(s)) {
          playable.add(s);
        }
      }
      // Fallback: si la variante pedida no tiene servidores descargables,
      // probar cualquier variante (manteniendo preferencia DUB/SUB).
      if (playable.isEmpty) {
        for (final s in detail.embeds) {
          if (isDownloadable(s)) {
            playable.add(s);
          }
        }
      }
      if (playable.isEmpty) {
        throw Exception('Sin fuente descargable para ep ${job.episode}');
      }
      // Orden: HLS (Zilla) -> UPNShare -> Voe -> MP4Upload -> Byse.
      playable.sort((a, b) {
        int rank(ServerMirror s) {
          final n = s.server.toLowerCase();
          final u = s.url.toLowerCase();
          if (n.contains('hls') || u.contains('zilla')) return 0;
          if (n.contains('upnshare') || u.contains('uns.bio')) return 1;
          if (n.contains('voe') || u.contains('voe.sx')) return 2;
          if (n.contains('mp4upload')) return 3;
          if (n.contains('byse') || u.contains('byselapuix.com')) return 4;
          return 5;
        }
        return rank(a).compareTo(rank(b));
      });

      // 2+3. Resolver URL real y descargar, con failover entre servidores.
      // Si un servidor responde mal (p.ej. 522 de Zilla), marcar y probar el
      // siguiente. Último error se lanza si todos fallan.
      ServerMirror? chosen;
      String? wonType;
      String? lastError;
      final sw = Stopwatch();

      // Precalentamiento temprano en paralelo: mientras el HLS intenta (y
      // probablemente falla con 522), despertar el origin del MP4Upload
      // (Range 0-0) para que cuando el failover salte, el primer byte llegue
      // en ~7s y no en 20-35s. El prewarm nunca bloquea el bucle.
      Future<void> prewarmMp4() async {
        final mp4candidate = playable
            .where((s) => s.server.toLowerCase().contains('mp4upload'))
            .toList();
        if (mp4candidate.isEmpty) return;
        try {
          final resolved = await ApiService.fetchVideoUrl(mp4candidate.first.url);
          final u = resolved['url'] as String?;
          if (u == null || u.isEmpty) return;
          await ApiService.prewarmVideo(u,
              headers: {'Referer': 'https://www.mp4upload.com/'});
        } catch (_) {}
      }
      final earlyWarm = prewarmMp4();
      // No bloquear: correr en paralelo con el primer intento del bucle.
      // (El await real está al final si el ganador es MP4 sin haber calentado).

      for (final candidate in playable) {
        if (_cancelRequested) return;
        chosen = candidate;
        sw
          ..reset()
          ..start();
        try {
          final resolved = await ApiService.fetchVideoUrl(candidate.url);
          final url = resolved['url'] as String?;
          final type = resolved['type'] as String? ?? '';
          if (url == null || url.isEmpty || type == 'embed') {
            throw Exception('URL no descargable directamente para ep ${job.episode} ($type)');
          }
          final customHeaders = (resolved['headers'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString()));

          if (_cancelRequested) return;

          if (type == 'hls') {
            await _downloadHls(url, tmpPlaylist, segsTmpDir, job.key,
                () => _cancelRequested, headers: customHeaders);
          } else {
            // El prewarm temprano (earlyWarm) ya está calentando este mismo
            // origin en paralelo; esperarlo aquí evita duplicar el request
            // Range 0-0 y arranca la descarga contra un origin caliente.
            try {
              await earlyWarm.timeout(const Duration(seconds: 32));
            } catch (_) {}
            await _downloadDirect(
              url,
              videoTmp,
              job.key,
              referer: customHeaders?['Referer'] ?? 'https://www.mp4upload.com/',
            );
          }

          // Validación mínima: si el stream vino mal, no darlo por bueno.
          if (type == 'hls') {
            final pl = await tmpPlaylist.length();
            if (pl < 200) throw Exception('Playlist HLS inválido ($pl B)');
            final segCount = segsTmpDir.listSync().length;
            if (segCount < 2) {
              throw Exception('Segmentos insuficientes ($segCount)');
            }
          } else {
            final size = await videoTmp.length();
            if (size < 1024 * 1024) {
              throw Exception(
                  'Archivo demasiado pequeño ($size B), probablemente inválido');
            }
            if (!_looksLikeMp4(videoTmp)) {
              throw Exception('El archivo descargado no parece video MP4');
            }
          }

          // Éxito: salir del bucle con este servidor.
          wonType = type;
          break;
        } catch (e) {
          lastError = '$e';
          debugPrint('DOWNLOAD server ${candidate.server} falló: $e');
          // Limpiar parciales de este intento antes de probar el siguiente.
          for (final p in [videoTmp.path, tmpPlaylist.path]) {
            try {
              final f = File(p);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
          try {
            if (await segsTmpDir.exists()) {
              await segsTmpDir.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
      // Medir solo el tiempo del servidor ganador (reset/start por intento).
      sw.stop();
      if (chosen == null) {
        throw Exception('Sin fuente descargable para ep ${job.episode}');
      }
      if (lastError != null &&
          !(await videoTmp.exists()) &&
          !(await tmpPlaylist.exists())) {
        throw Exception('Todas las fuentes fallaron para ep ${job.episode}: $lastError');
      }
      if (_cancelRequested) return;

      // 5. Publicar el episodio en su destino final.
      // HLS → playlist local + segmentos (ExoPlayer calcula duración exacta
      // desde los EXTINF; seek correcto). MP4 → archivo único renombrado.
      int size;
      if (wonType == 'hls') {
        final dir = _hlsDir(root, job.slug, job.episode);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        await dir.create(recursive: true);
        await tmpPlaylist.rename('${dir.path}/index.m3u8');
        final segsDir = Directory('${dir.path}/segs');
        await segsDir.create();
        await for (final f in segsTmpDir.list()) {
          await (f as File).rename('${segsDir.path}/${f.uri.pathSegments.last}');
        }
        try {
          await segsTmpDir.delete(recursive: true);
        } catch (_) {}
        size = await _dirSize(dir);
      } else {
        final finalVideo = _videoFile(root, job.slug, job.episode);
        if (await finalVideo.exists()) await finalVideo.delete();
        await videoTmp.rename(finalVideo.path);
        size = await finalVideo.length();
      }

      // 6. Sidecar con metadatos del episodio.
      await _atomicWrite(
        _sidecarFile(root, job.slug, job.episode),
        utf8.encode(jsonEncode({
          'episode': job.episode,
          'size': size,
          'variant': chosen.variant.isEmpty ? variant : chosen.variant,
          'dub': job.preferDub && hasDub,
          'server': chosen.server,
          'seconds': sw.elapsedMilliseconds / 1000.0,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
        })),
      );

      // 7. Actualizar índice.
      _rebuildIndexFromDisk(root, job.slug);
      await _saveIndex(root);
      // 8. Registrar en completadas de sesión (feedback del gestor).
      final m = List<Map<String, dynamic>>.from(recentCompleted.value);
      m.removeWhere((e) => e['key'] == job.key);
      m.insert(0, {
        'key': job.key,
        'slug': job.slug,
        'episode': job.episode,
        'title': titleFor(job.slug),
        'bytes': size,
        'dub': job.preferDub && hasDub,
      });
      if (m.length > 20) {
        recentCompleted.value = m.sublist(0, 20);
      } else {
        recentCompleted.value = m;
      }
      debugPrint('DOWNLOAD OK: ${job.key} ($size bytes)');
    } catch (e) {
      debugPrint('DOWNLOAD FAIL: ${job.key} → $e');
      if (!_cancelRequested) {
        _markFailure(job.key, '$e');
        // Marcar para reencolado al final (reintento con jerarquía).
        _failedJobs.add(job.key);
      }
      // Limpiar parciales para no dejar basura.
      for (final p in [videoTmp.path, tmpPlaylist.path]) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      try {
        if (await segsTmpDir.exists()) await segsTmpDir.delete(recursive: true);
      } catch (_) {}
      if (!_cancelRequested) rethrow;
    } finally {
      _stallTimer?.cancel();
      final s = sink;
      if (s != null) {
        try {
          await s.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _ensureEpisodesDir(Directory root, String slug) async {
    final d = _episodesDir(root, slug);
    if (!await d.exists()) await d.create(recursive: true);
  }

  Future<void> _saveMeta(
    Directory root,
    int animeId,
    String slug,
    String title,
    String synopsis,
    String? posterUrl, {
    AnimeDetail? detail,
  }) async {
    final meta = _readMetaSafe(root, slug);
    if (meta != null &&
        meta['synopsis'] != null &&
        (meta['synopsis'] as String).isNotEmpty &&
        (detail == null || (meta['genres'] as List? ?? []).isNotEmpty)) {
      return; // Ya guardado completo; no re-descargar poster.
    }
    await _ensureEpisodesDir(root, slug);
    String? posterPath;
    if (posterUrl != null && posterUrl.isNotEmpty) {
      try {
        final bytes = await _fetchBytes(posterUrl);
        if (bytes != null && bytes.length > 1024) {
          final pf = File('${root.path}/$slug/poster.jpg.tmp');
          await pf.writeAsBytes(bytes, flush: true);
          final target = File('${root.path}/$slug/poster.jpg');
          if (await target.exists()) await target.delete();
          await pf.rename(target.path);
          posterPath = 'poster.jpg';
          // Disponible al instante para el FAB/gestor.
          _posterOverrides[slug] = target.path;
        }
      } catch (e) {
        debugPrint('POSTER DL FAIL $slug: $e');
      }
    }
    await _atomicWrite(
      _metaFile(root, slug),
      utf8.encode(jsonEncode({
        'anime_id': animeId,
        'title': title,
        'synopsis': synopsis,
        'poster': posterPath ?? (meta?['poster'] as String? ?? ''),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        if (detail != null) ...{
          'status': detail.status,
          'category': detail.category,
          'episodes_count': detail.episodesCount,
          'genres': detail.genres.map((g) => g.name).toList(),
          'episodes': detail.episodes
              .map((e) => {'id': e.id, 'number': e.number})
              .toList(),
        } else ...{
          // Preservar etiquetas de un meta previo si no llega detalle.
          'status': meta?['status'] ?? '',
          'category': meta?['category'] ?? '',
          'genres': meta?['genres'] ?? <String>[],
          'episodes': meta?['episodes'] ?? <Map>[],
        },
      })),
    );
  }

  static Future<List<int>?> _fetchBytes(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static bool _looksLikeMp4(File f) {
    try {
      final raf = f.openSync();
      try {
        final head = raf.readSync(12);
        if (head.length < 12) return false;
        // ftyp en offsets 4-8 (MP4/MOV) o styp en fMP4 crudo.
        final sig = String.fromCharCodes(head.sublist(4, 8));
        return sig == 'ftyp' || sig == 'styp' || sig == 'moov' || sig == 'mdat';
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  // ── Descarga directa (MP4 progresivo, mp4upload) ──────────────────────

  Future<void> _downloadDirect(
    String url,
    File target,
    String progressKey, {
    String? referer,
    Map<String, String> extraHeaders = const {},
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36');
      if (referer != null) req.headers.set(HttpHeaders.refererHeader, referer);
      extraHeaders.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw Exception('HTTP ${resp.statusCode} al descargar $url');
      }
      final total = resp.contentLength > 0 ? resp.contentLength : -1;
      var received = 0;
      sink = target.openWrite();
      lastActivity = DateTime.now();
      _startStallWatchdog(progressKey);
      await for (final chunk in resp) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          _setProgress(progressKey, received / total);
        }
        lastActivity = DateTime.now();
        if (_cancelRequested) break;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (_cancelRequested) {
        return; // Cancelación silenciosa: finally limpia el .part.
      }
    } catch (e) {
      if (_cancelRequested) return; // Cancelación: no propagar como error.
      rethrow;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  DateTime lastActivity = DateTime.now();

  /// Watchdog anti-stall: si no llegan bytes en 45s, aborta el intento
  /// (el usuario puede reintentar; evita colgar la cola indefinidamente).
  void _startStallWatchdog(String progressKey) {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 15), (t) {
      final idle = DateTime.now().difference(lastActivity);
      if (idle.inSeconds > 45) {
        t.cancel();
        debugPrint('DOWNLOAD STALL: $progressKey sin datos ${idle.inSeconds}s');
        _cancelRequested = true; // Aborta como cancelación → limpia .part.
      }
    });
  }

  // ── Descarga HLS (zilla-networks): playlist + segmentos fMP4 ──────────
  // El episodio se guarda como playlist M3U8 LOCAL + archivos de segmento
  // en disco (no concatenados). ExoPlayer lee los EXTINF del playlist y
  // conoce la duración total y los puntos de seek desde el inicio.

  Future<void> _downloadHls(
    String masterUrl,
    File playlistOut,
    Directory segsDir,
    String progressKey,
    bool Function() cancelled, {
    Map<String, String>? headers,
  }) async {
    final reqHeaders = headers ?? _zillaHeaders();

    // 1. Obtener el playlist de medios (resuelve master multi-variante).
    var mediaUrl = masterUrl;
    final masterBytes = await _fetchBytes(mediaUrl, headers: reqHeaders);
    if (masterBytes == null) {
      throw Exception('No se pudo bajar el playlist HLS');
    }
    var playlist = utf8.decode(masterBytes, allowMalformed: true);
    if (playlist.contains('#EXT-X-STREAM-INF')) {
      final lines = playlist.split('\n');
      String? child;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF') && i + 1 < lines.length) {
          child = lines[i + 1].trim();
          break;
        }
      }
      if (child == null || child.startsWith('#')) {
        throw Exception('Master HLS sin variantes');
      }
      mediaUrl = Uri.parse(masterUrl).resolve(child).toString();
      final mediaBytes = await _fetchBytes(mediaUrl, headers: reqHeaders);
      if (mediaBytes == null) throw Exception('No se pudo bajar la variante HLS');
      playlist = utf8.decode(mediaBytes, allowMalformed: true);
    }
    if (cancelled()) return;

    // 2. Parsear segmentos, EXTINF e init, resolviendo rutas relativas.
    final base = Uri.parse(
      mediaUrl.substring(0, mediaUrl.lastIndexOf('/') + 1),
    );
    Uri resolveUri(String ref) =>
        ref.startsWith('http') ? Uri.parse(ref) : base.resolve(ref);

    final entries = <({String ref, double? seconds})>[];
    String? initSeg;
    final headTags = <String>[];
    var pendingInf = -1.0;
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-MAP:')) {
        final m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null) initSeg = m.group(1);
      } else if (line.startsWith('#EXTINF:')) {
        final v = double.tryParse(
            line.substring(8).replaceAll(RegExp(r'[,\s].*$'), ''));
        pendingInf = v ?? -1.0;
      } else if (line.startsWith('#')) {
        // Conserva TARGETDURATION, VERSION, etc. Descarta ENDLIST propio.
        if (!line.startsWith('#EXT-X-ENDLIST') &&
            !line.startsWith('#EXTINF:')) {
          headTags.add(line);
        }
      } else {
        entries.add((
          ref: line,
          seconds: pendingInf >= 0 ? pendingInf : null,
        ));
        pendingInf = -1.0;
      }
    }
    if (entries.isEmpty) throw Exception('Playlist HLS sin segmentos');
    if (segsLinesTooMany(entries.length)) {
      throw Exception('Playlist HLS demasiado grande (${entries.length})');
    }

    // 3. Escribir playlist local con referencias a los archivos descargados.
    // Cada EXTINF va INMEDIATAMENTE antes de su segmento (requisito HLS);
    // ExoPlayer usa esos valores para duración total y seeking exacto.
    final buf = StringBuffer('#EXTM3U\n');
    for (final t in headTags) {
      buf.writeln(t);
    }
    if (initSeg != null) buf.writeln('#EXT-X-MAP:URI="segs/init.m4s"');
    for (var i = 0; i < entries.length; i++) {
      final s = entries[i].seconds;
      buf.writeln('#EXTINF:${s?.toStringAsFixed(6) ?? '4.000000'},');
      buf.writeln('segs/seg_${i.toString().padLeft(4, '0')}.m4s');
    }
    buf.writeln('#EXT-X-ENDLIST');
    await segsDir.create(recursive: true);
    await playlistOut.parent.create(recursive: true);
    await playlistOut.writeAsString(buf.toString(), flush: true);

    // 4. Bajar init + segmentos en secuencia a segs/.
    lastActivity = DateTime.now();
    _startStallWatchdog(progressKey);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final total = entries.length + (initSeg != null ? 1 : 0);
    var done = 0;
    try {
      Future<void> fetchSeg(Uri uri, File out) async {
        final req = await client.getUrl(uri);
        reqHeaders.forEach((k, v) => req.headers.set(k, v));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode} en $uri');
        }
        final tmpOut = File('${out.path}$_partSuffix');
        final sink = tmpOut.openWrite();
        try {
          await for (final chunk in resp) {
            sink.add(chunk);
            lastActivity = DateTime.now();
          }
          await sink.flush();
          await sink.close();
        } catch (_) {
          try {
            await sink.close();
          } catch (_) {}
          if (await tmpOut.exists()) await tmpOut.delete();
          rethrow;
        }
        if (await out.exists()) await out.delete();
        await tmpOut.rename(out.path);
      }

      if (initSeg != null && !cancelled()) {
        await fetchSeg(resolveUri(initSeg), File('${segsDir.path}/init.m4s'));
        done++;
        _setProgress(progressKey, done / total);
      }
      for (var i = 0; i < entries.length; i++) {
        if (cancelled()) return;
        await fetchSeg(
          resolveUri(entries[i].ref),
          File('${segsDir.path}/seg_${i.toString().padLeft(4, '0')}.m4s'),
        );
        done++;
        _setProgress(progressKey, done / total);
      }
    } finally {
      client.close(force: true);
      _stallTimer?.cancel();
    }
  }

  static bool segsLinesTooMany(int n) => n > 100000;

  static Map<String, String> _zillaHeaders() => {
        HttpHeaders.userAgentHeader:
            'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-origin',
        HttpHeaders.acceptHeader: '*/*',
        HttpHeaders.refererHeader: 'https://player.zilla-networks.com/',
      };
}

class _Job {
  final String key;
  final String slug;
  final int episode;
  final bool preferDub;
  final String title;

  _Job({
    required this.key,
    required this.slug,
    required this.episode,
    this.preferDub = false,
    this.title = '',
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'slug': slug,
        'episode': episode,
        'preferDub': preferDub,
        'title': title,
      };

  factory _Job.fromJson(Map<String, dynamic> json) => _Job(
        key: json['key'] as String? ?? '${json['slug']}#${json['episode']}',
        slug: json['slug'] as String? ?? '',
        episode: (json['episode'] as num?)?.toInt() ?? 1,
        preferDub: json['preferDub'] as bool? ?? false,
        title: json['title'] as String? ?? '',
      );
}
