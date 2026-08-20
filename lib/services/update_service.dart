import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Información de una actualización disponible.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseUrl,
    this.fileName,
    this.notes,
  });

  final String latestVersion; // ej. "1.2.9"
  final String downloadUrl; // URL del APK o instalador .exe
  final String releaseUrl;
  final String? fileName;
  final String? notes;

  /// Alias de compatibilidad.
  String get apkUrl => downloadUrl;
}

/// UpdateService — actualización automática desde GitHub Releases.
///
/// Flujo:
/// 1. `checkForUpdate()` consulta la última release del repo y compara la
///    versión semántica con la instalada (vía canal nativo en Android o versión del app).
/// 2. Si hay versión nueva → `hasUpdate` = true. La app lo muestra con un
///    diálogo Actualizar/Posponer al arrancar y con un botón-badge junto al
///    avatar de cuenta.
/// 3. `downloadAndInstall()` descarga el APK/.exe DENTRO de la app (con progreso,
///    sin abrir el navegador) y lanza la instalación (FileProvider en Android,
///    proceso desacoplado en Windows).
/// 4. Los archivos temporales se limpian tras la instalación.
class UpdateService {
  UpdateService._();

  static const MethodChannel _channel =
      MethodChannel('com.mapleprojects.animaple/updater');

  // Repo público de releases.
  static const _repoOwner = 'MapleProjects';
  static const _repoName = 'AniMaple';

  /// Versión de la app por defecto / compilada.
  static const String appVersion = '1.2.10';

  /// Notifica a la UI cuando hay (o deja de haber) una actualización.
  static final ValueNotifier<bool> hasUpdate = ValueNotifier(false);

  static UpdateInfo? _pending;

  static UpdateInfo? get pending => _pending;
  static String? get latestVersion => _pending?.latestVersion;
  static bool get isUpdateAvailable => _pending != null;

  /// Versión actual instalada (ej. "1.2.9").
  static String get currentVersion => _currentVersion ?? appVersion;
  static String? _currentVersion;

  static bool _checked = false;

  /// Lee la versión instalada desde el canal nativo (PackageManager en Android) o fallback.
  static Future<String?> _loadCurrentVersion() async {
    if (Platform.isAndroid) {
      try {
        final v = await _channel.invokeMethod<String>('getCurrentVersion');
        if (v != null && v.isNotEmpty) {
          _currentVersion = v;
          return v;
        }
      } catch (_) {}
    }
    _currentVersion = appVersion;
    return _currentVersion;
  }

