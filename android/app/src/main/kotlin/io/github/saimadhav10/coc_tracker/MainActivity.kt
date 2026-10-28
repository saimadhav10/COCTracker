package io.github.saimadhav10.coc_tracker

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var fileResult: MethodChannel.Result? = null
    private var backupText = ""
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coc_tracker/device").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "configure" -> { ReminderEngine.configure(this, call.arguments as Map<*, *>); result.success(null) }
                    "status" -> result.success(mapOf("supported" to true, "usageAccess" to ReminderEngine.hasUsageAccess(this),
                        "notifications" to ReminderEngine.notificationsAllowed(this), "lastSeen" to ReminderEngine.lastSeen(this)))
                    "usageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null)
                    }
                    "notificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)); result.success(null)
                    }
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 31)
                        result.success(null)
                    }
                    "openClash" -> {
                        val intent = packageManager.getLaunchIntentForPackage(ReminderEngine.GAME)
                        if (intent == null) result.error("not_installed", "Clash of Clans is not installed on this device.", null)
                        else { startActivity(intent); result.success(null) }
                    }
                    "saveBackup", "readBackup" -> {
                        if (fileResult != null) result.error("busy", "A file picker is already open.", null)
                        else {
                            fileResult = result
                            if (call.method == "saveBackup") {
                                backupText = call.argument<String>("text") ?: ""
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                                    .setType("application/json").putExtra(Intent.EXTRA_TITLE, "COCTracker-backup.json"), 41)
                            } else startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                                .setType("*/*"), 42)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { fileResult = null; result.error("device_error", e.message, null) }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 41 && requestCode != 42) return
        val result = fileResult ?: return
        fileResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); backupText = ""; return }
        try {
            if (requestCode == 41) {
                val output = contentResolver.openOutputStream(uri, "wt") ?: error("Cannot write this file")
                output.use { it.write(backupText.toByteArray(Charsets.UTF_8)) }; result.success(true)
            } else {
                val input = contentResolver.openInputStream(uri) ?: error("Cannot open this file")
                val bytes = input.use { stream ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count == -1) break
                        if (output.size() + count > 10000000) error("Backup exceeds 10 MB")
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                result.success(String(bytes, Charsets.UTF_8))
            }
        } catch (e: Exception) { result.error("file_error", e.message, null) }
        finally { backupText = "" }
    }
}
