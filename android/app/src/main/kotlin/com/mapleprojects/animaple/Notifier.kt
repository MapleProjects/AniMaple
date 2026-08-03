package com.mapleprojects.animaple

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

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

    /** Notifica el estreno de un capítulo. [slug] abre el episodio si se toca. */
    fun notifyNewEpisode(ctx: Context, title: String, episode: Int, slug: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!nm.areNotificationsEnabled()) return
        }
        ensureNewEpisodeChannel(ctx)

        // Tap → abre la app.
        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val contentIntent = PendingIntent.getActivity(
            ctx, slug.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(ctx, CHANNEL_NEW_EP)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("Nuevo capítulo de $title")
            .setContentText("Episodio $episode ya disponible")
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .build()

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val id = NOTIF_ID_BASE + (slug.hashCode() and 0x7fffffff) % 10000
        nm.notify(id, notification)
    }
}
