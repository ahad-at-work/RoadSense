import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class BackgroundPreparationResult {
  final bool canStart;
  final bool needsBatteryOptimizationExemption;
  final String? userMessage;

  const BackgroundPreparationResult({
    required this.canStart,
    this.needsBatteryOptimizationExemption = false,
    this.userMessage,
  });
}

class BackgroundExecutionService {
  static Future<bool> areRoadMonitoringPermissionsReady() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final locationWhenInUse = await Permission.locationWhenInUse.status;
    if (!locationWhenInUse.isGranted) {
      return false;
    }

    final locationAlways = await Permission.locationAlways.status;
    if (!locationAlways.isGranted) {
      return false;
    }

    final notificationPermission = await Permission.notification.status;
    if (!notificationPermission.isGranted) {
      return false;
    }

    final batteryOptimization =
        await Permission.ignoreBatteryOptimizations.status;
    if (!batteryOptimization.isGranted) {
      return false;
    }

    return true;
  }

  static Future<BackgroundPreparationResult>
      ensureReadyForRoadMonitoring() async {
    if (!Platform.isAndroid) {
      return const BackgroundPreparationResult(canStart: true);
    }

    final locationWhenInUse = await Permission.locationWhenInUse.request();
    if (!locationWhenInUse.isGranted) {
      return const BackgroundPreparationResult(
        canStart: false,
        userMessage:
            'Location permission is required to start road monitoring.',
      );
    }

    final locationAlways = await Permission.locationAlways.request();
    if (!locationAlways.isGranted) {
      debugPrint(
        'Background location was not granted. Monitoring may stop when app is backgrounded.',
      );
      return const BackgroundPreparationResult(
        canStart: false,
        userMessage:
            'Allow "All the time" location access to keep monitoring in background.',
      );
    }

    final notificationPermission = await Permission.notification.request();
    if (!notificationPermission.isGranted) {
      return const BackgroundPreparationResult(
        canStart: false,
        userMessage:
            'Notification permission is required for background monitoring on Android.',
      );
    }

    final batteryOptimization =
        await Permission.ignoreBatteryOptimizations.request();
    if (!batteryOptimization.isGranted) {
      debugPrint(
        'Battery optimization exemption not granted. Monitoring may pause on some devices.',
      );
      return const BackgroundPreparationResult(
        canStart: true,
        needsBatteryOptimizationExemption: true,
        userMessage:
            'Open battery optimization settings and allow RoadSense to run without restrictions.',
      );
    }

    return const BackgroundPreparationResult(canStart: true);
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return;
    }

    const packageName = 'com.example.smartroadsense';
    const intent = AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:$packageName',
    );

    await intent.launch();
  }
}