  /// Consulta la última release de GitHub una vez. Idempotente por proceso.
  /// Silencioso ante errores de red — nunca bloquea el arranque.
  static Future<bool> checkForUpdate() async {
    if (_checked) return isUpdateAvailable;
    _checked = true;
    try {
      await _loadCurrentVersion();
      final resp = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'AniMaple-$_repoName',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return false;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '');
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;

      // Buscar el archivo instalador (.exe para Windows, .apk para Android)
      final assets = (data['assets'] as List? ?? []);
      String? downloadUrl;
      String? downloadFileName;

      if (Platform.isWindows) {
        for (final a in assets) {
          final name = (a as Map)['name'] as String? ?? '';
          if (name.toLowerCase().endsWith('.exe')) {
            downloadUrl = a['browser_download_url'] as String?;
            downloadFileName = name;
            if (name.toLowerCase().contains('setup') ||
                name.toLowerCase().contains('animaple')) {
              break;
            }
          }
        }
      } else if (Platform.isAndroid) {
        for (final a in assets) {
          final name = (a as Map)['name'] as String? ?? '';
          if (name.toLowerCase().endsWith('.apk')) {
            downloadUrl = a['browser_download_url'] as String?;
            downloadFileName = name;
            if (name == 'app-release.apk') {
              break;
            }
          }
        }
      } else {
        for (final a in assets) {
          final name = (a as Map)['name'] as String? ?? '';
          downloadUrl = a['browser_download_url'] as String?;
          downloadFileName = name;
          break;
        }
      }

      if (downloadUrl == null) {
        debugPrint('Update: no asset found for current platform');
        return false;
      }

      if (_isNewer(latest, currentVersion)) {
        _pending = UpdateInfo(
          latestVersion: latest,
          downloadUrl: downloadUrl,
          releaseUrl:
              (data['html_url'] as String?) ?? 'https://github.com/$_repoOwner/$_repoName/releases',
          fileName: downloadFileName,
          notes: _extractNotes(data['body'] as String?, latest),
        );
        hasUpdate.value = true;
        debugPrint('Update: disponible $latest ($downloadFileName, actual: $currentVersion)');
        return true;
      }
      debugPrint('Update: sin novedades ($latest == $currentVersion)');
      return false;
    } catch (e) {
      debugPrint('Update check skip: $e');
      return false;
    }
  }

  /// Compara dos versiones semánticas "x.y.z" → true si [a] > [b].
  static bool _isNewer(String a, String b) {
    final pa = _parse(a), pb = _parse(b);
    if (pa == null || pb == null) return false;
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] > pb[i];
    }
    return false;
  }

  static List<int>? _parse(String v) {
    final parts = v.split('.');
    if (parts.length < 2) return null;
    final out = <int>[];
    for (final p in parts.take(3)) {
      final n = int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n == null) return null;
      out.add(n);
    }
    while (out.length < 3) {
      out.add(0);
    }
    return out;
  }

  static String? _extractNotes(String? body, String latest) {
    if (body == null || body.isEmpty) return null;
    // Recortar notas a un tamaño razonable para el diálogo.
    final clean = body.trim();
    if (clean.length > 900) return '${clean.substring(0, 900)}…';
    return clean;
  }

  /// Ruta del directorio donde se descarga el archivo de actualización.
  static Future<String> updatesDir() async {
    if (Platform.isAndroid) {
      try {
        final d = await _channel.invokeMethod<String>('getUpdatesDir');
        if (d != null && d.isNotEmpty) return d;
      } catch (_) {}
    }
    final tempDir = Directory('${Directory.systemTemp.path}/AniMapleUpdates');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir.path;
  }

  /// Descarga el instalador/APK dentro de la app. Devuelve la ruta del archivo.
  /// [onProgress] recibe 0.0→1.0 durante la descarga. Lanza si falla.
  static Future<String> downloadFile({
    required String url,
    String? fileName,
    void Function(double)? onProgress,
  }) async {
    final dir = await updatesDir();
    if (dir.isEmpty) {
      throw Exception('No se pudo preparar la carpeta de descarga');
    }
    final name = fileName ??
        (Platform.isWindows ? 'animaple-setup.exe' : 'app-update.apk');
    final target = '$dir/$name';

    final req = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    try {
      final resp = await client.send(req).timeout(const Duration(seconds: 180));
      if (resp.statusCode != 200) {
        throw Exception('Error al descargar (HTTP ${resp.statusCode})');
      }
      final total = resp.contentLength ?? 0;
      final file = File(target);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      if (total > 0 && received < total) {
        throw Exception('Descarga incompleta');
      }
      return target;
    } finally {
      client.close();
    }
  }

  /// Alias de compatibilidad.
  static Future<String> downloadApk({
    required String url,
    void Function(double)? onProgress,
  }) =>
      downloadFile(url: url, onProgress: onProgress);

  /// Pide la instalación de la actualización (nativo en Android, proceso desacoplado en Windows).
  /// Devuelve true si se lanzó el instalador.
  static Future<bool> requestInstall(String filePath) async {
    if (Platform.isWindows) {
      try {
        final file = File(filePath);
        if (!await file.exists()) {
          debugPrint('Update installer not found at $filePath');
          return false;
        }
        debugPrint('Update: ejecutando instalador $filePath');
        await Process.start(filePath, [], mode: ProcessStartMode.detached);
        // Cierra la app para permitir que el instalador sobrescriba los binarios
        Future.delayed(const Duration(milliseconds: 300), () {
          exit(0);
        });
        return true;
      } catch (e) {
        debugPrint('Update Windows install error: $e');
        return false;
      }
    } else if (Platform.isAndroid) {
      try {
        final ok =
            await _channel.invokeMethod<bool>('installApk', {'path': filePath});
        return ok ?? false;
      } catch (e) {
        debugPrint('Update install invoke error: $e');
        return false;
      }
    }
    return false;
  }

  /// Limpieza manual de archivos de actualización restantes.
  static Future<void> cleanupDownloaded() async {
    try {
      final dir = await updatesDir();
      if (dir.isEmpty) return;
      final d = Directory(dir);
      if (await d.exists()) {
        final entries = d.listSync();
        for (final e in entries) {
          if (e is File) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  //  UI
  // ─────────────────────────────────────────────────────────

  /// Muestra el diálogo de actualización. Actualizar a la derecha, Posponer
  /// a la izquierda. Devuelve true si el usuario eligió actualizar.
  static Future<bool?> showUpdateDialog(BuildContext context) {
    final info = _pending;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16121f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.system_update_alt, color: Color(0xFFa78bfa), size: 34),
        title: const Text(
          'Nueva versión disponible',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFe8e4f0)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info == null
                  ? 'Hay una nueva versión de AniMaple.'
                  : 'Estás usando $currentVersion. La versión ${info.latestVersion} ya está disponible.',
              style: const TextStyle(fontSize: 13, color: Color(0xFFb8b0cd)),
            ),
            if (info?.notes != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF110e1a),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2a2438)),
                  ),
                  child: SingleChildScrollView(
                    child: _MarkdownNotes(info!.notes!),
                  ),
                ),
              ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Posponer',
              style: TextStyle(color: Color(0xFF6d6488), fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8b5cf6),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Comprueba (y pide si falta) el permiso de instalar apps desconocidas
  /// ANTES de descargar, para que no haya que volver a bajar el APK si era la
  /// primera vez. Devuelve true si se puede proceder a descargar.
  static Future<bool> ensureInstallPermission(BuildContext context) async {
    bool canInstall;
    try {
      canInstall = await _channel
              .invokeMethod<bool>('canRequestPackageInstalls') ??
          true;
    } catch (_) {
      // Plataforma sin permiso de instalación (desktop/web) → continuar.
      return true;
    }
    if (canInstall) return true;
    if (!context.mounted) return false;

    // Pedir el permiso ahora, antes de descargar.
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16121f),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.security, color: Color(0xFFa78bfa), size: 30),
        title: const Text(
          'Permiso para instalar',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFe8e4f0)),
        ),
        content: const Text(
          'Para instalar la actualización, AniMaple necesita permiso para '
          'instalar apps desconocidas. Se abrirá la configuración del sistema.',
          style: TextStyle(fontSize: 13, color: Color(0xFFb8b0cd)),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF6d6488), fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8b5cf6),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Permitir', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return false;

    // Abrir los ajustes de "Instalar apps desconocidas".
    try {
      await _channel.invokeMethod('requestInstallPermission');
    } catch (_) {}

    // Esperar a que el usuario vuelva de los ajustes y re-verificar.
    final completer = Completer<void>();
    final awaiter = _ResumeAwaiter(completer);
    WidgetsBinding.instance.addObserver(awaiter);
    try {
      await completer.future.timeout(const Duration(seconds: 60));
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(awaiter);

    try {
      return await _channel
              .invokeMethod<bool>('canRequestPackageInstalls') ??
          false;
    } catch (_) {
      return true;
    }
  }

  /// Descarga + instalación con diálogo de progreso.
  static Future<void> downloadAndInstall(BuildContext context) async {
    final info = _pending;
    if (info == null) return;

    // Permiso de instalación ANTES de descargar (evita re-descargar el APK
    // si es la primera vez y hay que ir a habilitar "fuentes desconocidas").
    final canInstall = await ensureInstallPermission(context);
    if (!canInstall || !context.mounted) return;

    final progress = ValueNotifier<double>(0);
    final errorMsg = ValueNotifier<String?>(null);
    final done = ValueNotifier<bool>(false);

    // Diálogo que se refresca solo con los ValueNotifier.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: done.value || errorMsg.value != null,
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (ctx, p, _) => ValueListenableBuilder<String?>(
            valueListenable: errorMsg,
            builder: (ctx, err, _) => AlertDialog(
              backgroundColor: const Color(0xFF16121f),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Descargando actualización…',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFFe8e4f0)),
              ),
              content: err != null
                  ? Text(
                      'No se pudo completar la actualización:\n$err',
                      style: const TextStyle(fontSize: 13, color: Color(0xFFf87171)),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: p,
                          minHeight: 6,
                          backgroundColor: const Color(0xFF2a2438),
                          color: const Color(0xFF8b5cf6),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${(p * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFb8b0cd)),
                        ),
                      ],
                    ),
              actions: err != null
                  ? [
                      TextButton(
                        onPressed: () {
                          done.value = true;
                          Navigator.pop(ctx);
                        },
                        child: const Text('Cerrar', style: TextStyle(color: Color(0xFF6d6488))),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );

    try {
      final path = await downloadFile(
        url: info.downloadUrl,
        fileName: info.fileName,
        onProgress: (v) => progress.value = v.clamp(0.0, 1.0),
      );
      progress.value = 1.0;
      done.value = true;
      // Pedir e instalar (en Android o Windows). La app se cierra al actualizar.
      final launched = await requestInstall(path);
      if (launched) {
        // La app se cierra con la instalación; pequeño margen para el 100%.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } else {
        // El instalador no se pudo lanzar (permiso/rechazo): notificar.
        errorMsg.value = Platform.isWindows
            ? 'No se pudo iniciar el instalador de actualización.'
            : 'No se pudo iniciar la instalación. Habilita permitir fuentes desconocidas e inténtalo de nuevo.';
        await cleanupDownloaded();
      }
    } catch (e) {
      errorMsg.value = '$e';
      await cleanupDownloaded();
    } finally {
      // Solo se cierra solo cuando la instalación ya empezó y la app caduca.
      if (done.value && errorMsg.value == null) {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }
}

/// Observa el ciclo de vida de la app para detectar cuándo el usuario vuelve
/// de los ajustes de "Instalar apps desconocidas" a la app.
class _ResumeAwaiter extends WidgetsBindingObserver {
  _ResumeAwaiter(this._completer);

  final Completer<void> _completer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_completer.isCompleted) _completer.complete();
    }
  }
}

