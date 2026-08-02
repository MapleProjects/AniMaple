/// Configuración de Google Sign-In / Drive para AniMaple.
///
/// Tras crear el proyecto en Google Cloud Console (ver README de sync),
/// pega aquí los OAuth Client IDs que Google te genere:
///
///  - androidClientId: Client ID de tipo "Android" (usa el package
///    com.mapleprojects.animaple + tu SHA-1 de firma).
///  - webServerClientId: Client ID de tipo "Web application". Lo exige
///    google_sign_in en Android cuando NO se usa google-services.json
///    (es el flujo de refresh token server-side).
///
/// Si se dejan vacíos, el plugin intenta leerlos de google-services.json.
class GDriveConfig {
  GDriveConfig._();

  static const String androidClientId = '';
  static const String webServerClientId = '';
}
