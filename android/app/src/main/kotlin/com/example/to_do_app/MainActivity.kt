package com.example.to_do_app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"to_do_app/task_alarm",
		).setMethodCallHandler { call, result ->
			try {
				when (call.method) {
					"schedule" -> {
						val taskId = call.argument<Number>("taskId")?.toInt()
						val title = call.argument<String>("title")
						val body = call.argument<String>("body")
						val scheduledTime = call.argument<Number>("scheduledTime")?.toLong()
						if (taskId == null || title == null || body == null || scheduledTime == null) {
							result.error("invalid_arguments", "Missing alarm details", null)
							return@setMethodCallHandler
						}
						TaskAlarmScheduler.schedule(
							applicationContext,
							taskId,
							title,
							body,
							scheduledTime,
						)
						result.success(null)
					}
					"cancel" -> {
						val taskId = call.argument<Number>("taskId")?.toInt()
						if (taskId == null) {
							result.error("invalid_arguments", "Missing task ID", null)
							return@setMethodCallHandler
						}
						TaskAlarmScheduler.cancel(applicationContext, taskId)
						result.success(null)
					}
					else -> result.notImplemented()
				}
			} catch (error: SecurityException) {
				result.error("exact_alarm_permission", error.message, null)
			} catch (error: Exception) {
				result.error("alarm_schedule_failed", error.message, null)
			}
		}
	}
}
