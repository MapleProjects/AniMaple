# AniMaple — Registro de cambios

## v2.0.9

### Novedades y mejoras
- Limpieza y saneamiento general de código fuente y documentación técnica.
- Optimización de comentarios internos y simplificación de estructuras descriptivas.
- Actualización de documentación de arquitectura abierta para la comunidad.

## v2.0.8

### Novedades y mejoras
- Eliminación de la línea verde en la base del reproductor para Android TV mediante recorte dinámico de macrobloques YUV.
- Detección y sondeo en tiempo real de flujos HLS con cabeceras de origen y contexto WAF.
- Encabezado de días de emisión con distribución horizontal uniforme y navegación adaptada para control remoto en televisores y pantallas anchas.

## v2.0.7

### Novedades y mejoras
- Optimización integral del motor de streaming para UPNShare, Voe, MP4Upload y Byse con prefetching predictivo en bucle invertido y reutilización de conexiones TLS persistentes.
- Motor de aceleración concurrente por rebanadas de 2 MB para flujos MP4 directos superando los límites de ancho de banda por socket en servidores como MP4Upload.
- Medición precisa de caudal y latencia multimedia descargando fragmentos binarios reales en lugar de manifiestos en caché.
- Selección inteligente de servidores con umbrales mínimos de viabilidad por resolución para evitar almacenamiento en búfer.
- Elevación administrativa garantizada mediante ShellExecute RunAs al actualizar desde la aplicación en Windows para evitar fallos de permisos UAC al ejecutar el instalador.
- Corrección de caracteres especiales, estrellas (★, ☆), acentos y emojis en historial y favoritos mediante decodificación UTF-8 rigurosa y normalización CP1252.
- Resolución de sincronización en eliminación de historial: asignación de tombstones consistentes para evitar la reaparición de capítulos ante discrepancias horarias entre dispositivos.
- Tolerancia multicadena de redirecciones en el resolutor de Voe y sondeo en memoria sin bloqueo para Byse.

## v2.0.6

### Novedades y mejoras
- Corrección de la verificación de versión en Windows: detección precisa a partir del binario compilado para asegurar notificaciones fiables de nuevas actualizaciones.
- Recompilación nativa completa del instalador de Windows garantizando el reemplazo efectivo de todos los archivos y ejecutables.
- Sincronización automática de Google Drive en Windows y Linux con validación de permisos completos de lectura y escritura.
- Detección reactiva de sesiones heredadas con ámbitos insuficientes y flujo guiado de renovación.
- Sincronización inmediata al conectar la cuenta y nueva opción de sincronización manual en el menú de perfil.

## v2.0.5

### Novedades y mejoras
- Corrección de la superposición visual en el diálogo de inicio de sesión de Google en televisores y Android TV.
- Optimización del código QR con apertura directa del portal de verificación y código prellenado.
- Sincronización completa y bidireccional en la nube de Google Drive compartida entre Android TV, escritorio y móviles.
- Migración automática de datos existentes al almacenamiento compartido de Google Drive.
- Distribución vertical equilibrada y adaptable de la barra de navegación lateral para pantallas panorámicas y televisores.
- Resaltado de foco de alto contraste para navegación fluida con control remoto en televisores.

## v2.0.4

### Novedades y mejoras
- Código QR interactivo en el inicio de sesión para Android TV: escanea con la cámara del celular para abrir directamente la confirmación de Google con el código ya insertado.
- Corrección del estado de cuenta y avatar en Android TV tras completar la vinculación con Google Drive.
- Cierre automático y reactivo del diálogo de vinculación una vez otorgada la autorización.
- Persistencia de sesión y restauración inmediata en TV sin depender de Google Play Services.

## v2.0.3

### Novedades y mejoras
- Autenticación Google para Android TV mediante flujo de dispositivos (Google Device Authorization Grant RFC 8628). Vinculación con código en pantalla sin salir de la app ni requerir navegador web en el televisor.
- Sincronización en la nube con Google Drive compatible con ámbitos restringidos y dispositivos de entrada limitada.
- Optimización de retención de memoria y mitigación del cierre por Low Memory Killer en televisores con recursos reducidos.
- Análisis de código estático y depuración de canales nativos para máxima estabilidad.

## v2.0.2

### Novedades y mejoras
- Optimización y estabilidad en la sincronización de cuenta y copia de seguridad en la nube para televisores y dispositivos Android TV.
- Mejoras en la barra de reproducción y navegación fluida con control remoto.
- Cierre optimizado y seguro en Windows durante el proceso de actualización automática.
- Actualización del canal de releases y verificador automático para todas las plataformas.

## v2.0.1

