package com.mapleprojects.animaple

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * Servicio foreground de reproducción (tipo mediaPlayback).
 *
 * La manera correcta de publicar la notificación media con barra de
 * progreso y controles es desde un foreground service declarado con
 * foregroundServiceType="mediaPlayback" y publicada con startForeground().
 * Publicar con notify() desde la Activity no genera la notificación media
 * del sistema en Android moderno.
 *
 * Posee el MediaSession del reproductor. Los callbacks de la sesión
 * (play/pause/stop/seek) se reenvían a Dart vía el canal media_session
 * usando el FlutterEngine cacheado por MainActivity.
 */
class PlaybackService : Service() {

    private var mediaSession: MediaSession? = null
    private var notificationManager: NotificationManager? = null

    // Último estado recibido desde Dart.
    private var lastTitle = ""
    private var lastEpisode = 0
    private var lastPlaying = false
    private var lastPosition = 0L
    private var lastDuration = 0L
    private var lastAnimeId = 0

    // Portada: se descarga en hilo de fondo (el main thread no puede tocar
    // red → NetworkOnMainThreadException que silenciaba la imagen).
    private var posterBitmap: Bitmap? = null
    private var posterAnimeId = 0

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannel()
        setupSession()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let { applyState(it) }
        // El service queda en foreground mientras la notificación exista.
        publishNotification()
        return START_STICKY
    }

    override fun onDestroy() {
        notificationManager?.cancel(NOTIFICATION_ID)
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    // ── Estado ──

    private fun applyState(intent: Intent) {
        lastTitle = intent.getStringExtra(EXTRA_TITLE) ?: ""
        lastEpisode = intent.getIntExtra(EXTRA_EPISODE, 0)
        lastPlaying = intent.getBooleanExtra(EXTRA_PLAYING, false)
        lastPosition = intent.getLongExtra(EXTRA_POSITION, 0L)
        lastDuration = intent.getLongExtra(EXTRA_DURATION, 0L)
        val animeId = intent.getIntExtra(EXTRA_ANIME_ID, 0)
        if (animeId != 0 && (posterBitmap == null || posterAnimeId != animeId)) {
            posterAnimeId = animeId
            posterBitmap = null
            loadPoster(animeId)
        }
    }

    private fun setupSession() {
        mediaSession?.release()
        mediaSession = MediaSession(this, "AniMapleMediaSession").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = sendToDart("mediaTogglePlayPause")
                override fun onPause() = sendToDart("mediaTogglePlayPause")
                override fun onStop() {
                    sendToDart("mediaStop")
                    stopSelf()
                }
                override fun onSeekTo(pos: Long) = sendToDart("mediaSeekTo", pos)
            })
            isActive = true
        }
    }

    /** Reenvía un control al canal Dart usando el engine cacheado. */
    private fun sendToDart(method: String, arg: Any? = null) {
        try {
            val engine = FlutterEngineCache.getInstance().get(ENGINE_ID) ?: return
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            channel.invokeMethod(method, arg)
        } catch (e: Exception) {
            Log.w(TAG, "sendToDart $method failed: ${e.message}")
        }
    }

    // ── Notificación ──

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Reproducción de video",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Controles de reproducción de AniMaple"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun publishNotification() {
        val session = mediaSession ?: return

        val state = PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_STOP or
                PlaybackState.ACTION_SEEK_TO
            )
            .setState(
                if (lastPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                lastPosition, if (lastPlaying) 1.0f else 0.0f
            )
            .setActiveQueueItemId(0)
            .build()
        session.setPlaybackState(state)

        val metaBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, lastTitle)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, "Episodio $lastEpisode")
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "AniMaple")
            .putLong(MediaMetadata.METADATA_KEY_DURATION, lastDuration)
        val poster = posterBitmap
        if (poster != null) metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, poster)
        session.setMetadata(metaBuilder.build())

        val playPauseIcon = if (lastPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (lastPlaying) "Pausar" else "Reproducir"

        val playPauseIntent = PendingIntent.getBroadcast(
            this, 0, Intent(ACTION_PLAY_PAUSE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getBroadcast(
            this, 1, Intent(ACTION_STOP).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        if (poster != null) builder.setLargeIcon(poster)

        val notification = builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(lastTitle)
            .setContentText("Episodio $lastEpisode")
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(playPauseIcon, playPauseLabel, playPauseIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Detener", stopIntent)
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(session.sessionToken)
                    .setShowActionsInCompactView(0)
            )
            .setPriority(Notification.PRIORITY_LOW)
            .build()

        Log.d(TAG, "publishNotification: $lastTitle ep=$lastEpisode playing=$lastPlaying pos=$lastPosition dur=$lastDuration poster=${poster != null}")
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun loadPoster(animeId: Int) {
        Thread {
            var bmp: Bitmap? = null
            try {
                val url = java.net.URL("https://cdn.animeav1.com/covers/$animeId.jpg")
                bmp = android.graphics.BitmapFactory.decodeStream(url.openStream())
            } catch (e: Exception) {
                Log.w(TAG, "loadPoster error: ${e.message}")
            }
            val loaded = bmp
            mainHandler.post {
                if (loaded != null && posterAnimeId == animeId) {
                    posterBitmap = loaded
                    publishNotification()
                }
            }
        }.start()
    }

    // ── API estática ──

    companion object {
        private const val TAG = "AniMaplePlayback"
        const val CHANNEL_ID = "animaple_media_playback"
        const val NOTIFICATION_ID = 1001
        // Debe coincidir con el id con que MainActivity cachea el engine.
        private const val ENGINE_ID = "animaple_main_engine"
        const val MEDIA_CHANNEL = "com.mapleprojects.animaple/media_session"

        const val ACTION_PLAY_PAUSE = "com.mapleprojects.animaple.MEDIA_PLAY_PAUSE"
        const val ACTION_STOP = "com.mapleprojects.animaple.MEDIA_STOP"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_EPISODE = "episode"
        private const val EXTRA_PLAYING = "playing"
        private const val EXTRA_POSITION = "position"
        private const val EXTRA_DURATION = "duration"
        private const val EXTRA_ANIME_ID = "animeId"

        @Volatile
        private var running = false

        fun isRunning() = running

        /** Actualiza el estado y asegura el service en primer plano. */
        fun update(
            context: Context,
            title: String,
            episode: Int,
            playing: Boolean,
            position: Long,
            duration: Long,
            animeId: Int,
        ) {
            // No arrancar el servicio (ni mostrar notificación) si nunca hubo
            // reproducción real: evita una notificación media "pausada" eterna
            // por el simple hecho de abrir la pantalla del reproductor.
            if (!running && !playing) {
                Log.d(TAG, "skip start (idle)")
                return
            }
            running = true
            val intent = Intent(context, PlaybackService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_EPISODE, episode)
                putExtra(EXTRA_PLAYING, playing)
                putExtra(EXTRA_POSITION, position)
                putExtra(EXTRA_DURATION, duration)
                putExtra(EXTRA_ANIME_ID, animeId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** Detiene el service y retira la notificación media. */
        fun stop(context: Context) {
            running = false
            context.stopService(Intent(context, PlaybackService::class.java))
        }
    }
}
