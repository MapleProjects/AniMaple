/// Configuración de Google Sign-In / Drive para AniMaple.
///
/// OAuth Client IDs del proyecto "animaple" en Google Cloud Console.
/// Proyecto en producción, scope único drive.appdata (non-sensitive).
class GDriveConfig {
  GDriveConfig._();

  /// Client ID tipo Android (package com.mapleprojects.animaple + SHA-1 debug).
  static const String androidClientId =
      '514889389663-3ub4munmduvi1v8p9stj6er8v7v2th9c.apps.googleusercontent.com';

  /// Client ID tipo Web application — lo exige google_sign_in en Android
  /// cuando NO se usa google-services.json (refresh token server-side).
  static const String webServerClientId =
      '514889389663-srsa20r4lrn55u6q2npu4o0rs8lfcs7t.apps.googleusercontent.com';
}
