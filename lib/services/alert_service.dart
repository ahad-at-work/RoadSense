import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tts_service.dart';

class AlertService {
  AlertService._private();
  static final AlertService instance = AlertService._private();

  static const MethodChannel _notificationChannel =
      MethodChannel('com.example.smartroadsense/notifications');

  final AudioPlayer _player = AudioPlayer();
  final Map<String, DateTime> _lastAlertAt = {};

  Duration _cooldownFor(String label) {
    if (label == 'crash_like') return const Duration(seconds: 8);
    if (label == 'high_risk') return const Duration(seconds: 6);
    return const Duration(seconds: 5);
  }

  bool _isCooling(String label) {
    final last = _lastAlertAt[label];
    if (last == null) return false;
    return DateTime.now().difference(last) < _cooldownFor(label);
  }

  /// Whether a label is still within its alert cooldown window.
  bool isOnCooldown(String label) => _isCooling(label);

  Future<void> showAlert(
    BuildContext context, {
    required String label,
    required double score,
    double? lat,
    double? lon,
    String? title,
    String? message,
  }) async {
    if (_isCooling(label)) return;
    _lastAlertAt[label] = DateTime.now();

    // No external notification plugin initialization required here.

    // Overlay
    final overlay = Overlay.of(context);
    final headline = title ??
        '${label.toUpperCase()} ${(score * 100).toStringAsFixed(0)}% - Stay alert';
    final body = message;
    final displayText = body == null ? headline : '$headline\n$body';
    final entry = OverlayEntry(
      builder: (c) => Positioned(
        top: 80,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: label == 'crash_like'
                  ? Colors.red.shade700
                  : Colors.orange.shade700,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.3),
                  blurRadius: 8,
                )
              ],
            ),
            child: Row(
              children: [
                Icon(
                  label == 'crash_like' ? Icons.dangerous : Icons.warning,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
      // Remove after short duration
      Timer(const Duration(seconds: 4), () {
        try {
          entry.remove();
        } catch (_) {}
      });

    // Try to play synthesized TTS audio (generated at first run). Fallback to asset.
    try {
      final text = (label == 'crash_like')
          ? 'Beep. Crash like alert.'
          : 'Beep. High risk alert.';
      final generated =
          await TtsService.instance.generateAlertFile(label, text);
      if (generated != null && await File(generated).exists()) {
        await _player.play(DeviceFileSource(generated));
      } else {
        final assetName = label == 'crash_like'
            ? 'alerts/crash_like.mp3'
            : 'alerts/high_risk.mp3';
        await _player.play(AssetSource(assetName));
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        await _notificationChannel.invokeMethod('showAlertNotification', {
          'label': label,
          'score': score,
          'lat': lat,
          'lon': lon,
          'title': title,
          'message': message,
        });
      } catch (_) {}
    }

    // Overlay + audio + haptic remain the immediate in-app alert path.
  }
}
