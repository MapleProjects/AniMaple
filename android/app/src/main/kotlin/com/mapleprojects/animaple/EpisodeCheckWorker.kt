package com.mapleprojects.animaple

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Worker periódico (WorkManager) que revisa si algún anime seguido estrenó
 * un capítulo nuevo y lo notifica. Corre aunque la app esté cerrada y se
 * reprograma automáticamente tras un reinicio (contrato de androidx.work).
 *
 * OPTIMIZACIÓN (mínimo procesamiento):
 * - Un solo GET al recientes del sitio (~20 episodios). NO se itera la lista
 *   de seguidos (900 animes no multiplican el trabajo): el coste es
 *   O(recientes), y cada lookup es O(1) sobre el mapa.
 * - Filtro temporal: solo notifica si createdAt(episodio) > followedAt(anime).
 *   Seguir un anime viejo no dispara nada; solo cuentan estrenos posteriores.
 * - Anime finalizado = jamás aparece en recientes → cero procesamiento.
 * - Sin límite de avisos por ciclo: notifica TODOS los estrenos nuevos de la
 *   ventana (10 min). El control anti-duplicado es por número de capítulo
 *   en lastNotified, no por tope de cantidad.
 * - Revisión cada 10 min mediante one-off auto-reagendada (el WorkManager
 *   periódico tiene mínimo 15 min y no alcanza este intervalo).
 * - Sin seguidos o sin red → no consume recursos.
 */
class EpisodeCheckWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "AniMaple"
        // Mismo nombre de prefs del plugin shared_preferences (backend legacy).
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        // Clave espejo JSON {slug: {title, followedAt}} mantenida por Dart.
        const val KEY_FOLLOWED_JSON = "notif_followed_json"
        private const val KEY_LAST_NOTIFIED = "notif_last_notified"
        private const val BASE = "https://animeav1.com"
        private const val UA =
            "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
        // Prefs privadas del worker para estado de notificación.
        private const val PREFS_NOTIF = "animaple_notif"
        // Cadencia efectiva: revisión cada 8 min vía one-off auto-reagendada.
        private const val CHECK_EVERY_MIN = 8L
        // Respaldo administrado por el sistema (sobrevive reinicios). Mínimo
        // permitido por PeriodicWorkRequest = 15 min; no va más abajo.
        private const val PERIODIC_MIN = 15L
        // Nombre de la cadena one-off LEGACY (previo a v1.2.9): se cancela al
        // migrar para que no queden dos mecanismos compitiendo.
        private const val WORK_LEGACY = "animaple_episode_check"
        // Trabajo periódico administrado por el sistema (sobrevive reinicio).
        private const val WORK_NAME = "animaple_episode_check_periodic"
        // Revisión de 8 min (auto-reagendada) y revisión inmediata (boot).
        private const val WORK_NOW = "animaple_episode_check_now"

        /**
         * Agenda la revisión periódica de capítulos como RED DE SEGURIDAD.
         * PeriodicWorkRequest es persistente: WorkManager lo reagenda SOLO
         * tras reinicios del dispositivo (contrato + RECEIVE_BOOT_COMPLETED),
         * de modo que aunque la cadena de 8 min fallara, el ciclo continúa.
         * KEEP no duplica.
         */
        fun enqueuePeriodic(ctx: Context) {
            try {
                // Migración: matar la cadena one-off antigua (v1.2.2-v1.2.8).
                WorkManager.getInstance(ctx).cancelUniqueWork(WORK_LEGACY)
                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
                val request = PeriodicWorkRequestBuilder<EpisodeCheckWorker>(
                    PERIODIC_MIN, TimeUnit.MINUTES
                )
                    .setConstraints(constraints)
                    .build()
                WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
                    WORK_NAME,
                    ExistingPeriodicWorkPolicy.KEEP,
                    request,
                )
                Log.d(TAG, "EpisodeCheck: respaldo periódico cada $PERIODIC_MIN min (KEEP)")
            } catch (e: Exception) {
                Log.e(TAG, "EpisodeCheck enqueuePeriodic error: ${e.message}")
            }
        }

        /**
         * Agenda la siguiente revisión en [delayMinutes]. La cadena principal
         * es esta: one-off de ~8 min auto-reagendado (el worker se re-encola
         * al terminar). WorkManager la persiste y la re-encola tras reinicios.
         */
        fun enqueueDelayed(ctx: Context, delayMinutes: Long) {
            try {
                val constraints = Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
                val request = OneTimeWorkRequestBuilder<EpisodeCheckWorker>()
                    .setConstraints(constraints)
                    .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                    .build()
                WorkManager.getInstance(ctx).enqueueUniqueWork(
                    WORK_NOW,
                    ExistingWorkPolicy.REPLACE,
                    request,
                )
                Log.d(TAG, "EpisodeCheck: próxima revisión en $delayMinutes min")
            } catch (e: Exception) {
                Log.e(TAG, "EpisodeCheck enqueueDelayed error: ${e.message}")
            }
        }

        /** Revisión inmediata. La usa BootReceiver tras un reinicio. */
        fun enqueueImmediate(ctx: Context) = enqueueDelayed(ctx, 0L)

        /** Detiene todos los ciclos (al vaciarse la lista de seguidos). */
        fun cancel(ctx: Context) {
            try {
                val wm = WorkManager.getInstance(ctx)
                wm.cancelUniqueWork(WORK_NAME)
                wm.cancelUniqueWork(WORK_NOW)
                wm.cancelUniqueWork(WORK_LEGACY)
                Log.d(TAG, "EpisodeCheck cancelado (sin seguidos)")
            } catch (e: Exception) {
                Log.e(TAG, "EpisodeCheck cancel error: ${e.message}")
            }
        }
    }

    override suspend fun doWork(): Result {
        val ctx = applicationContext
        try {
            val prefs = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val followedJson = prefs.getString(KEY_FOLLOWED_JSON, null)
            if (followedJson.isNullOrEmpty() || followedJson == "{}") {
                Log.d(TAG, "EpisodeCheck: sin seguidos, skip")
                return Result.success()
            }
            val followed = JSONObject(followedJson)
            if (followed.length() == 0) return Result.success()

            val recent = fetchRecentEpisodes()
            if (recent.isNotEmpty()) {
                val selPrefs = ctx.getSharedPreferences(PREFS_NOTIF, Context.MODE_PRIVATE)
                val lastNotifiedRaw = selPrefs.getString(KEY_LAST_NOTIFIED, "{}")
                val lastNotified = JSONObject(lastNotifiedRaw ?: "{}")

                // Sin límite: pendientes por anime (máx 1; se queda el más reciente).
                val pending = LinkedHashMap<String, RecentEp>()
                for (ep in recent) {
                    if (!followed.has(ep.slug)) continue
                    val entry = followed.optJSONObject(ep.slug) ?: continue
                    val followedAt = tsMillis(entry.optString("followedAt", ""))
                    // Capítulo anterior al momento de seguir → ignorar.
                    if (followedAt > 0 && ep.createdMs <= followedAt) continue
                    val known = lastNotified.optInt(ep.slug, 0)
                    if (ep.number > known) {
                        val existing = pending[ep.slug]
                        if (existing == null || ep.number > existing.number) {
                            pending[ep.slug] = ep
                        }
                    }
                }

                if (pending.isNotEmpty()) {
                    var notified = 0
                    for ((slug, ep) in pending) {
                        val entry = followed.optJSONObject(slug)
                        val title = entry?.optString("title", ep.title) ?: ep.title
                        Notifier.notifyNewEpisode(ctx, title, ep.number, slug, ep.animeId)
                        lastNotified.put(slug, ep.number)
                        notified++
                        Log.d(TAG, "EpisodeCheck: notificado $slug ep ${ep.number}")
                    }
                    selPrefs.edit().putString(KEY_LAST_NOTIFIED, lastNotified.toString()).apply()
                    Log.d(TAG, "EpisodeCheck: $notified notificación(es)")
                } else {
                    Log.d(TAG, "EpisodeCheck: sin novedades")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "EpisodeCheck error: ${e.message}")
        }
        // Cadencia principal (~8 min): reagendar la siguiente revisión. Al
        // terminar sin seguidos no se llega aquí (early return arriba), así
        // que la cadena se detiene sola. El periódico de 15 min queda como
        // red de seguridad administrada por el sistema tras reinicios.
        enqueueDelayed(ctx, CHECK_EVERY_MIN)
        return Result.success()
    }

    private data class RecentEp(
        val slug: String,
        val title: String,
        val number: Int,
        val createdMs: Long,
        val animeId: Int,
    )

    private fun fetchRecentEpisodes(): List<RecentEp> {
        val conn = URL("$BASE/__data.json").openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 15000
        conn.readTimeout = 15000
        conn.setRequestProperty("User-Agent", UA)
        conn.setRequestProperty("Accept", "*/*")
        conn.setRequestProperty("Accept-Language", "es-EC,es-419;q=0.9,es;q=0.8")
        conn.setRequestProperty("Accept-Encoding", "identity")
        conn.setRequestProperty("Sec-Fetch-Dest", "empty")
        conn.setRequestProperty("Sec-Fetch-Mode", "cors")
        conn.setRequestProperty("Sec-Fetch-Site", "same-origin")
        conn.setRequestProperty("Referer", "$BASE/")

        val code = conn.responseCode
        if (code !in 200..299) {
            conn.disconnect()
            Log.w(TAG, "EpisodeCheck fetch HTTP $code")
            return emptyList()
        }
        val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
        val raw = reader.use { it.readText() }
        conn.disconnect()

        val resp = JSONObject(raw)
        val nodes = resp.optJSONArray("nodes") ?: return emptyList()
        var main: JSONArray? = null
        for (i in 0 until nodes.length()) {
            val n = nodes.optJSONObject(i) ?: continue
            val d = n.optJSONArray("data")
            if (d != null && (main == null || d.length() > main!!.length())) main = d
        }
        val data = main ?: return emptyList()
        if (data.length() == 0) return emptyList()

        val root = data.optJSONObject(0) ?: return emptyList()
        val leIdx = optInt(root.opt("latestEpisodes"))
        if (leIdx < 0 || leIdx >= data.length()) return emptyList()
        val epIndices = data.optJSONArray(leIdx) ?: return emptyList()

        val out = ArrayList<RecentEp>()
        for (j in 0 until epIndices.length()) {
            val idx = optInt(epIndices.opt(j))
            if (idx < 0 || idx >= data.length()) continue
            val rawEp = data.optJSONObject(idx) ?: continue
            val number = resolveIndexedInt(data, rawEp, "number")
            if (number <= 0) continue
            val mediaIdx = optInt(rawEp.opt("media"))
            if (mediaIdx < 0 || mediaIdx >= data.length()) continue
            val rawMedia = data.optJSONObject(mediaIdx) ?: continue
            val slug = resolveStr(data, rawMedia, "slug")
            val title = resolveStr(data, rawMedia, "title")
            if (slug.isEmpty() || title.isEmpty()) continue
            val created = resolveStr(data, rawEp, "createdAt")
            val createdMs = tsMillis(created)
            val animeId = resolveIndexedInt(data, rawMedia, "id")
            out.add(RecentEp(slug, title, number, createdMs, animeId))
        }
        return out
    }

    // ── Resolutores devalue (espejo de api_service.dart) ──

    private fun optInt(v: Any?): Int {
        return when (v) {
            is Number -> v.toInt()
            is String -> v.toIntOrNull() ?: 0
            else -> 0
        }
    }

    /**
     * Resolución devalue de 1 salto para campos numéricos que son ÍNDICES
     * hacia el valor real (number, id). Espejo de _resolveVal del Dart.
     *
     * CRÍTICO: en __data.json de SvelteKit el valor crudo de "number" no es
     * el número de episodio, es un índice dentro de `data` (p. ej. `166` →
     * data[166] = `5`). Leer el índice crudo producía avisos "Episodio 184"
     * cuando el episodio real era el 5. Un solo salto resuelve el valor real.
     */
    private fun resolveIndexedInt(data: JSONArray, obj: JSONObject, key: String): Int {
        val v = obj.opt(key) ?: return 0
        if (v is String) return v.toIntOrNull() ?: 0
        if (v !is Number) return 0
        val idx = v.toInt()
        if (idx !in 0 until data.length()) return 0
        val inner = data.opt(idx)
        return when (inner) {
            is Number -> inner.toInt()
            is String -> inner.toIntOrNull() ?: 0
            else -> 0
        }
    }

    /** Resuelve cadena de índices (espejo de _resolveVal). */
    private fun resolveStr(data: JSONArray, obj: JSONObject, key: String): String {
        var v = obj.opt(key)
        var guard = 6
        while (guard-- > 0) {
            if (v is String) return v
            if (v is Number) {
                val idx = v.toInt()
                if (idx in 0 until data.length()) {
                    v = data.opt(idx)
                    continue
                }
                return ""
            }
            return ""
        }
        return ""
    }

    /** "2026-08-02 20:15:17.307125+00" | "2026-08-02T15:00:00.000Z" → epoch ms (UTC). */
    private fun tsMillis(s: String): Long {
        if (s.isEmpty()) return 0L
        return try {
            val clean = s.trim().replace('T', ' ')
            val end = clean.indexOf('.')
            val datePart = if (end > 0) clean.substring(0, end) else clean
            // formato esperado: yyyy-MM-dd HH:mm[:ss]
            val fmt = if (datePart.length > 16)
                SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            else
                SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            fmt.parse(datePart).time
        } catch (e: Exception) {
            Log.w(TAG, "tsMillis parse falló: '$s'")
            0L
        }
    }
}
