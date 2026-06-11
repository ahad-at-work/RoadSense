import 'package:flutter/services.dart';

class ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('com.example.smartroadsense/foreground');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }
}
