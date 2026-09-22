package com.mapleprojects.animaple

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    // ── Method Channels ──
    private val PIP_CHANNEL = "com.mapleprojects.animaple/pip"
    private val MEDIA_CHANNEL = "com.mapleprojects.animaple/media_session"
    private val NOTIF_CHANNEL = "com.mapleprojects.animaple/notifications"
    private val UPDATE_CHANNEL = "com.mapleprojects.animaple/updater"
    private val DOWNLOAD_CHANNEL = "com.mapleprojects.animaple/downloads"

    private var pipMethodChannel: MethodChannel? = null
    private var mediaMethodChannel: MethodChannel? = null
    private var notifMethodChannel: MethodChannel? = null
    private var updateMethodChannel: MethodChannel? = null
    private var downloadMethodChannel: MethodChannel? = null

    // ── PiP State ──
    private var isPipSupported = false
    private var isPlaying = false
    private val handler = Handler(Looper.getMainLooper())
    private var pendingPip = false

    // ── Media Session State ──
    private var mediaSession: MediaSession? = null
    private var notificationManager: NotificationManager? = null

    // Estado último de la notificación media: permite re-publicarla cuando
    // la portada termina de descargarse o cuando avanza la posición.
    private var lastTitle = ""
    private var lastEpisode = 0
    private var lastPlaying = false
    private var lastPosition = 0L
    private var lastDuration = 0L
    private var lastAnimeId = 0
    // Portada cacheada para no re-descargar en cada actualización de posición.
    private var posterBitmap: android.graphics.Bitmap? = null
    private var posterAnimeId = 0

    companion object {
        private const val TAG = "AniMaple"
        private const val MEDIA_CHANNEL_ID = "animaple_media_playback"
        private const val NOTIFICATION_ID = 1001
        private const val PREFS_NOTIF = "animaple_notif"
        private const val ACTION_MEDIA_PLAY_PAUSE = "com.mapleprojects.animaple.MEDIA_PLAY_PAUSE"
        private const val ACTION_MEDIA_STOP = "com.mapleprojects.animaple.MEDIA_STOP"
    }

    // ── Broadcast Receivers ──
    private val pipPauseReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            isPlaying = !isPlaying
            pipMethodChannel?.invokeMethod("pipTogglePlayPause", null)
            updatePipParams()
        }
    }

    private val mediaReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_MEDIA_PLAY_PAUSE -> {
                    mediaMethodChannel?.invokeMethod("mediaTogglePlayPause", null)
                }
                ACTION_MEDIA_STOP -> {
                    dismissMediaNotification()
                    mediaMethodChannel?.invokeMethod("mediaStop", null)
                }
            }
        }
    }

    // ── Engine Configuration ──
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        isPipSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O

        try { unregisterReceiver(pipPauseReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(mediaReceiver) } catch (_: Exception) {}

        registerReceiver(pipPauseReceiver, IntentFilter("com.mapleprojects.animaple.PIP_PAUSE"), RECEIVER_EXPORTED)

        val mediaFilter = IntentFilter().apply {
            addAction(ACTION_MEDIA_PLAY_PAUSE)
            addAction(ACTION_MEDIA_STOP)
        }
        registerReceiver(mediaReceiver, mediaFilter, RECEIVER_EXPORTED)

        // ── PiP Channel ──
        pipMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (isPipSupported && !isInPictureInPictureMode) {
                        isPlaying = true
                        val params = buildPipParams(autoEnter = true)
                        enterPictureInPictureMode(params)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "updatePipState" -> {
                    isPlaying = call.arguments as? Boolean ?: true
                    updatePipParams()
                    result.success(true)
                }
                "isPipSupported" -> result.success(isPipSupported)
                else -> result.notImplemented()
            }
        }

        // ── Media Session Channel ──
        mediaMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        mediaMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMediaSession" -> {
                    val title = call.argument<String>("title") ?: ""
                    val episode = call.argument<Int>("episode") ?: 0
                    val playing = call.argument<Boolean>("playing") ?: false
                    val position = call.argument<Long>("position") ?: 0L
                    val duration = call.argument<Long>("duration") ?: 0L
                    val animeId = call.argument<Int>("animeId") ?: 0
                    showMediaNotification(title, episode, playing, position, duration, animeId)
                    result.success(true)
                }
                "dismissMediaNotification" -> {
                    dismissMediaNotification()
                    result.success(true)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Crea el canal de notificaciones de novedades (idempotente).
        Notifier.ensureNewEpisodeChannel(this)
        setupNotificationChannel(flutterEngine)
        setupUpdateChannel(flutterEngine)
        setupMediaSession()
    }

    // ── Updater Channel ──
    // Actualización automática desde GitHub. Flutter consulta el release,
    // descarga el APK en `updates/` y pide instalar vía FileProvider.
    private fun setupUpdateChannel(flutterEngine: FlutterEngine) {
        updateMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
        // Al arrancar la app nueva, limpiar APK descargados que ya no se
        // necesitan (la instalación anterior dejó el archivo huérfano).
        Updater.cleanupDownloaded(this)

        updateMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentVersion" -> {
                    result.success(Updater.currentVersion(this))
                }
                "getUpdatesDir" -> {
                    result.success(Updater.updatesDir(this).absolutePath)
                }
                "canRequestPackageInstalls" -> {
                    // Consulta si la app puede instalar APK (permitir fuentes
                    // desconocidas). Se consulta ANTES de descargar para pedir
                    // el permiso a tiempo y no tener que re-descargar.
                    result.success(Updater.canRequestPackageInstalls(this))
                }
                "requestInstallPermission" -> {
                    // Abre los ajustes para habilitar "Instalar apps
                    // desconocidas" para esta app.
                    Updater.requestInstallPermission(this)
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                    } else {
                        Updater.install(this, File(path))
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Notification Service Channel ──
    // Flutter agenda la revisión periódica de nuevos capítulos (WorkManager),
    // escribe el espejo de seguidos y pide el permiso de notificaciones.
    private fun setupNotificationChannel(flutterEngine: FlutterEngine) {
        notifMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
        notifMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleEpisodeCheck" -> {
                    scheduleEpisodeCheck()
                    result.success(true)
                }
                "updateFollowedMirror" -> {
                    val json = call.argument<String>("json") ?: "{}"
                    updateFollowedMirror(json)
                    result.success(true)
                }
                "requestPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }
                "notificationStatus" -> {
                    result.success(notificationStatus())
                }
                "openAppNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }
                "isBatteryOptimizationIgnored" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ── Download Channel ──
        downloadMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL)
        downloadMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startDownloadService" -> {
                    val title = call.argument<String>("title") ?: "Anime"
                    val episode = call.argument<Int>("episode") ?: 1
                    val slug = call.argument<String>("slug") ?: ""
                    DownloadForegroundService.start(this, title, episode, slug)
                    result.success(true)
                }
                "updateDownloadProgress" -> {
                    val title = call.argument<String>("title") ?: "Anime"
                    val episode = call.argument<Int>("episode") ?: 1
                    val progress = call.argument<Int>("progress") ?: 0
                    val status = call.argument<String>("status") ?: ""
                    DownloadForegroundService.update(this, title, episode, progress, status)
                    result.success(true)
                }
                "stopDownloadService" -> {
                    val completedTitle = call.argument<String>("completedTitle")
                    val completedEp = call.argument<Int>("completedEp")
                    DownloadForegroundService.stop(this, completedTitle, completedEp)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Registra el seguimiento periódico de capítulos (15 min). El
     *  PeriodicWorkRequest lo administra el sistema: sobrevive reinicios y
     *  proceso muerto. KEEP: no se duplica en cada arranque. También se
     *  agenda la alarma robusta que dispara en Doze (ver receiver). */
    private fun scheduleEpisodeCheck() {
        EpisodeCheckWorker.enqueuePeriodic(this)
        EpisodeCheckWorker.enqueueAlarm(this)
    }

    // ── Permiso de notificaciones (Android 13+ / POST_NOTIFICATIONS) ──
    // Regla del sistema: si el usuario toca "Don't allow", el diálogo ya NO
    // vuelve a aparecer y solo se reactiva desde Ajustes. Se guarda el
    // resultado del request (1002) en prefs para distinguir "posible" (nunca
    // respondió / swipe-away) de "permanente" (negó) sin consultar una API
    // inestable. La app re-pide solo en "posible"; en "permanente" se guía
    // a Ajustes desde Dart.

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (areNotificationsEnabled()) return
            if (notificationStatus() != "possible") return
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                1002
            )
        }
    }

    /** "granted" | "permanent" | "possible" para que Dart decida qué hacer. */
    private fun notificationStatus(): String {
        if (areNotificationsEnabled()) return "granted"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val prefs = getSharedPreferences(PREFS_NOTIF, MODE_PRIVATE)
            val requested = prefs.getBoolean("perm_requested", false)
            val granted = prefs.getBoolean("perm_granted", false)
            return if (requested && !granted) "permanent" else "possible"
        }
        return "granted"
    }

    private fun areNotificationsEnabled(): Boolean {
        return (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .areNotificationsEnabled()
    }

    private fun openNotificationSettings() {
        try {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openNotificationSettings error: ${e.message}")
        }
    }

    // ── Optimización de batería (Doze) ──
    // Si el dispositivo entra en Doze con la app en segundo plano, el trabajo
    // periódico se difiere a ventanas de mantenimiento (pueden espaciarse
    // mucho). Eximir a la app (Settings ACTION_REQUEST_IGNORE_BATTERY_
    // OPTIMIZATIONS) permite que el worker corra con normalidad, como hacen
    // WhatsApp/Facebook. Es un permiso especial (Play lo restringe a apps
    // cuyo nucleo se ve perjudicado; esta app distribuye por GitHub).

    private fun isBatteryOptimizationIgnored(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isBatteryOptimizationIgnored()) return
        try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "requestBatteryOptimizationExemption error: ${e.message}")
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {}
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1002) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            getSharedPreferences(PREFS_NOTIF, MODE_PRIVATE).edit()
                .putBoolean("perm_requested", true)
                .putBoolean("perm_granted", granted)
                .apply()
            Log.d(TAG, "POST_NOTIFICATIONS result: granted=$granted")
            if (granted) Notifier.ensureNewEpisodeChannel(this)
        }
    }

    /** Persiste el espejo {slug: titulo} de seguidos para que el Worker lo lea
     *  sin depender de la sesión/red de Google. Si se vacía, se cancela el worker. */
    private fun updateFollowedMirror(json: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        prefs.edit().putString(EpisodeCheckWorker.KEY_FOLLOWED_JSON, json).apply()
        // KEEP hace el periódico idempotente: no se duplica si ya existe.
        scheduleEpisodeCheck()
        if (json == "{}" || json.isEmpty()) {
            EpisodeCheckWorker.cancel(this)
        }
    }

    // ══════════════════════════════════════════════
    //  MEDIA SESSION (platform API, minSdk 21+)
    // ══════════════════════════════════════════════

    private fun setupMediaSession() {
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()

        mediaSession?.release()

        mediaSession = MediaSession(this, "AniMapleMediaSession").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    mediaMethodChannel?.invokeMethod("mediaTogglePlayPause", null)
                }
                override fun onPause() {
                    mediaMethodChannel?.invokeMethod("mediaTogglePlayPause", null)
                }
                override fun onStop() {
                    dismissMediaNotification()
                    mediaMethodChannel?.invokeMethod("mediaStop", null)
                }
            })
            isActive = true
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                MEDIA_CHANNEL_ID,
                "Reproducción de video",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Controles de reproducción de AniMaple"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun showMediaNotification(title: String, episode: Int, playing: Boolean, position: Long, duration: Long, animeId: Int) {
        // Guardar el último estado para re-publicar cuando la portada esté
        // lista o cuando la posición avance desde Dart.
        lastTitle = title
        lastEpisode = episode
        lastPlaying = playing
        lastPosition = position
        lastDuration = duration
        lastAnimeId = animeId

        // La portada se descarga en hilo de fondo: en el main thread la red
        // lanza NetworkOnMainThreadException (que el catch anterior tragaba
        // silenciosamente → la imagen nunca aparecía). Cachear: solo se
        // descarga cuando cambia el anime.
        if (posterBitmap == null || posterAnimeId != animeId) {
            posterAnimeId = animeId
            posterBitmap = null
            loadPosterInBackground(animeId)
        }

        publishMediaNotification()
    }

    private fun publishMediaNotification() {
        val session = mediaSession ?: return

        // Playback state con posición: el sistema dibuja la barra de progreso
        // (timeline) y la avanza mientras el estado es STATE_PLAYING.
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

        // Metadata con duración y portada: la imagen del capítulo aparece en
        // la notificación extendida (album art).
        val metadataBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, lastTitle)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, "Episodio $lastEpisode")
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "AniMaple")
            .putLong(MediaMetadata.METADATA_KEY_DURATION, lastDuration)
        val poster = posterBitmap
        if (poster != null) {
            metadataBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, poster)
        }
        session.setMetadata(metadataBuilder.build())

        val playPauseIcon = if (lastPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (lastPlaying) "Pausar" else "Reproducir"

        val playPauseIntent = PendingIntent.getBroadcast(
            this, NOTIFICATION_ID,
            Intent(ACTION_MEDIA_PLAY_PAUSE).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = PendingIntent.getBroadcast(
            this, NOTIFICATION_ID + 1,
            Intent(ACTION_MEDIA_STOP).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MEDIA_CHANNEL_ID)
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
                    .setMediaSession(session.getSessionToken())
                    .setShowActionsInCompactView(0)
            )
            .setPriority(Notification.PRIORITY_LOW)
            .build()

        Log.d(TAG, "publishMediaNotification: title=$lastTitle ep=$lastEpisode playing=$lastPlaying pos=$lastPosition dur=$lastDuration poster=${poster != null}")
        notificationManager?.notify(NOTIFICATION_ID, notification)
    }

    /** Descarga la portada en segundo plano y re-publica la notificación al
     *  terminar. Nunca toca red en el hilo principal. */
    private fun loadPosterInBackground(animeId: Int) {
        Thread {
            var bitmap: android.graphics.Bitmap? = null
            try {
                val url = java.net.URL("https://cdn.animeav1.com/covers/$animeId.jpg")
                bitmap = android.graphics.BitmapFactory.decodeStream(url.openStream())
            } catch (e: Exception) {
                Log.w(TAG, "loadPosterInBackground error: ${e.message}")
            }
            val bmp = bitmap
            handler.post {
                if (bmp != null && posterAnimeId == animeId) {
                    posterBitmap = bmp
                    publishMediaNotification()
                }
            }
        }.start()
    }

    private fun dismissMediaNotification() {
        notificationManager?.cancel(NOTIFICATION_ID)
        mediaSession?.setPlaybackState(
            PlaybackState.Builder()
                .setState(PlaybackState.STATE_NONE, 0, 0.0f)
                .build()
        )
    }

    // ══════════════════════════════════════════════
    //  PICTURE-IN-PICTURE
    // ══════════════════════════════════════════════

    private fun buildPipParams(autoEnter: Boolean = isPlaying): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val pauseIcon = Icon.createWithResource(this,
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
            val pauseIntent = PendingIntent.getBroadcast(
                this, 200,
                Intent("com.mapleprojects.animaple.PIP_PAUSE").setPackage(packageName),
                PendingIntent.FLAG_IMMUTABLE
            )
            val pauseAction = RemoteAction(
                pauseIcon,
                if (isPlaying) "Pausar" else "Reproducir",
                if (isPlaying) "Pausar reproducción" else "Reanudar reproducción",
                pauseIntent
            )
            builder.setActions(listOf(pauseAction))
        }

        return builder.build()
    }

    private fun updatePipParams() {
        if (isPipSupported) {
            title = ""
            setPictureInPictureParams(buildPipParams())
        }
    }

    private fun tryEnterPip(source: String) {
        if (isPlaying && isPipSupported && !isInPictureInPictureMode && !isFinishing) {
            try {
                val params = buildPipParams(autoEnter = true)
                val success = enterPictureInPictureMode(params)
                Log.d(TAG, "tryEnterPip($source): success=$success")
            } catch (e: Exception) {
                Log.e(TAG, "tryEnterPip($source) FAILED: ${e.message}")
            }
        } else {
            Log.d(TAG, "tryEnterPip($source): SKIPPED isPlaying=$isPlaying inPip=$isInPictureInPictureMode finishing=$isFinishing")
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        tryEnterPip("onUserLeaveHint")
    }

    override fun onPause() {
        super.onPause()
        if (!isInPictureInPictureMode && !isFinishing && isPlaying) {
            pendingPip = true
            tryEnterPip("onPause-immediate")
            handler.postDelayed({
                if (pendingPip && !isInPictureInPictureMode && !isFinishing && isPlaying) {
                    tryEnterPip("onPause-delayed")
                }
                pendingPip = false
            }, 300)
        }
    }

    override fun onResume() {
        super.onResume()
        pendingPip = false
    }

    override fun onStop() {
        super.onStop()
        // If activity stops and we're NOT in PiP, the user dismissed PiP with X
        if (!isInPictureInPictureMode && isPlaying) {
            pipMethodChannel?.invokeMethod("mediaStop", null)
            isPlaying = false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        Log.d(TAG, "onPictureInPictureModeChanged: $isInPictureInPictureMode")
        pipMethodChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        if (isInPictureInPictureMode) updatePipParams()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try { unregisterReceiver(pipPauseReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(mediaReceiver) } catch (_: Exception) {}
        mediaSession?.release()
        dismissMediaNotification()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
