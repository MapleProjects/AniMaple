package com.mapleprojects.animaple

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Tras un reinicio del dispositivo dispara una revisión inmediata de nuevos
 * capítulos y garantiza que el trabajo periódico de WorkManager quede
 * registrado. El periódico por sí solo ya sobrevive al reinicio (WorkManager
 * lo reagenda vía su propio receiver de BOOT_COMPLETED); este receiver solo
 * adelanta la primera comprobación para que las notificaciones lleguen pronto
 * después de reiniciar, sin tener que abrir la app.
 *
 * BOOT_COMPLETED es un broadcast protegido con recepción por manifest; sigue
 * exento en Android 14/15 para encolar trabajo (lo prohibido desde boot es
 * lanzar ciertos foreground services, no encolar WorkManager).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        Log.d("AniMaple", "BootReceiver: reinicio detectado")
        EpisodeCheckWorker.enqueueImmediate(context)
        EpisodeCheckWorker.enqueuePeriodic(context)
    }
}
