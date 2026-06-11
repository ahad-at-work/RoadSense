package com.example.smartroadsense

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.example.smartroadsense/foreground"
	private val NOTIFICATION_CHANNEL = "com.example.smartroadsense/notifications"
	private val ALERT_CHANNEL_ID = "road_sense_alerts"
	private val ALERT_NOTIFICATION_BASE_ID = 24000

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"startForegroundService" -> {
					startMonitoringService()
					result.success(null)
				}
				"stopForegroundService" -> {
					stopMonitoringService()
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"showAlertNotification" -> {
					@Suppress("UNCHECKED_CAST")
					val arguments = call.arguments as? Map<String, Any?>
					showAlertNotification(arguments)
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun showAlertNotification(arguments: Map<String, Any?>?) {
		if (arguments == null) return

		ensureAlertChannel()

		val label = (arguments["label"] as? String)?.ifBlank { "risk" } ?: "risk"
		val score = (arguments["score"] as? Number)?.toDouble() ?: 0.0
		val lat = (arguments["lat"] as? Number)?.toDouble()
		val lon = (arguments["lon"] as? Number)?.toDouble()
		val titleOverride = arguments["title"] as? String
		val messageOverride = arguments["message"] as? String

		val title = titleOverride ?: if (label == "crash_like") {
			"Crash-like risk detected"
		} else {
			"High risk detected"
		}
		val locationText = if (lat != null && lon != null) {
			"Lat ${String.format("%.5f", lat)}, Lon ${String.format("%.5f", lon)}"
		} else {
			"Open the app for details"
		}
		val contentText = messageOverride ?: "$title • ${String.format("%.0f", score * 100)}% • $locationText"

		val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
		val contentPendingIntent = if (launchIntent != null) {
			PendingIntent.getActivity(
				this,
				label.hashCode(),
				launchIntent,
				pendingIntentFlags()
			)
		} else {
			null
		}

		val builder = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
			.setSmallIcon(R.mipmap.ic_launcher)
			.setContentTitle(title)
			.setContentText(contentText)
			.setStyle(NotificationCompat.BigTextStyle().bigText(contentText))
			.setPriority(NotificationCompat.PRIORITY_HIGH)
			.setCategory(NotificationCompat.CATEGORY_ALARM)
			.setAutoCancel(true)
			.setOnlyAlertOnce(true)
			.setDefaults(0)

		if (contentPendingIntent != null) {
			builder.setContentIntent(contentPendingIntent)
		}

		val notification = builder.build()
		val notificationManager = getSystemService(NotificationManager::class.java)
		notificationManager.notify(ALERT_NOTIFICATION_BASE_ID + label.hashCode(), notification)
	}

	private fun ensureAlertChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

		val notificationManager = getSystemService(NotificationManager::class.java)
		val existingChannel = notificationManager.getNotificationChannel(ALERT_CHANNEL_ID)
		if (existingChannel != null) return

		val channel = NotificationChannel(
			ALERT_CHANNEL_ID,
			"RoadSense alerts",
			NotificationManager.IMPORTANCE_HIGH,
		).apply {
			description = "System notifications for risk alerts"
			setShowBadge(true)
		}
		notificationManager.createNotificationChannel(channel)
	}

	private fun pendingIntentFlags(): Int {
		return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
		} else {
			PendingIntent.FLAG_UPDATE_CURRENT
		}
	}

	private fun startMonitoringService() {
		val intent = Intent(this, MonitoringForegroundService::class.java)
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			startForegroundService(intent)
		} else {
			startService(intent)
		}
	}

	private fun stopMonitoringService() {
		val intent = Intent(this, MonitoringForegroundService::class.java)
		stopService(intent)
	}
}
