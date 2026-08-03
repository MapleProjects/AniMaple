import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/anime.dart';
import 'api_service.dart';

/// NotificationService — coordina el lado nativo de notificaciones.
///
/// Responsabilidades:
/// - Pedir el permiso POST_NOTIFICATIONS al ARRANQUE de la app (no al entrar
///   a un capítulo, como estaba antes).
/// - Mantener el "espejo" de seguidos en nativo: un JSON {slug: titulo} que
///   el Worker de WorkManager lee periódicamente SIN depender de la sesión
///   de Google ni de la red de sincronización.
/// - Agendar la revisión periódica de nuevos capítulos (WorkManager nativo,
///   sobrevive reinicio y app cerrada).
///
/// No usa flutter_local_notifications a propósito: ese plugin exigiría
/// actualizar AGP/desugaring/Java y rompería el toolchain del proyecto.
/// Todo el trabajo de notificación ocurre en Kotlin (Notifier.kt +
/// EpisodeCheckWorker.kt), que ya usa las APIs de plataforma.
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.mapleprojects.animaple/notifications');

  static bool _mirrorRegistered = false;

  /// Pide el permiso de notificaciones. Se llama una vez al arrancar.
  /// En Android 13+ abre el diálogo del sistema SOLO si el usuario aún puede
  /// decidir (nunca lo denegó con "Don't allow"); en versiones anteriores
  /// es no-op.
  static Future<void> requestPermissionAtStartup() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  /// Estado real: "granted" | "permanent" (denegado, solo Ajustes) | "possible".
  static Future<String> notificationStatus() async {
    try {
      final s = await _channel.invokeMethod<String>('notificationStatus');
      return s ?? 'possible';
    } catch (_) {
      return 'possible';
    }
  }

  /// Abre los ajustes de notificaciones de la app en Android. Útil cuando el
  /// permiso fue denegado de forma permanente y solo queda reactivarlo desde
  /// el sistema ("Don't allow" ya no permite re-prompt de la app).
  static Future<void> openAppNotificationSettings() async {
    try {
      await _channel.invokeMethod('openAppNotificationSettings');
    } catch (_) {}
  }

  /// true si la app ya está exenta de la optimización de batería (Doze).
  static Future<bool> isBatteryOptimizationIgnored() async {
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Pide al usuario eximir a AniMaple de la optimización de batería. Abre el
  /// diálogo del sistema (ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS). Clave
  /// para que el worker de capítulos corra también con el teléfono en reposo
  /// (Doze), sin depender de Firebase ni de ningún backend.
  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (_) {}
  }

  /// Agenda (una sola vez) la revisión de nuevos capítulos. Registra el
  /// respaldo periódico de 15 min (idempotente, ExistingPeriodicWorkPolicy.
  /// KEEP); la cadencia real de 8 min la mantiene el worker al reagendarse.
  static Future<void> scheduleEpisodeCheck() async {
    try {
      await _channel.invokeMethod('scheduleEpisodeCheck');
    } catch (_) {}
  }

  /// Re-escribe el espejo de seguidos en nativo. Se llama tras cualquier
  /// cambio de la lista de seguidos (follow/unfollow/merge desde la nube).
  ///
  /// Estructura: {slug: {"title": ..., "followedAt": ...}}. El Worker usa
  /// followedAt para no notificar capítulos anteriores al momento de seguir:
  /// si sigues un anime que ya lleva 200 capítulos no llega ninguna
  /// notificación, solo los que estrenen después.
  static Future<void> updateFollowedMirror() async {
    try {
      final followed = await ApiService.fetchFollowed();
      final mirror = <String, dynamic>{
        for (final FollowedAnime f in followed)
          f.animeSlug: {
            'title': f.animeTitle,
            'followedAt': f.followedAt,
          },
      };
      await _channel.invokeMethod('updateFollowedMirror', {
        'json': jsonEncode(mirror),
      });
    } catch (_) {}
  }

  /// Punto de entrada: permiso + agendado + primer espejo. Se invoca al
  /// arrancar la app, tras el primer frame (contexto de Activity listo).
  static Future<void> init() async {
    if (_mirrorRegistered) return;
    _mirrorRegistered = true;
    await requestPermissionAtStartup();
    await scheduleEpisodeCheck();
    await updateFollowedMirror();
  }
}