### Novedades y mejoras
- Soporte para televisores y dispositivos Android TV con navegación fluida mediante control remoto y selección de elementos optimizada.
- Almacenamiento dinámico de reproducción en caché para precarga eficiente sin saturar la memoria del dispositivo.
- Limpieza automática de archivos temporales al cambiar o finalizar episodios para evitar residuos en el almacenamiento.
- Mayor estabilidad y rendimiento general en conexiones lentas mediante reconexión inteligente continua.
- Corrección de anomalías visuales en la zona inferior de la pantalla durante episodios extensos.
- Selección automática de la máxima resolución disponible en transmisiones con múltiples calidades.

## v2.0.0

### Novedades y mejoras
- Incorporación de Image Reconstruction, un sistema que limpia imperfecciones de transmisión, suaviza los degradados de color y realza los trazos del dibujo para que la animación se aprecie más nítida y definida.
- Implementación de estado visual para la verificación y selección de servidores.
- Descarga acelerada multiconexión para servidores de video que optimiza la velocidad y previene pausas durante la reproducción.
- Mayor memoria previa en el reproductor para asegurar una reproducción continua y estable.
- Soporte para nuevos servidores de transmisión.

## v1.2.10 (20 ago 2026)

### Novedades y mejoras
- **Favoritos visibles en Inicio y Horario**: los animes agregados a favoritos ahora muestran el distintivo de corazón rojo en las tarjetas de Inicio y en la cuadrícula de Horario de emisión en tiempo real.
- **Acceso dinámico e inteligente en Inicio**: al tocar un anime que esté en tus favoritos, la app te lleva directamente al capítulo en emisión actual. Si no está en favoritos, abre la vista detallada con la descripción y todos los capítulos como de costumbre.
- **Corrección de reproducción en Windows (`SourceNotSupported`)**: integración de proxy local HLS/MP4 con inyección de User-Agent y Referer, permitiendo la reproducción fluida de streams HLS y servidores de video en Windows.
- **Autoactualización en Windows**: soporte completo para detectar nuevas versiones desde GitHub Releases, descargar el instalador en segundo plano con barra de progreso y actualizar la app automáticamente.
- **Google Sign-In para Windows**: soporte completo del inicio de sesión con Google en Windows vía flujo OAuth 2.0 PKCE + loopback.

## v1.2.8 (03 ago 2026)

### Correcciones

- **Reproducción automática al reconectar**: al recuperar la conexión, el
  capítulo se reanuda reproduciéndose solo, sin que tengas que tocar la
  pantalla, y continúa donde se cortó.
- **Títulos con tildes corregidos**: los nombres de animes con caracteres
  especiales (tildes, ñ) que podían verse distorsionados en Historial y en
  Mi lista ahora se muestran correctamente. Los títulos guardados se
  reparan automáticamente.

## v1.2.7 (03 ago 2026) — versión revisada (+15)

### Actualización automática (corrección)

- **Notas de la actualización legibles**: el texto con los cambios del release
  se muestra correctamente (encabezados, listas y negritas), ya no aparece
  el código de formato.

## v1.2.7 (03 ago 2026)

### Reproductor (ajuste)

- **Reconexión cada 8 segundos**: el intento de restaurar la reproducción tras
  una pérdida de internet ahora espera 8 segundos entre reintentos, para dar
  al video tiempo de cargar y reproducirse (antes cada segundo nunca llegaba
  a hacerlo).
- **Aviso claro**: al perder la conexión se muestra "Conexión perdida, se
  está restaurando la reproducción".

### Actualización automática (ajuste)

- **Permiso de instalación antes de descargar**: al tocar Actualizar se pide
  primero el permiso de "instalar apps desconocidas" si hace falta, y solo
  después comienza la descarga. Ya no pasa que se descargue el APK, se pida el
  permiso y haya que volver a descargarlo al regresar.

## v1.2.6 (03 ago 2026)

### Reproductor (corrección)

- **Reconexión automática al perder internet**: si la conexión se cae durante
  la reproducción, AniMaple reanuda el video automáticamente. Reintenta cada
  segundo, sin límite, hasta volver a conectar, y muestra un aviso
  "Reconectando…". Ya no se queda en 00:00 ni es necesario recargar.
- **Progreso conservado al reconectar**: al volver la conexión, el capítulo
  continúa exactamente en el segundo donde se cortó.
- **Progreso conservado al cambiar de servidor o idioma**: cambiar entre
  servidores (HLS / MP4Upload) o entre Doblaje y Subtitulado no pierde lo
  visto; el video retoma desde donde iba.

## v1.2.5 (03 ago 2026)

### Actualización automática

- **Aviso de versión nueva al abrir la app**: si hay una release más reciente
  disponible, al iniciar aparece una ventana con dos opciones: **Actualizar**
  (a la derecha) y **Posponer** (a la izquierda).
- **Recordatorio a la vista**: si pospones la actualización, junto al icono
  de tu cuenta aparece un botón que indica que hay una versión pendiente.
  Al tocarlo se vuelve a mostrar la misma ventana.
- **Descarga dentro de la app**: Actualizar descarga el APK desde GitHub
  directamente en AniMaple (sin abrir el navegador), con barra de progreso,
  y pide permiso para instalarse al terminar.
