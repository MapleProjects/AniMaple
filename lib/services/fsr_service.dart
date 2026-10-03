import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio global para AMD FidelityFX Super Resolution 1.0 (FSR).
/// Pipeline: deblock de artefactos -> CAS 0.70 -> FSR 1.0 EASU+RCAS
/// (nitidez 3.00, denoise 0.70) escalando cualquier fuente a 2560x1440
/// y persiste la preferencia del usuario entre sesiones de la aplicación.
class FsrService {
  FsrService._();

  static const String _prefKey = 'fsr_2k_enabled';
  static const String _legacyPrefKey = 'sgsr_2k_enabled';
  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(false);
  static String? _cachedShaderPath;

  /// Image Reconstrucción es NATIVA: siempre activa, sin toggle. La
  /// preferencia se mantiene forzada en ON para que el pipeline madVR
  /// (deband + CAS + SMAA) corra en cada reproduccion.
  static Future<void> init() async {
    isEnabled.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
      await prefs.setBool(_legacyPrefKey, true);
    } catch (e) {
      debugPrint('FsrService init error: $e');
    }
  }

  static Future<void> setEnabled(bool value) async {
    // No-op: la reconstruccion es nativa, no se desactiva.
    isEnabled.value = true;
  }

  /// Extrae la cadena de shaders GLSL (deblock + CAS + FSR 1.0) empaquetada
  /// como asset y la almacena localmente para que libmpv (MediaKit) pueda
  /// cargarla de forma directa en disco.
  static Future<String?> getShaderFile() async {
    if (_cachedShaderPath != null && File(_cachedShaderPath!).existsSync()) {
      return _cachedShaderPath!;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final shadersDir = Directory('${dir.path}/shaders');
      if (!await shadersDir.exists()) {
        await shadersDir.create(recursive: true);
      }
      final file = File('${shadersDir.path}/fsr_2k.glsl');
      final data = await rootBundle.loadString('assets/shaders/fsr_2k.glsl');
      if (!file.existsSync() || file.lengthSync() != data.length) {
        await file.writeAsString(data, flush: true);
      }
      final normalized = file.path.replaceAll(r'\', '/');
      _cachedShaderPath = normalized;
      return normalized;
    } catch (e) {
      debugPrint('FsrService getShaderFile error: $e');
      return null;
    }
  }
}
