import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_config.dart';

class TripLoggerService {
  static const String _apiEndpointStorageKey = 'trip_logger_api_endpoint';
  static String? _scriptUrl;
  static bool _isLogging = false;
  static String? _currentTripId;
  static String? _currentRouteType;
  static DateTime? _lastLoggedAt;

  static const Duration _minLogInterval = Duration(seconds: 1);
  static const String _queueStorageKey = 'trip_logger_offline_queue_v1';
  static const int _maxQueueSize = 5000;

  static final List<Map<String, dynamic>> _offlineQueue =
      <Map<String, dynamic>>[];
  static bool _isProcessingQueue = false;
  static int _currentTripSentCount = 0;
  static int _currentTripQueuedCount = 0;

  static bool get isLogging => _isLogging;
  static String? get currentTripId => _currentTripId;
  static String? get currentRouteType => _currentRouteType;
  static int get currentTripSentCount => _currentTripSentCount;
  static int get currentTripQueuedCount => _currentTripQueuedCount;
  static int get pendingQueueSize => _offlineQueue.length;
  static bool get hasPendingQueue => _offlineQueue.isNotEmpty;

  static Future<void> initialize({String? apiUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUrl = prefs.getString(_apiEndpointStorageKey);

    // Prefer explicit apiUrl, then AppConfig, then stored trip logger key
    final configUrl = await AppConfig.getApiEndpoint();
    _scriptUrl = apiUrl ?? configUrl ?? storedUrl;

    // Persist provided endpoint (or AppConfig endpoint) for background isolates
    if (apiUrl != null && apiUrl.isNotEmpty) {
      await prefs.setString(_apiEndpointStorageKey, apiUrl);
    } else if (configUrl != null && configUrl.isNotEmpty) {
      await prefs.setString(_apiEndpointStorageKey, configUrl);
    }

    await _loadOfflineQueue();

    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      debugPrint(' Trip logger endpoint not configured');
      return;
    }

    if (_offlineQueue.isNotEmpty) {
      unawaited(_processOfflineQueue());
    }
  }

  static Future<void> updateApiEndpoint(String apiUrl) async {
    _scriptUrl = apiUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiEndpointStorageKey, apiUrl);
  }

  static Future<String?> startTrip({
    required String routeType,
    String? tripId,
  }) async {
    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      return null;
    }

    _currentTripId = tripId ?? _generateTripId();
    _currentRouteType = routeType;
    _isLogging = true;
    _lastLoggedAt = null;
    _currentTripSentCount = 0;
    _currentTripQueuedCount = 0;

    debugPrint(' Trip logging started: $_currentTripId ($routeType)');
    return _currentTripId;
  }

  static void stopTrip() {
    debugPrint(' Trip logging stopped: $_currentTripId | '
        'sent=$_currentTripSentCount queued=$_currentTripQueuedCount '
        'pending=${_offlineQueue.length}');
    _isLogging = false;
    _currentTripId = null;
    _currentRouteType = null;
    _lastLoggedAt = null;
  }

  static Future<void> logPosition(Position position) async {
    if (!_isLogging || _currentTripId == null || _currentRouteType == null) {
      return;
    }

    final now = DateTime.now();
    if (_lastLoggedAt != null &&
        now.difference(_lastLoggedAt!) < _minLogInterval) {
      return;
    }
    _lastLoggedAt = now;

    final row = <String, dynamic>{
      'dataType': 'trip_gps',
      'trip_id': _currentTripId,
      'timestamp_utc': now.toUtc().toIso8601String(),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'speed_mps': position.speed,
      'bearing_deg': position.heading,
      'accuracy_m': position.accuracy,
      'altitude_m': position.altitude,
      'route_type': _currentRouteType,
      'device': Platform.isAndroid ? 'Android' : 'iOS',
    };

    final success = await _sendRow(row);
    if (success) {
      _currentTripSentCount++;
      if (_currentTripSentCount % 10 == 0) {
        debugPrint(' Trip logger progress: sent=$_currentTripSentCount '
            'queued=$_currentTripQueuedCount pending=${_offlineQueue.length}');
      }
    } else {
      _currentTripQueuedCount++;
      await _enqueueRow(row);
      if (_currentTripQueuedCount % 5 == 0) {
        debugPrint(' Trip logger queueing: sent=$_currentTripSentCount '
            'queued=$_currentTripQueuedCount pending=${_offlineQueue.length}');
      }
    }
  }

  static String _generateTripId() {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    return 'trip_$stamp';
  }

  static Future<bool> _sendRow(Map<String, dynamic> row) async {
    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      return false;
    }

    try {
      final body = jsonEncode(row);
      final headers = await AppConfig.getAuthHeaders(body: body);
      headers['User-Agent'] =
          'RoadSense-TripLogger/${Platform.isAndroid ? 'Android' : 'iOS'}';

      final response = await http
          .post(
            Uri.parse(_scriptUrl!),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      final ok = response.statusCode == 200 || response.statusCode == 302;
      if (!ok) {
        final bodyPreview = response.body.length > 180
            ? '${response.body.substring(0, 180)}...'
            : response.body;
        debugPrint(' Trip logger upload rejected: status=${response.statusCode} '
            'body=$bodyPreview');
      }
      return ok;
    } catch (error) {
      debugPrint(' Trip logger point send failed: $error');
      return false;
    }
  }

  static Future<void> _enqueueRow(Map<String, dynamic> row) async {
    if (_offlineQueue.length >= _maxQueueSize) {
      _offlineQueue.removeAt(0);
    }
    _offlineQueue.add(row);
    await _saveOfflineQueue();

    if (!_isProcessingQueue) {
      unawaited(_processOfflineQueue());
    }
  }

  static Future<void> _processOfflineQueue() async {
    if (_isProcessingQueue || _offlineQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;
    try {
      while (_offlineQueue.isNotEmpty) {
        final row = _offlineQueue.first;
        final success = await _sendRow(row);
        if (!success) {
          break;
        }
        _offlineQueue.removeAt(0);
      }
      await _saveOfflineQueue();
    } finally {
      _isProcessingQueue = false;
    }
  }

  static Future<void> flushOfflineQueue() async {
    await _processOfflineQueue();
  }

  static Future<void> _loadOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueStorageKey);
    if (raw == null || raw.isEmpty) {
      _offlineQueue.clear();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _offlineQueue
          ..clear()
          ..addAll(decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)));
      }
    } catch (_) {
      _offlineQueue.clear();
    }
  }

  static Future<void> _saveOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueStorageKey, jsonEncode(_offlineQueue));
  }
}
