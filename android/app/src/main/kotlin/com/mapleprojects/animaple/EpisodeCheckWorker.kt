package com.mapleprojects.animaple

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Worker periódico (WorkManager) que revisa si algún anime seguido estrenó
 * un capítulo nuevo y lo notifica. Corre aunque la app esté cerrada y se
 * reprograma automáticamente tras un reinicio (contrato de androidx.work).
 * Sin seguidos o sin red → no consume recursos.
 */
class EpisodeCheckWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "AniMaple"
        // Mismo nombre de prefs del plugin shared_preferences (backend legacy).
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        // Clave espejo JSON {slug: titulo} mantenida por Dart (NotifService).
        const val KEY_FOLLOWED_JSON = "notif_followed_json"
        private const val KEY_LAST_NOTIFIED = "notif_last_notified"
        const val CHANNEL_NEW_EP = "animaple_new_episodes"
        private const val BASE = "https://animeav1.com"
        private const val UA =
            "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
        // Prefs privadas del worker para estado de notificación.
        private const val PREFS_NOTIF = "animaple_notif"
    }

    override suspend fun doWork(): Result {
        return try {
            val ctx = applicationContext
            val prefs = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val followedJson = prefs.getString(KEY_FOLLOWED_JSON, null)
            if (followedJson.isNullOrEmpty() || followedJson == "{}") {
                Log.d(TAG, "EpisodeCheck: sin seguidos, skip")
                return Result.success()
            }
            val followed = JSONObject(followedJson)
            if (followed.length() == 0) return Result.success()

            val recent = fetchRecentEpisodes()
            if (recent.isEmpty()) return Result.success()

            val selPrefs = ctx.getSharedPreferences(PREFS_NOTIF, Context.MODE_PRIVATE)
            val lastNotifiedRaw = selPrefs.getString(KEY_LAST_NOTIFIED, "{}")
            val lastNotified = JSONObject(lastNotifiedRaw ?: "{}")

            val pending = LinkedHashMap<String, RecentEp>()
            for (ep in recent) {
                if (followed.has(ep.slug)) {
                    val known = lastNotified.optInt(ep.slug, 0)
                    if (ep.number > known) {
                        val existing = pending[ep.slug]
                        if (existing == null || ep.number > existing.number) {
                            pending[ep.slug] = ep
                        }
                    }
                }
            }

            if (pending.isEmpty()) {
                Log.d(TAG, "EpisodeCheck: sin novedades")
                return Result.success()
            }

            var notified = 0
            for ((slug, ep) in pending) {
                val title = followed.optString(slug, ep.title)
                Notifier.notifyNewEpisode(ctx, title, ep.number, slug)
                lastNotified.put(slug, ep.number)
                notified++
                Log.d(TAG, "EpisodeCheck: notificado $slug ep ${ep.number}")
            }
            selPrefs.edit().putString(KEY_LAST_NOTIFIED, lastNotified.toString()).apply()
            Log.d(TAG, "EpisodeCheck: $notified notificación(es)")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "EpisodeCheck error: ${e.message}")
            Result.retry()
        }
    }

    private data class RecentEp(
        val slug: String,
        val title: String,
        val number: Int,
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
            out.add(RecentEp(slug, title, number))
        }
        return out
    }

    // ── Resolutores devalue (espejo de api_service.dart) ──

    /** Convierte a int un valor que puede ser double/int/string. */
    private fun optInt(v: Any?): Int {
        return when (v) {
            is Number -> v.toInt()
            is String -> v.toIntOrNull() ?: 0
            else -> 0
        }
    }

    /**
     * Resuelve cadena de índices: media['slug'] puede ser 12 → data[12] = "algo"
     * o 12 → data[12] = 45 → data[45] = "algo" (espejo de _resolveVal).
     */
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
}