/// Renderiza el markdown de las notas del release como texto legible
/// (headers, lista de puntos, negrita). Sin dependencias externas.
class _MarkdownNotes extends StatelessWidget {
  const _MarkdownNotes(this._text);

  final String _text;

  // Extrae los segmentos de una línea y estilo bold para los `**...**`.
  static List<TextSpan> _inlineSpans(String line) {
    const bold = TextStyle(fontSize: 12, color: Color(0xFFe8e4f0), fontWeight: FontWeight.w700, height: 1.35);
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final m in regex.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: bold));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    if (spans.isEmpty) spans.add(TextSpan(text: line));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = _text.split('\n');
    final children = <Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }
      // Header nivel 2: "## Título"
      if (line.startsWith('## ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 3),
          child: Text(
            line.substring(3).trim(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFe8e4f0)),
          ),
        ));
        continue;
      }
      // Header nivel 3: "### Subtítulo"
      if (line.startsWith('### ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(
            line.substring(4).trim(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFa78bfa)),
          ),
        ));
        continue;
      }
      // Lista: "- ítem"
      if (line.trimLeft().startsWith('- ')) {
        children.add(RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 12, color: Color(0xFFb8b0cd), height: 1.35),
            children: [
              const TextSpan(text: '•  ', style: TextStyle(color: Color(0xFF8b5cf6), fontWeight: FontWeight.w900)),
              ..._inlineSpans(line.trimLeft().substring(2)),
            ],
          ),
        ));
        continue;
      }
      // Párrafo plano
      children.add(RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Color(0xFFb8b0cd), height: 1.35),
          children: _inlineSpans(line),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}
