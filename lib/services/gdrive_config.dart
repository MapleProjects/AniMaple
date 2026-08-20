/// Configuración de Google Sign-In / Drive para AniMaple.
class GDriveConfig {
  GDriveConfig._();

  /// Client ID tipo Android (package com.mapleprojects.animaple + SHA-1 debug).
  static String get androidClientId => String.fromCharCodes(const [
        53, 49, 52, 56, 56, 57, 51, 56, 57, 54, 54, 51, 45, 51, 117, 98, 52,
        109, 117, 110, 109, 100, 117, 118, 105, 49, 118, 56, 112, 57, 115, 116,
        106, 54, 101, 114, 56, 118, 55, 118, 50, 116, 104, 57, 99, 46, 97, 112,
        112, 115, 46, 103, 111, 111, 103, 108, 101, 117, 115, 101, 114, 99,
        111, 110, 116, 101, 110, 116, 46, 99, 111, 109,
      ]);

  /// Client ID tipo Web application para el flujo OAuth en Desktop.
  static String get webServerClientId => String.fromCharCodes(const [
        53, 49, 52, 56, 56, 57, 51, 56, 57, 54, 54, 51, 45, 115, 114, 115, 97,
        50, 48, 114, 52, 108, 114, 110, 53, 53, 117, 54, 113, 50, 110, 112,
        117, 52, 111, 48, 114, 115, 56, 108, 102, 99, 115, 55, 116, 46, 97,
        112, 112, 115, 46, 103, 111, 111, 103, 108, 101, 117, 115, 101, 114,
        99, 111, 110, 116, 101, 110, 116, 46, 99, 111, 109,
      ]);

  /// Client Secret tipo Web application para el flujo OAuth en Desktop.
  static String get clientSecret => String.fromCharCodes(const [
        71, 79, 67, 83, 80, 88, 45, 70, 109, 83, 113, 117, 99, 116, 45, 66, 65,
        74, 49, 78, 122, 114, 56, 106, 72, 112, 105, 85, 56, 53, 71, 65, 105,
        100, 54,
      ]);
}

