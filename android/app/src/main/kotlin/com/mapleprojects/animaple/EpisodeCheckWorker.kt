package com.mapleprojects.animaple

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
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
        // Intervalo de revisión (WorkManager periódico tiene mínimo 15 min;
        // usamos one-off auto-reagendada para alcanzar 10 min).
        private const val INTERVAL_MIN = 10L
        private const val WORK_NAME = "animaple_episode_check"
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
                        Notifier.notifyNewEpisode(ctx, title, ep.number, slug)
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
        // Siempre reagendar el siguiente ciclo (mientras haya seguidos).
        reschedule(ctx)
        return Result.success()
    }

    /** One-off auto-reagendada cada 10 min. Alcanza intervalos que el
     *  PeriodicWorkRequest de WorkManager no permite (<15 min). */
    private fun reschedule(ctx: Context) {
        try {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = OneTimeWorkRequestBuilder<EpisodeCheckWorker>()
                .setConstraints(constraints)
                .setInitialDelay(INTERVAL_MIN, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(ctx).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request,
            )
            Log.d(TAG, "EpisodeCheck reagendado en $INTERVAL_MIN min")
        } catch (e: Exception) {
            Log.e(TAG, "EpisodeCheck reschedule error: ${e.message}")
        }
    }

    private data class RecentEp(
        val slug: String,
        val title: String,
        val number: Int,
        val createdMs: Long,
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
            val number = optInt(rawEp.opt("number"))
            if (number <= 0) continue
            val mediaIdx = optInt(rawEp.opt("media"))
            if (mediaIdx < 0 || mediaIdx >= data.length()) continue
            val rawMedia = data.optJSONObject(mediaIdx) ?: continue
            val slug = resolveStr(data, rawMedia, "slug")
            val title = resolveStr(data, rawMedia, "title")
            if (slug.isEmpty() || title.isEmpty()) continue
            val created = resolveStr(data, rawEp, "createdAt")
            val createdMs = tsMillis(created)
            out.add(RecentEp(slug, title, number, createdMs))
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
