import 'dart:collection';

import 'package:flutter/foundation.dart';

class AppLogEntry {
  final DateTime timestamp;
  final String message;

  const AppLogEntry({
    required this.timestamp,
    required this.message,
  });
}

class AppLogger extends ChangeNotifier {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int _maxEntries = 600;
  final List<AppLogEntry> _entries = <AppLogEntry>[];

  bool _paused = false;
  bool _notifyScheduled = false;

  static const List<String> _fieldTestAllowKeywords = <String>[
    'fluttererror:',
    'user gesture',
    'auto-follow disabled - user moved camera',
    'temporarily paused auto-follow',
    'event',
    'consensus',
    'detection',
    'rejected (stale)',
    'enhanced event markers',
    'sensor',
    'sensor reading snapshot',
    'acc:',
    'motion:',
    'location:',
    'accuracy:',
    'heading:',
    'speed=',
    'alt=',
    'accel',
    'gyro',
    'detected',
    'road_event_detected',
    'classification',
    'confidence',
    'training window',
    'monitoring',
    'movement',
    'decision',
    'risk_prediction',
    'ml_inference',
    'suppressed',
    'trip logging',
    'trip logger',
    'trip point',
    'trip upload',
    'queue',
    'upload rejected',
  ];

  static const List<String> _fieldTestDenyKeywords = <String>[
    'started continuous location tracking',
    'stopped continuous location tracking',
    'initial location:',
    'recentered to current location',
    'recentered to cached location',
    'locationsource',
    'locationservice disposed',
    'optimized for bike/vehicle speeds',
  ];

  bool get paused => _paused;
  UnmodifiableListView<AppLogEntry> get entries =>
      UnmodifiableListView<AppLogEntry>(_entries);

  void add(String message) {
    if (_paused) return;

    final lines = message.split('\n').where((line) => line.trim().isNotEmpty);
    final now = DateTime.now();

    for (final line in lines) {
      if (!_shouldKeepForFieldTesting(line)) continue;
      _entries.add(AppLogEntry(timestamp: now, message: line));
    }

    final overflow = _entries.length - _maxEntries;
    if (overflow > 0) {
      _entries.removeRange(0, overflow);
    }

    _scheduleNotify();
  }

  bool _shouldKeepForFieldTesting(String message) {
    final normalized = message.toLowerCase();

    for (final denied in _fieldTestDenyKeywords) {
      if (normalized.contains(denied)) {
        return false;
      }
    }

    for (final allowed in _fieldTestAllowKeywords) {
      if (normalized.contains(allowed)) {
        return true;
      }
    }

    return false;
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void setPaused(bool value) {
    if (_paused == value) return;
    _paused = value;
    notifyListeners();
  }

  void togglePaused() {
    _paused = !_paused;
    notifyListeners();
  }

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future<void>.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
