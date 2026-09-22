package com.mapleprojects.animaple

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Cadena de alarma robusta del check de capítulos.
 *
 * WorkManager es diferido por Doze y App Standby cuando la app lleva
 * tiempo sin abrirse (ventanas de mantenimiento que pueden espaciarse
 * horas), y las cadenas one-off auto-reagendadas se pierden si el
 * sistema cancela el trabajo. `setAndAllowWhileIdle` dispara la alarma
 * incluso en Doze y se re-agenda en cada disparo, de modo que aunque una
 * ejecución falle o se retrase, la cadena continúa sola.
 *
 * El receiver re-agenda la alarma ANTES de encolar el trabajo: la cadena
 * no depende de que el fetch termine bien.
 */
class EpisodeCheckAlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AniMaple"
        private const val ACTION_CHECK = "com.mapleprojects.animaple.EPISODE_CHECK_ALARM"
        private const val REQUEST_CODE = 2026
        private const val ALARM_MIN = 15L
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_CHECK) return

        // Reagendar la siguiente alarma PRIMERO: aunque el proceso muera
        // después, la cadena continúa.
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val followed = prefs.getString(EpisodeCheckWorker.KEY_FOLLOWED_JSON, null)
        if (followed.isNullOrEmpty() || followed == "{}") {
            cancel(context)
            Log.d(TAG, "EpisodeCheckAlarm: sin seguidos, cadena detenida")
            return
        }
        schedule(context)

        // Encolar el check en la cadena principal (reusa toda la lógica del
        // worker). REPLACE sobre la misma clave: no acumula un flujo paralelo.
        EpisodeCheckWorker.enqueueFromAlarm(context)
    }

    /**
     * Programa la siguiente alarma. Usa setAndAllowWhileIdle (inexacta pero
     * dispara en Doze y NO requiere SCHEDULE_EXACT_ALARM; el sistema la
     * agrupa pero la cadena se auto-corrige). Si el dispositivo permite
     * alarmas exactas, usa setExactAndAllowWhileIdle para máxima puntualidad.
     */
    fun schedule(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = pendingIntent(context)
            val triggerAt = System.currentTimeMillis() + ALARM_MIN * 60_000L
            val exact = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                am.canScheduleExactAlarms()
            if (exact) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
            Log.d(TAG, "EpisodeCheckAlarm: próxima alarma en $ALARM_MIN min (exact=$exact)")
        } catch (e: Exception) {
            // setExact puede lanzar SecurityException si el permiso fue
            // revocado; caer a la variante inexacta sin permiso.
            try {
                val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + ALARM_MIN * 60_000L,
                    pendingIntent(context),
                )
                Log.d(TAG, "EpisodeCheckAlarm: fallback inexacto $ALARM_MIN min")
            } catch (e2: Exception) {
                Log.e(TAG, "EpisodeCheckAlarm schedule error: ${e2.message}")
            }
        }
    }

    fun cancel(context: Context) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(context))
            Log.d(TAG, "EpisodeCheckAlarm cancelada")
        } catch (e: Exception) {
            Log.e(TAG, "EpisodeCheckAlarm cancel error: ${e.message}")
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, EpisodeCheckAlarmReceiver::class.java)
            .setAction(ACTION_CHECK)
        return PendingIntent.getBroadcast(
            context, REQUEST_CODE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
