# AniMaple — Registro de cambios

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
