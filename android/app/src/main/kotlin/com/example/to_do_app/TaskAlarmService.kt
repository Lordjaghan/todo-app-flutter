package com.example.to_do_app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

internal object TaskAlarmScheduler {
    private const val preferencesName = "task_alarm_schedule"
    private const val entryPrefix = "task_"
    private const val extraTaskId = "taskId"
    private const val extraTitle = "title"
    private const val extraBody = "body"
    private const val extraScheduledTime = "scheduledTime"

    const val actionFire = "com.example.to_do_app.action.FIRE_TASK_ALARM"
    const val actionStop = "com.example.to_do_app.action.STOP_TASK_ALARM"
    const val actionSnooze = "com.example.to_do_app.action.SNOOZE_TASK_ALARM"

    fun schedule(
        context: Context,
        taskId: Int,
        title: String,
        body: String,
        scheduledTime: Long,
    ) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
            ?: throw IllegalStateException("Alarm service is unavailable")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            throw SecurityException("Exact alarm permission is not granted")
        }

        val intent = alarmIntent(context, taskId, title, body, scheduledTime)
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            scheduledTime,
            firePendingIntent(context, taskId, intent),
        )
        save(context, taskId, title, body, scheduledTime)
    }

    fun cancel(context: Context, taskId: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager?.cancel(firePendingIntent(context, taskId, alarmIntent(context, taskId)))
        preferences(context).edit().remove(entryKey(taskId)).apply()
        TaskAlarmService.stopIfActive(context, taskId)
    }

    fun snooze(context: Context, taskId: Int) {
        val saved = preferences(context).getString(entryKey(taskId), null) ?: return
        val alarm = JSONObject(saved)
        schedule(
            context,
            taskId,
            alarm.getString(extraTitle),
            alarm.getString(extraBody),
            System.currentTimeMillis() + SNOOZE_DURATION_MS,
        )
        TaskAlarmService.stopIfActive(context, taskId)
    }

    fun restoreAfterBoot(context: Context) {
        val now = System.currentTimeMillis()
        preferences(context).all.forEach { (key, value) ->
            if (!key.startsWith(entryPrefix) || value !is String) return@forEach
            try {
                val taskId = key.removePrefix(entryPrefix).toInt()
                val alarm = JSONObject(value)
                schedule(
                    context,
                    taskId,
                    alarm.getString(extraTitle),
                    alarm.getString(extraBody),
                    maxOf(alarm.getLong(extraScheduledTime), now + 1_000L),
                )
            } catch (_: Exception) {
                preferences(context).edit().remove(key).apply()
            }
        }
    }

    private fun save(context: Context, taskId: Int, title: String, body: String, time: Long) {
        val alarm = JSONObject()
            .put(extraTitle, title)
            .put(extraBody, body)
            .put(extraScheduledTime, time)
        preferences(context).edit().putString(entryKey(taskId), alarm.toString()).apply()
    }

    private fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    private fun entryKey(taskId: Int) = "$entryPrefix$taskId"

    private fun alarmIntent(
        context: Context,
        taskId: Int,
        title: String? = null,
        body: String? = null,
        time: Long? = null,
    ) = Intent(context, TaskAlarmReceiver::class.java).apply {
        action = actionFire
        putExtra(extraTaskId, taskId)
        title?.let { putExtra(extraTitle, it) }
        body?.let { putExtra(extraBody, it) }
        time?.let { putExtra(extraScheduledTime, it) }
    }

    private fun firePendingIntent(context: Context, taskId: Int, intent: Intent) =
        PendingIntent.getBroadcast(
            context,
            taskId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private const val SNOOZE_DURATION_MS = 5 * 60 * 1000L
}

class TaskAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getIntExtra("taskId", -1)
        if (taskId <= 0) return
        val serviceIntent = Intent(context, TaskAlarmService::class.java).apply {
            putExtras(intent)
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}

class TaskAlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getIntExtra("taskId", -1)
        if (taskId <= 0) return
        when (intent.action) {
            TaskAlarmScheduler.actionStop -> TaskAlarmScheduler.cancel(context, taskId)
            TaskAlarmScheduler.actionSnooze -> TaskAlarmScheduler.snooze(context, taskId)
        }
    }
}

class TaskAlarmBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        TaskAlarmScheduler.restoreAfterBoot(context)
    }
}

class TaskAlarmService : Service() {
    private var alarmId = -1
    private var mediaPlayer: MediaPlayer? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent.action == STOP_SERVICE_ACTION) {
            if (intent.getIntExtra("taskId", -1) == alarmId) stopSelf()
            return START_NOT_STICKY
        }

        val taskId = intent.getIntExtra("taskId", -1)
        if (taskId <= 0) {
            stopSelf()
            return START_NOT_STICKY
        }

        alarmId = taskId
        activeTaskId = taskId
        val title = intent.getStringExtra("title") ?: "Task reminder"
        val body = intent.getStringExtra("body") ?: "This task is due now."
        startForeground(alarmId, buildNotification(title, body))
        startAlarmSound()
        return START_REDELIVER_INTENT
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        mediaPlayer?.let { player ->
            if (player.isPlaying) player.stop()
            player.release()
        }
        mediaPlayer = null
        if (alarmId > 0) {
            getSystemService(NotificationManager::class.java).cancel(alarmId)
        }
        if (activeTaskId == alarmId) activeTaskId = -1
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val alarmAudio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Task alarms",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Ringing task alarms with snooze and dismiss controls"
            setSound(null, alarmAudio)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 700, 400)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, body: String) =
        NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Dismiss",
                actionPendingIntent(TaskAlarmScheduler.actionStop),
            )
            .addAction(
                android.R.drawable.ic_lock_idle_alarm,
                "Snooze 5 min",
                actionPendingIntent(TaskAlarmScheduler.actionSnooze),
            )
            .build()

    private fun actionPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, TaskAlarmActionReceiver::class.java).apply {
            this.action = action
            putExtra("taskId", alarmId)
        }
        return PendingIntent.getBroadcast(
            this,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun startAlarmSound() {
        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return
        val player = MediaPlayer()
        mediaPlayer = player
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.isLooping = true
            player.setDataSource(this, soundUri)
            player.setOnPreparedListener { preparedPlayer ->
                if (mediaPlayer === preparedPlayer) preparedPlayer.start()
            }
            player.setOnErrorListener { _, _, _ ->
                stopSelf()
                true
            }
            player.prepareAsync()
        } catch (_: Exception) {
            player.release()
            mediaPlayer = null
            stopSelf()
        }
    }

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "task_alarm_ringing_v1"
        private const val STOP_SERVICE_ACTION = "com.example.to_do_app.action.STOP_ACTIVE_ALARM"

        @Volatile
        private var activeTaskId = -1

        fun stopIfActive(context: Context, taskId: Int) {
            if (activeTaskId != taskId) return
            val stopIntent = Intent(context, TaskAlarmService::class.java).apply {
                action = STOP_SERVICE_ACTION
                putExtra("taskId", taskId)
            }
            context.startService(stopIntent)
        }
    }
}