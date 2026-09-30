import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio global para Qualcomm Snapdragon Game Super Resolution (SGSR 2K).
/// Escala cualquier fuente de video a 2560x1440 en tiempo real y persiste
/// la preferencia del usuario entre sesiones de la aplicación.
class SgsrService {
  SgsrService._();

  static const String _prefKey = 'sgsr_2k_enabled';
  static final ValueNotifier<bool> isEnabled = ValueNotifier<bool>(false);
  static String? _cachedShaderPath;

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isEnabled.value = prefs.getBool(_prefKey) ?? false;
    } catch (e) {
      debugPrint('SgsrService init error: $e');
    }
  }

  static Future<void> setEnabled(bool value) async {
    if (isEnabled.value == value) return;
    isEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (e) {
      debugPrint('SgsrService setEnabled error: $e');
    }
  }

  /// Extrae el shader GLSL empaquetado como asset y lo almacena localmente
  /// para que libmpv (MediaKit) pueda cargarlo de forma directa en disco.
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
      final file = File('${shadersDir.path}/snapdragon_gsr_2k.glsl');
      final data = await rootBundle.loadString('assets/shaders/snapdragon_gsr_2k.glsl');
      await file.writeAsString(data, flush: true);
      _cachedShaderPath = file.path;
      return file.path;
    } catch (e) {
      debugPrint('SgsrService getShaderFile error: $e');
      return null;
    }
  }
}
