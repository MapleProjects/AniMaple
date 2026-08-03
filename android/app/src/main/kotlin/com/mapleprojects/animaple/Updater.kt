package com.mapleprojects.animaple

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File

/**
 * Actualización automática lado nativo: versión instalada, carpeta de
 * descarga, instalación del APK (FileProvider + permiso de orígenes
 * desconocidos) y limpieza de APK huérfanos.
 */
object Updater {

    private const val TAG = "AniMaple"
    private const val AUTHORITY = "com.mapleprojects.animaple.fileprovider"
    private const val UPDATE_DIR = "updates"

    /** Versión instalada (versionName). */
    fun currentVersion(ctx: Context): String {
        return try {
            ctx.packageManager
                .getPackageInfo(ctx.packageName, 0)
                .versionName
                ?: ""
        } catch (e: Exception) {
            Log.e(TAG, "getVersion error: ${e.message}")
            ""
        }
    }

    /** Carpeta privada de la app para APK descargados. */
    fun updatesDir(ctx: Context): File {
        val dir = File(ctx.filesDir, UPDATE_DIR)
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /** true si la app ya tiene permiso para instalar apps desconocidas
     *  (Android 8+ pide habilitarlo por-app; en versiones antiguas siempre). */
    fun canRequestPackageInstalls(ctx: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ctx.packageManager.canRequestPackageInstalls()
    }

    /** Abre los ajustes para habilitar "Instalar apps desconocidas" (este app). */
    fun requestInstallPermission(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            this.requestInstallPermissionImpl(ctx)
        }
    }

    /** Lanza el instalador del sistema para [apk]. Si la app no tiene permiso
     *  de "orígenes desconocidos" (Android 8+), lo pide primero. */
    fun install(ctx: Context, apk: File) {
        if (!apk.exists()) {
            Log.w(TAG, "install: APK no existe ${apk.path}")
            return
        }
        // Android 8+ requiere permiso por-app "Install unknown apps".
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !ctx.packageManager.canRequestPackageInstalls()
        ) {
            requestInstallPermissionImpl(ctx)
            return
        }
        launchInstaller(ctx, apk)
    }

    private fun requestInstallPermissionImpl(ctx: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + ctx.packageName)
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "requestInstallPermission error: ${e.message}")
        }
    }

    private fun launchInstaller(ctx: Context, apk: File) {
        try {
            val uri = FileProvider.getUriForFile(ctx, AUTHORITY, apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            ctx.startActivity(intent)
            // Tras lanzar el instalador el archivo ya se leyó; se elimina en el
            // próximo arranque (cleanupDownloaded). Sin dejar basura.
            Log.d(TAG, "Instalador lanzado para ${apk.name}")
        } catch (e: Exception) {
            Log.e(TAG, "launchInstaller error: ${e.message}")
        }
    }

    /** Borra los APK descargados. Se llama al arrancar (la app nueva limpia
     *  el archivo que la versión anterior descargó). */
    fun cleanupDownloaded(ctx: Context) {
        try {
            val dir = updatesDir(ctx)
            val files = dir.listFiles() ?: return
            for (f in files) {
                if (f.name.endsWith(".apk")) {
                    f.delete()
                    Log.d(TAG, "cleanup: borrado ${f.name} (${f.length() / 1024} KB)")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "cleanup error: ${e.message}")
        }
    }
}
