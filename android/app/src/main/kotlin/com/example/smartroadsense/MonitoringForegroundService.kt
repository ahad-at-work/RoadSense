package com.example.smartroadsense

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class MonitoringForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "road_sense_foreground"
        const val NOTIF_ID = 12345
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "RoadSense Monitoring"
            val channel = NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW)
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        val notif: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("RoadSense monitoring")
                .setContentText("Monitoring sensors and alerts")
                .setSmallIcon(R.mipmap.ic_launcher)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle("RoadSense monitoring")
                .setContentText("Monitoring sensors and alerts")
                .setSmallIcon(R.mipmap.ic_launcher)
                .build()
        }

        startForeground(NOTIF_ID, notif)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        stopForeground(true)
        super.onDestroy()
    }
}
