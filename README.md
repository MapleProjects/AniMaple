# AniMaple

Cliente de código abierto para streaming, seguimiento y descarga de anime. Diseñado para ofrecer una experiencia rápida, fluida y sin publicidad invasiva en Android, Android TV, Linux y Windows.

---

## Características principales

### Reproducción avanzada
- Selector dinámico de servidores y fuentes de video.
- Resolución automática y soporte para transmisiones HLS nativas.
- Superresolución en tiempo real con shaders AMD FidelityFX Super Resolution (FSR 1.0 EASU y RCAS) para escalado de alta fidelidad.
- Ajustes de velocidad, aspecto de pantalla y salto inteligente de intros.
- Modo Picture-in-Picture en dispositivos móviles.
- Integración con MediaSession del sistema operativo para controles multimedia en barra de notificaciones y pantalla de bloqueo.

### Experiencia multidispositivo
- Interfaz adaptativa optimizada para pantallas táctiles, escritorio y control remoto.
- Compatibilidad nativa con Android TV mediante navegación completa por D-Pad.
- Atajos de teclado en Windows y Linux.

### Sincronización en la nube privada
- Modelo sin servidor central (Serverless).
- Sincronización de historial, lista de seguidos y favoritos a través de Google Drive personal del usuario.
- Resolución de conflictos basada en marcas de tiempo para consistencia entre múltiples terminales.

### Descargas fuera de línea
- Descarga segmentada concurrente de flujos HLS.
- Ensamble automático de paquetes de video en almacenamiento local.
- Notificaciones de progreso en segundo plano mediante servicios foreground nativos en Android.

### Notificaciones de episodios nuevos
- Verificación periódica en segundo plano mediante Android WorkManager y AlarmManager.
- Notificaciones locales directas cuando se publica un nuevo capítulo de una serie seguida.

---

## Arquitectura técnica

La aplicación está construida sobre Flutter y complementada con canales nativos de alto rendimiento.

- **Lenguaje principal** Dart 3.10+
- **Framework UI** Flutter
- **Motor de video** media_kit con backend libmpv
- **Servicios nativos Android** Kotlin (Foreground Services, WorkManager, MediaSessionCompat, Picture-in-Picture)
- **Persistencia local** SharedPreferences y caché de disco

---

## Requisitos de compilación

Antes de compilar el proyecto es necesario contar con el siguiente entorno configurado.

- Flutter SDK 3.10 o superior
- Android SDK 34 y NDK configurado
- Java Development Kit (JDK) 17
- Git

---

## Configuración y credenciales

AniMaple utiliza autenticación OAuth2 de Google Drive para la sincronización privada. Por motivos de seguridad, las credenciales no forman parte del repositorio público.

Cree un archivo denominado `secrets.env` en la raíz del proyecto con la siguiente estructura.

```env
GOOGLE_DRIVE_CLIENT_ID=su_client_id_aqui
GOOGLE_DRIVE_CLIENT_SECRET=su_client_secret_aqui
```

El script de compilación inyecta estas variables de entorno en el paquete final durante el proceso de empaquetado.

---

## Instrucciones de compilación

### Compilar APK para Android

Para generar el paquete de distribución optimizado para Android ejecute los comandos siguientes.

```bash
flutter pub get
flutter build apk --release
```

El binario compilado se generará en la ruta indicada a continuación.
`build/app/outputs/flutter-apk/app-release.apk`

### Compilar para escritorio

#### Linux
```bash
flutter pub get
flutter build linux --release
```

#### Windows
```bash
flutter pub get
flutter build windows --release
```

---

## Estructura del repositorio

```text
AniMaple/
├── android/               Código nativo para Android y Android TV
├── assets/                Recursos estáticos, iconos y shaders FSR
├── lib/
│   ├── models/            Estructuras de datos y modelos del dominio
│   ├── pages/             Vistas principales de la aplicación
│   ├── services/          Lógica de red, descargas, sincronización y video
│   ├── utils/             Utilidades auxiliares y constantes
│   ├── widgets/           Componentes visuales reutilizables
│   └── main.dart          Punto de entrada de la aplicación
├── tools/                 Scripts de compilación y automatización
├── pubspec.yaml           Configuración de dependencias de Flutter
└── README.md              Documentación técnica del proyecto
```

---

## Contribuciones

Para proponer mejoras o correcciones al proyecto siga los siguientes pasos.

1. Realice una bifurcación (fork) del repositorio.
2. Cree una rama específica para su característica o corrección (`git checkout -b feature/nueva-mejora`).
3. Verifique la calidad de código con `flutter analyze`.
4. Envíe una solicitud de extracción (pull request) con una descripción técnica clara de los cambios.

---

## Aviso legal y descargo de responsabilidad

AniMaple es un proyecto desarrollado con fines estrictamente educativos y de investigación sobre el desarrollo de clientes multimedia y shaders en Flutter. La aplicación no aloja, almacena ni distribuye ningún contenido multimedia en servidores propios. Todos los enlaces y metadatos son obtenidos de fuentes públicas en la red.

---

## Licencia

Distribuido bajo la Licencia MIT. Consulte el archivo `LICENSE` para obtener más información.
