# AniMaple — Registro de cambios

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
