package com.mapleprojects.animaple

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import java.net.HttpURLConnection
import java.net.URL

/**
 * Centraliza las notificaciones de "nuevo capítulo". Usa un canal propio
 * distinto del de reproducción para que el usuario pueda gestionarlas por
 * separado (silenciar novedades sin tocar los controles de video).
 */
object Notifier {

    private const val CHANNEL_NEW_EP = "animaple_new_episodes"
    private const val NOTIF_ID_BASE = 2000

    /** Crea el canal de novedades (idempotente). */
    fun ensureNewEpisodeChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_NEW_EP,
                "Nuevos capítulos",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Avisos cuando un anime de Mi lista estrena capítulo"
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }
    }

    /** Notifica el estreno de un capítulo. [slug] abre el episodio si se toca.
     *  [animeId] se usa para cargar la portada (misma imagen de la pestaña
     *  Horario: cdn.animeav1.com/covers/<id>.jpg) como imagen grande. */
    fun notifyNewEpisode(
        ctx: Context,
        title: String,
        episode: Int,
        slug: String,
        animeId: Int,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!nm.areNotificationsEnabled()) return
        }
        ensureNewEpisodeChannel(ctx)

        // Portada del anime (idéntica a las tarjetas del Horario). Scale up
        // moderado para que se vea nítida expandida; si falla, sin imagen.
        val poster = if (animeId > 0) {
            loadBitmap("https://cdn.animeav1.com/covers/$animeId.jpg")
        } else null

        // Tap → abre la app.
        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val contentIntent = PendingIntent.getActivity(
            ctx, slug.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(ctx, CHANNEL_NEW_EP)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("Nuevo capítulo de $title")
            .setContentText("Episodio $episode ya disponible")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)

        if (poster != null) {
            builder.setLargeIcon(poster)
            builder.setStyle(
                NotificationCompat.BigPictureStyle()
                    .bigPicture(poster)
                    .setBigContentTitle("Nuevo capítulo de $title")
                    .setSummaryText("Episodio $episode ya disponible")
            )
        }

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = NOTIF_ID_BASE + (slug.hashCode() and 0x7fffffff) % 10000
        nm.notify(id, builder.build())
    }

    private fun loadBitmap(url: String): Bitmap? {
        var conn: HttpURLConnection? = null
        return try {
            conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 6000
            conn.readTimeout = 6000
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("User-Agent", "AniMaple/1.2")
            if (conn.responseCode !in 200..299) return null
            val bmp = BitmapFactory.decodeStream(conn.inputStream) ?: return null
            scaleUp(bmp)
        } catch (_: Exception) {
            null
        } finally {
            try { conn?.disconnect() } catch (_: Exception) {}
        }
    }

    /** Upscale moderado para que la portada (260px de origen) se vea nítida
     *  al expandirse en la notificación. Preserva proporción (2:3). */
    private fun scaleUp(src: Bitmap): Bitmap {
        val targetLong = 1024
        val long = maxOf(src.width, src.height)
        if (long >= targetLong) return src
        val scale = targetLong.toFloat() / long
        val w = (src.width * scale).toInt().coerceAtLeast(1)
        val h = (src.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(src, w, h, true)
    }
}
