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
  /// En Android 13+ abre el diálogo del sistema; en versiones anteriores es no-op.
  static Future<void> requestPermissionAtStartup() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  /// Agenda (una sola vez) la revisión periódica de nuevos capítulos.
  /// Idempotente nativamente (ExistingPeriodicWorkPolicy.KEEP).
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
