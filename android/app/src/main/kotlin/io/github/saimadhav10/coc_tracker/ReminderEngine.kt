package io.github.saimadhav10.coc_tracker

import android.Manifest
import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import org.json.JSONArray
import java.util.Calendar

object ReminderEngine {
    const val GAME = "com.supercell.clashofclans"
    private const val HOUR = 3600000L
    private const val CHANNEL = "village_reminders"
    private fun prefs(c: Context) = c.getSharedPreferences("reminders", Context.MODE_PRIVATE)
    fun hasUsageAccess(c: Context): Boolean {
        val ops = c.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        return ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), c.packageName) == AppOpsManager.MODE_ALLOWED
    }
    fun notificationsAllowed(c: Context): Boolean {
        val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun configure(c: Context, args: Map<*, *>) {
        val p = prefs(c)
        val enabled = args["enabled"] == true
        val upgrades = JSONArray(args["upgrades"] as? List<*> ?: emptyList<Any>())
        val ids = (0 until upgrades.length()).map { upgrades.getJSONObject(it).getString("id") }.toSet()
        val previous = p.getStringSet("notified", emptySet()) ?: emptySet()
        val edit = p.edit().putBoolean("enabled", enabled)
            .putInt("quietStart", (args["quietStart"] as? Number)?.toInt() ?: 22)
            .putInt("quietEnd", (args["quietEnd"] as? Number)?.toInt() ?: 8)
            .putString("upgrades", upgrades.toString()).putStringSet("notified", previous.intersect(ids))
        if (enabled && !p.getBoolean("enabled", false)) {
            edit.putLong("enabledAt", System.currentTimeMillis()).putLong("lastSeen", System.currentTimeMillis()).putLong("lastReminder", 0)
        }
        edit.apply()
        if (!enabled) {
            val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancelAll()
        }
        schedule(c)
    }
    fun lastSeen(c: Context): Long {
        val p = prefs(c)
        var latest = p.getLong("lastSeen", p.getLong("enabledAt", System.currentTimeMillis()))
        if (!hasUsageAccess(c)) return latest
        val now = System.currentTimeMillis()
        val manager = c.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(maxOf(latest, now - 48 * HOUR).coerceAtMost(now), now)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.packageName == GAME && event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) latest = maxOf(latest, event.timeStamp)
        }
        if (latest != p.getLong("lastSeen", 0)) {
            p.edit().putLong("lastSeen", latest).apply()
            (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(24)
        }
        return latest
    }
    fun isQuiet(hour: Int, start: Int, end: Int): Boolean = when {
        start == end -> false
        start < end -> hour >= start && hour < end
        else -> hour >= start || hour < end
    }
    fun inactivityDue(now: Long, seen: Long, lastReminder: Long): Boolean =
        now - seen >= 24 * HOUR && now - lastReminder >= 3 * HOUR
    fun tick(c: Context) {
        val p = prefs(c)
        if (!p.getBoolean("enabled", false)) return
        val now = System.currentTimeMillis()
        val seen = lastSeen(c)
        val quiet = isQuiet(Calendar.getInstance().get(Calendar.HOUR_OF_DAY), p.getInt("quietStart", 22), p.getInt("quietEnd", 8))
        if (!quiet && notificationsAllowed(c)) {
            if (hasUsageAccess(c) && inactivityDue(now, seen, p.getLong("lastReminder", 0))) {
                notify(c, 24, "Your village is waiting", "It’s been at least 24 hours since Clash was opened on this device.", true)
                p.edit().putLong("lastReminder", now).apply()
            }
            val upgrades = JSONArray(p.getString("upgrades", "[]"))
            val notified = (p.getStringSet("notified", emptySet()) ?: emptySet()).toMutableSet()
            val due = (0 until upgrades.length()).map { upgrades.getJSONObject(it) }
                .filter { it.getLong("at") <= now && !notified.contains(it.getString("id")) }
            due.groupBy { it.optString("profile", it.getString("village")) }.forEach { (profile, items) ->
                val village = items.first().getString("village")
                notify(c, 1000 + (profile.hashCode() and 0xffff), "$village ($profile) · refresh your snapshot",
                    "${items.size} recorded upgrade timer(s) ended. Confirm in-game and import fresh JSON.", false)
                items.forEach { notified.add(it.getString("id")) }
            }
            p.edit().putStringSet("notified", notified).apply()
        }
        schedule(c)
    }
    fun schedule(c: Context) {
        val alarm = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = PendingIntent.getBroadcast(c, 1, Intent(c, TrackerReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarm.cancel(intent)
        if (!prefs(c).getBoolean("enabled", false)) return
        val now = System.currentTimeMillis()
        val upgrades = JSONArray(prefs(c).getString("upgrades", "[]"))
        val next = (0 until upgrades.length()).map { upgrades.getJSONObject(it).getLong("at") }
            .filter { it > now }.minOrNull() ?: (now + HOUR)
        // Inexact scheduling respects battery restrictions and needs no exact-alarm permission.
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, minOf(next, now + HOUR).coerceAtLeast(now + 60000), intent)
    }
    private fun notify(c: Context, id: Int, title: String, body: String, game: Boolean) {
        val manager = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Village reminders", NotificationManager.IMPORTANCE_DEFAULT))
        val trackerIntent = Intent(c, MainActivity::class.java)
        val launch = if (game) c.packageManager.getLaunchIntentForPackage(GAME) ?: trackerIntent else trackerIntent
        val pending = PendingIntent.getActivity(c, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(c, CHANNEL).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title).setContentText(body).setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pending).setAutoCancel(true)
        if (game) notification.addAction(Notification.Action.Builder(null, "Open Clash", pending).build())
        manager.notify(id, notification.build())
    }
}

class TrackerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try { ReminderEngine.tick(context) } finally { pending.finish() }
        }.start()
    }
}
