# AniMaple — Sincronización con Google Drive (BYO cloud)

Historial, favoritos y notificaciones se sincronizan entre dispositivos usando
**la cuenta de Drive del propio usuario**. Cero hosting propio: cada usuario
usa su propia nube.

## Arquitectura

- Login: Google Sign-In (scope `drive.appdata`, **non-sensitive**)
- Datos: archivo `animaple_sync.json` en el `appDataFolder` de Drive
  (carpeta privada de la app, invisible para el usuario, solo accesible por la app)
- Sync: pull al abrir + push con debounce 2s tras cada cambio
- Merge: last-write-wins por registro usando el timestamp de cada entrada

## Por qué no hay verificación OAuth ni "testers"

`drive.appdata` es un scope **non-sensitive**. Según la doc de Google, las apps
que solo usan scopes non-sensitive **no están obligadas** a pasar la
verificación de OAuth. Eso implica:

- No aparece la pantalla "unverified app"
- No hay límite de 100 usuarios
- No hay que agregar test users uno por uno
- Tampoco vence el refresh token a los 7 días (eso aplica solo en estado Testing)

El único detalle: el OAuth consent screen debe estar en **In production**
(un click en consola) para que la restricción de testers desapareza.

## Datos para registrar

| Dato | Valor |
|---|---|
| Package name (Android) | `com.mapleprojects.animaple` |
| SHA-1 (debug keystore actual) | `7C:26:20:9C:22:A8:62:A1:80:11:07:AC:F8:46:34:61:96:15:54:6B` |
| SHA-1 (release, si creas keystore release) | remplazar en la consola |

> ⚠️ La app hoy firma release con el **debug keystore**. Cuando hagas un
> keystore release propio, hay que registrar su SHA-1 en la consola y cambiar
> `signingConfig`.

## Pasos en Google Cloud Console (una vez, ~10 min)

1. Ir a https://console.cloud.google.com → crear proyecto nuevo (ej: `animaple`)
2. Activar **Google Drive API**:
   `APIs & Services` → `Library` → buscar "Google Drive API" → `Enable`
3. Configurar la pantalla de consentimiento:
   - `APIs & Services` → `OAuth consent screen`
   - User type: **External**
   - App name: `AniMaple`, support email (tuyo)
   - Scopes: **Añadir** → `https://www.googleapis.com/auth/drive.appdata`
   - Test users: puedes dejar 1 (tú mismo) durante el desarrollo
   - **Publicar la app → In production** (esto quita el límite de testers)
4. Crear los OAuth Client IDs en `Credentials` → `Create Credentials` → `OAuth client ID`:
   - **Android**: package `com.mapleprojects.animaple` + SHA-1 de arriba
     → copiar el "Client ID" (termina en `.apps.googleusercontent.com`) a
     `lib/services/gdrive_config.dart` → `androidClientId`
   - **Web application**: crearlo y copiar su Client ID a
     `lib/services/gdrive_config.dart` → `webServerClientId`
     (lo requiere google_sign_in en Android sin google-services.json)

## Archivos involucrados

- `lib/services/sync_service.dart` — Sync completo (login, pull, push, merge)
- `lib/services/gdrive_config.dart` — **pega aquí los Client IDs**
- `lib/services/api_service.dart` — hooks de notificación en cada mutación
- `lib/widgets/sync_button.dart` — botón de nube en el AppBar (home)
- `lib/main.dart` — restore de sesión + pull al arrancar

## Probar

- En el emulador/móvil con tu cuenta: toca el icono de nube arriba
- Al autorizar, se crea el archivo en tu Drive (oculto)
- Segunda instalación (otro dispositivo) con el mismo login → mismo historial

## Notas

- `drive.appdata` tiene cuota 512MB por app → de sobra para un JSON.
- El archivo NO es visible en la interfaz de Drive del usuario (carpeta oculta).
- Si el usuario cierra sesión, los datos quedan solo en su dispositivo hasta
  que vuelva a iniciar sesión en cualquier dispositivo.
