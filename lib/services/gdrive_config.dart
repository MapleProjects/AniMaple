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



      ]);

  /// Client ID tipo TV (Limited Input Devices) para Device Authorization Grant (RFC 8628).
  static String get tvClientId => String.fromCharCodes(const [
        53, 49, 52, 56, 56, 57, 51, 56, 57, 54, 54, 51, 45, 107, 118, 106, 50,
        48, 113, 110, 108, 107, 109, 111, 108, 100, 104, 49, 113, 98, 113, 108,
        104, 50, 118, 52, 51, 56, 53, 54, 108, 106, 57, 54, 108, 46, 97, 112,
        112, 115, 46, 103, 111, 111, 103, 108, 101, 117, 115, 101, 114, 99,
        111, 110, 116, 101, 110, 116, 46, 99, 111, 109,
      ]);

  /// Client Secret tipo TV (Limited Input Devices).
  static String get tvClientSecret => String.fromCharCodes(const [



      ]);
}