- **Sin archivos basura**: el APK descargado se elimina tras la instalación.

## v1.2.4 (03 ago 2026) — versión revisada (+11)

### Sincronización (corrección)

- **Los cambios locales ya no quedan "olvidados"**: antes, si un borrado o
  una edición del historial/seguidos no se subía a la nube (fallo de red o
  de sesión en ese momento), no se reintentaba hasta que el usuario hiciera
  otro cambio. Ahora un pendiente local se publica automáticamente en cuanto
  se restablece la conexión o la sesión, sin esperar un nuevo evento.
  El borrado de historial se propaga al otro dispositivo en segundos.

## v1.2.4 (03 ago 2026)

### Notificaciones

- **Revisión cada 10 minutos**: los nuevos capítulos se detectan con mayor
  frecuencia. Se usa un trabajo que se reprograma solo (el mínimo del sistema
  para tareas periódicas es 15 min, por eso se agenda manualmente).
- **Sin límite de avisos**: se notifica cada estreno nuevo que aparezca en la
  ventana. Ningún capítulo deja de avisarse; la protección contra repetir es
  por número de capítulo, no por tope de cantidad.

## v1.2.3 (02 ago 2026)

### Notificaciones (optimización)

- **Solo capítulos posteriores a tu seguimiento**: si sigues un anime que ya
  lleva muchos capítulos, no llegan avisos por lo que ya se emitió — solo por
  los que se estrenen después del momento en que lo agregaste a Mi lista.
- **Mínimo uso de recursos**: la revisión procesa únicamente los episodios
  recientes del catálogo (una sola consulta), sin importar cuántos animes
  sigas. Los animes finalizados no se procesan en absoluto.
- **Sin saturación**: como máximo 5 avisos por ciclo; nunca se inunda la
  bandeja de notificaciones.

## v1.2.2 (02 ago 2026)

### Correcciones

- **Borrado por capítulo**: eliminar un capítulo del historial ya no borra
  todo el anime; solo quita ese capítulo y deja el resto intactos.
- **Tildes corregidas**: los títulos con acentos/ñ volvían distorsionados
  (mojibake) porque las respuestas JSON se decodificaban como latin1. Ahora
  se decodifican como UTF-8, los títulos se muestran correctos en todas las
  pantallas y diálogos.

### Notificaciones

- **Permiso al arranque**: la app pide permiso de notificaciones al abrirse
  por primera vez, no al reproducir un capítulo.
- **Nuevos capítulos de tu lista**: al estrenarse un episodio de un anime
  que sigues, llega una notificación. La revisión corre en segundo plano
  (WorkManager) cada 15 min solo si hay red y hay seguidos; resiste cierres
  de la app y reinicios del dispositivo.
- Los controles de reproducción (play/pausa/detener con la barra de progreso)
  siguen en la notificación durante el video.

## v1.2.1 (02 ago 2026)

### Correcciones (sync)

- **Los borrados ya persisten**: eliminar un favorito o un capítulo del
  historial ahora deja un *tombstone*. Antes el merge hacía solo union y el
  remoto "resucitaba" lo eliminado, en el mismo dispositivo o en otros.
- **Orden convergente entre dispositivos**: historial y Mi lista se
  reordenan siempre por timestamp (UTC, normalizado) con desempate por
  id/capítulo. Todos los dispositivos convergen a la misma lista, incluso con
  datos antiguos guardados antes de la normalización.
- **Re-marcar un capítulo ya visto lo reordena, no lo duplica**: el mismo
  capítulo aparece una sola vez y queda primero.
- `_sameEntries` comparaba con `toString()` (sin override) → el merge
  ignoraba reordenamientos por creer "sin cambios". Ahora compara contenido
  y orden reales (historia + seguidos + tombstones).

## v1.2.0 (01 ago 2026)

### Nuevo
- **Sincronización con Google Drive (BYO cloud)**: historial y Mi lista
  sincronizados entre dispositivos usando la cuenta de Drive del propio
  usuario. Cero hosting propio.
- Botón de nube en el AppBar (pantalla de inicio) para iniciar sesión con
  Google y sincronizar manualmente. Sync automático al abrir la app.
- Merge last-write-wins por timestamp: no se pierde ningún cambio reciente.

### Arquitectura (firma)
- **Firma de release estable y coherente con el cliente OAuth de Google**:
  `~/keystores/animaple-release.jks` (SHA-1 `7C:26:20:9C:...`).
- La firma se lee desde `android/key.properties` (no versionado).
- ⚠️ Al pasar de v1.1.1 a v1.2.0 se requiere **reinstalar una sola vez**
  (la v1.1.1 se firmó con otra clave). A partir de v1.2.0 todas las
  actualizaciones mantienen la misma firma; ya no habrá que desinstalar.

## v1.1.1 (20 jul 2026)
- Fix: seek display = tap_count × 10s exactly (not rounded).
