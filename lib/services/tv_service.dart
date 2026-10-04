import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio singleton para detección y gestión de Android TV / Pantallas 10-foot.
class TvService {
  static const _channel = MethodChannel('com.mapleprojects.animaple/tv');
  static const _prefTvOverride = 'tv_mode_override';

  /// Notificador reactivo del modo TV (permite que la UI cambie dinámicamente)
  static final ValueNotifier<bool> isTv = ValueNotifier<bool>(false);

  /// Acceso directo al estado actual
  static bool get isTvMode => isTv.value;

  /// Inicializa la detección al arrancar la aplicación
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userOverride = prefs.getBool(_prefTvOverride);

      if (userOverride != null) {
        isTv.value = userOverride;
        debugPrint('[TvService] Modo TV forzado por usuario: $userOverride');
        return;
      }

      if (!kIsWeb && Platform.isAndroid) {
        final detected = await _channel.invokeMethod<bool>('isTvMode');
        isTv.value = detected ?? false;
        debugPrint('[TvService] Detección Android TV nativa: ${isTv.value}');
      } else {
        // En escritorio o web no es Android TV por defecto
        isTv.value = false;
      }
    } catch (e) {
      debugPrint('[TvService] Error al detectar modo TV: $e');
      isTv.value = false;
    }
  }

  /// Permite alternar o forzar el modo TV manualmente
  static Future<void> setTvMode(bool enabled) async {
    isTv.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefTvOverride, enabled);
    } catch (e) {
      debugPrint('[TvService] Error guardando preferencia TV: $e');
    }
  }
}
