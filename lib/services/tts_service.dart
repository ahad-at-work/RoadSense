import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

class TtsService {
  TtsService._private();
  static final TtsService instance = TtsService._private();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setSharedInstance(true);
    } catch (_) {}
    _initialized = true;
  }

  Future<String?> _getFilePathForLabel(String label) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'alert_${label.replaceAll(RegExp(r"[^a-zA-Z0-9_]"), '_')}.wav';
    return '${dir.path}/$fileName';
  }

  Future<String?> generateAlertFile(String label, String text) async {
    await init();

    final target = await _getFilePathForLabel(label);
    if (target == null) return null;

    final file = File(target);
    if (await file.exists()) return file.path;

    try {
      // Try to pick a male voice if available
      final voices = await _tts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        final male = voices.firstWhere(
          (v) => v.toString().toLowerCase().contains('male'),
          orElse: () => voices.first,
        );
        try {
          await _tts.setVoice(male);
        } catch (_) {}
      }

      // Set reasonable params
      await _tts.setSpeechRate(0.95);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      // Attempt to synthesize to file. Note: this may be platform-dependent.
      // flutter_tts exposes synthesizeToFile on some platforms.
      try {
        final synthResult = await _tts.synthesizeToFile(text, target);
        if (synthResult == 1 ||
            synthResult == 'success' ||
            synthResult == true) {
          if (await file.exists()) return file.path;
        }
      } catch (_) {}

      // Fallback: speak and return null (no file)
      await _tts.speak(text);
      return null;
    } catch (e) {
      if (kDebugMode) print('TTS generate failed: $e');
      return null;
    }
  }
}
