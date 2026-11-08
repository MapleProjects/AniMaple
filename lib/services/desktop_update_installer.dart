import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Descarga, verifica y aplica actualizaciones de escritorio desde un ZIP.
///
/// El reemplazo de archivos lo hace `animaple_updater.exe`, un ejecutable
/// independiente que muestra una ventana con barra de progreso, espera el
/// cierre de la app, copia los archivos y la relanza.
class DesktopUpdateInstaller {
  DesktopUpdateInstaller._();

  static const String updaterName = 'animaple_updater.exe';

  /// Descarga el ZIP, verifica su SHA-256 y lo descomprime.
  ///
  /// Devuelve la ruta del directorio con los archivos listos para copiar.
  static Future<String> downloadAndStage({
    required String url,
    required String fileName,
    required String version,
    String? checksumsUrl,
    void Function(double progress)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final workDir = Directory(
      '${support.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}$version',
    );
    if (await workDir.exists()) {
      await workDir.delete(recursive: true);
    }
    await workDir.create(recursive: true);

    final archiveFile = File(
      '${workDir.path}${Platform.pathSeparator}$fileName',
    );

    await _download(url, archiveFile, onProgress);

    if (checksumsUrl != null && checksumsUrl.isNotEmpty) {
      final expected = await _expectedChecksum(checksumsUrl, fileName);
      if (expected != null) {
        final actual = await _sha256OfFile(archiveFile);
        if (actual.toLowerCase() != expected.toLowerCase()) {
          await archiveFile.delete();
          throw Exception(
            'El paquete descargado no coincide con su firma.\n'
            'Esperado: $expected\nObtenido: $actual',
          );
        }
      }
    }

    final stage = Directory('${workDir.path}${Platform.pathSeparator}stage');
    if (await stage.exists()) {
      await stage.delete(recursive: true);
    }
    await stage.create(recursive: true);

    await extractFileToDisk(archiveFile.path, stage.path);

    final entries = await stage.list().toList();
    if (entries.length == 1 && entries.first is Directory) {
      return entries.first.path;
    }
    return stage.path;
  }

  /// Lanza el actualizador desde el staging y deja que la app se cierre.
  ///
  /// Se ejecuta desde el staging para que también pueda reemplazar el
  /// actualizador instalado, que no está en marcha.
  static Future<void> launchUpdater({
    required String stage,
    required String target,
    required String executable,
  }) async {
    final updater = File('$stage${Platform.pathSeparator}$updaterName');
    if (!await updater.exists()) {
      throw Exception(
        'El paquete no incluye $updaterName. Descarga el instalador desde GitHub.',
      );
    }

    final logDir = Platform.environment['LOCALAPPDATA'] ?? target;
    final logPath = '$logDir${Platform.pathSeparator}AniMaple'
        '${Platform.pathSeparator}update.log';

    // `start` crea un proceso independiente del árbol de la app. Se usa
    // Process.start y no Process.run: run espera a que cmd cierre sus
    // tuberías, y como el actualizador las hereda, la espera no termina
    // nunca y la app no llega a cerrarse.
    await Process.start('cmd.exe', [
      '/c',
      'start',
      '',
      updater.path,
      '--pid',
      '$pid',
      '--stage',
      stage,
      '--target',
      target,
      '--exe',
      executable,
      '--log',
      logPath,
    ]);
  }

  /// Directorio donde está instalada la aplicación.
  static String installDirectory() {
    return File(Platform.resolvedExecutable).parent.path;
  }

  static Future<void> _download(
    String url,
    File destination,
    void Function(double progress)? onProgress,
  ) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'AniMaple-Updater';
      final response = await client.send(request).timeout(
            const Duration(seconds: 60),
          );
      if (response.statusCode != 200) {
        throw Exception('Error al descargar (HTTP ${response.statusCode})');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = destination.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (total > 0 && received < total) {
        throw Exception('Descarga incompleta');
      }
    } finally {
      client.close();
    }
  }

  static Future<String?> _expectedChecksum(
    String checksumsUrl,
    String fileName,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(checksumsUrl),
        headers: {'User-Agent': 'AniMaple-Updater'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      for (final line in const LineSplitter().convert(response.body)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final name = parts.last.replaceFirst('*', '');
        if (name == fileName) return parts.first;
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _sha256OfFile(File file) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return sink.value?.toString() ?? '';
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
