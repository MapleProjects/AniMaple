package com.mapleprojects.animaple

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class DownloadForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    companion object {
        const val CHANNEL_DOWNLOADS = "animaple_downloads"
        const val CHANNEL_COMPLETED = "animaple_downloads_completed"
        const val NOTIFICATION_ID = 2001
        const val NOTIFICATION_ID_COMPLETED_BASE = 2100

        const val ACTION_START = "com.mapleprojects.animaple.DOWNLOAD_START"
        const val ACTION_UPDATE = "com.mapleprojects.animaple.DOWNLOAD_UPDATE"
        const val ACTION_STOP = "com.mapleprojects.animaple.DOWNLOAD_STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_EPISODE = "episode"
        const val EXTRA_SLUG = "slug"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_STATUS = "status"
        const val EXTRA_COMPLETED_TITLE = "completed_title"
        const val EXTRA_COMPLETED_EPISODE = "completed_episode"

        fun start(context: Context, title: String, episode: Int, slug: String) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_EPISODE, episode)
                putExtra(EXTRA_SLUG, slug)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun update(context: Context, title: String, episode: Int, progress: Int, status: String) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_EPISODE, episode)
                putExtra(EXTRA_PROGRESS, progress)
                putExtra(EXTRA_STATUS, status)
            }
            context.startService(intent)
        }

        fun stop(context: Context, completedTitle: String? = null, completedEpisode: Int? = null) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_STOP
                if (completedTitle != null) putExtra(EXTRA_COMPLETED_TITLE, completedTitle)
                if (completedEpisode != null) putExtra(EXTRA_COMPLETED_EPISODE, completedEpisode)
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Anime"
                val episode = intent.getIntExtra(EXTRA_EPISODE, 1)
                val notification = buildDownloadNotification(title, episode, 0, "Iniciando descarga...")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "Anime"
                val episode = intent.getIntExtra(EXTRA_EPISODE, 1)
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0)
                val status = intent.getStringExtra(EXTRA_STATUS) ?: "$progress%"
                val notification = buildDownloadNotification(title, episode, progress, status)
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                val completedTitle = intent.getStringExtra(EXTRA_COMPLETED_TITLE)
                val completedEpisode = intent.getIntExtra(EXTRA_COMPLETED_EPISODE, 0)
                releaseLocks()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()

                if (!completedTitle.isNullOrEmpty() && completedEpisode > 0) {
                    showCompletedNotification(completedTitle, completedEpisode)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AniMaple:DownloadWakeLock").apply {
                setReferenceCounted(false)
                acquire(4 * 60 * 60 * 1000L) // 4 horas máx de salvaguarda
            }
        }
        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "AniMaple:DownloadWifiLock").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        wakeLock = null

        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (_: Exception) {}
        wifiLock = null
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val downloadChannel = NotificationChannel(
                CHANNEL_DOWNLOADS,
                "Descargas en curso",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Progreso de descarga de capítulos"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(downloadChannel)

            val completedChannel = NotificationChannel(
                CHANNEL_COMPLETED,
                "Descargas completadas",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Avisos al finalizar la descarga de capítulos"
                setShowBadge(true)
            }
            nm.createNotificationChannel(completedChannel)
        }
    }

    private fun buildDownloadNotification(
        title: String,
        episode: Int,
        progress: Int,
        statusText: String
    ): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_DOWNLOADS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Descargando: $title")
            .setContentText("Episodio $episode • $statusText")
            .setProgress(100, progress.coerceIn(0, 100), false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showCompletedNotification(title: String, episode: Int) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            title.hashCode() + episode,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_COMPLETED)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Descarga completada")
            .setContentText("$title - Episodio $episode listo sin conexión")
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID_COMPLETED_BASE + episode, notification)
    }
}
