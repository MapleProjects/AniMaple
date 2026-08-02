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
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // ── Method Channels ──
    private val PIP_CHANNEL = "com.mapleprojects.animaple/pip"
    private val MEDIA_CHANNEL = "com.mapleprojects.animaple/media_session"

    private var pipMethodChannel: MethodChannel? = null
    private var mediaMethodChannel: MethodChannel? = null

    // ── PiP State ──
    private var isPipSupported = false
    private var isPlaying = false
    private val handler = Handler(Looper.getMainLooper())
    private var pendingPip = false

    // ── Media Session State ──
    private var mediaSession: MediaSession? = null
    private var notificationManager: NotificationManager? = null

    companion object {
        private const val TAG = "AniMaple"
        private const val MEDIA_CHANNEL_ID = "animaple_media_playback"
        private const val NOTIFICATION_ID = 1001
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

        setupMediaSession()
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
        val session = mediaSession ?: return

        // Update playback state with position for seekbar
        val state = PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or
                PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_STOP or
                PlaybackState.ACTION_SEEK_TO
            )
            .setState(
                if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                position, if (playing) 1.0f else 0.0f
            )
            .setActiveQueueItemId(0)
            .build()
        session.setPlaybackState(state)

        // Update metadata with big icon
        val metadataBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, "Episodio $episode")
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "AniMaple")
            .putLong(MediaMetadata.METADATA_KEY_DURATION, duration)
        // Load poster as big picture
        val posterUrl = "https://cdn.animeav1.com/covers/$animeId.jpg"
        try {
            val bitmap = android.graphics.BitmapFactory.decodeStream(
                java.net.URL(posterUrl).openStream()
            )
            metadataBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bitmap)
        } catch (_: Exception) {}
        session.setMetadata(metadataBuilder.build())

        val playPauseIcon = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseLabel = if (playing) "Pausar" else "Reproducir"

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

        // Build notification with platform API
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MEDIA_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText("Episodio $episode")
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

        Log.d(TAG, "showMediaNotification: title=$title ep=$episode playing=$playing pos=$position dur=$duration animeId=$animeId")
        notificationManager?.notify(NOTIFICATION_ID, notification)
        Log.d(TAG, "showMediaNotification: notification sent")
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
