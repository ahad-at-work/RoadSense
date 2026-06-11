import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' show pow;
import '../utils/app_config.dart';

// ============================================================================
//  SENSOR DATA SERVICE - ENHANCED v3.1
// Features:
// - Offline queue with retry logic
// - Exponential backoff
// - Secure configuration (moved from hardcoded URL)
// - Battery optimization
// - Queue age expiration (7 days)
// - Safe type casting with validation
// ============================================================================

class SensorData {
  //  FIX #6: Moved to secure configuration
  // DO NOT hardcode API URLs in source code!
  // Set this via environment variables or Firebase Remote Config
  static String? _scriptUrl;

  // Offline queue
  static final List<Map<String, dynamic>> _offlineQueue = [];
  static const int maxQueueSize = 100;
  static const Duration maxQueueAge = Duration(days: 7);
  static bool _isProcessingQueue = false;

  //  ADD THIS: Public getter to check configuration status
  static bool get isConfigured => _scriptUrl != null && _scriptUrl!.isNotEmpty;

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration initialRetryDelay = Duration(seconds: 2);

  //  SECURITY: Initialize with secure config
  static Future<void> initialize({String? apiUrl}) async {
    final prefs = await SharedPreferences.getInstance();

    // Prefer explicit apiUrl, then AppConfig, then stored pref
    final configUrl = await AppConfig.getApiEndpoint();
    _scriptUrl = apiUrl ?? configUrl ?? prefs.getString('api_endpoint');

    // Persist provided endpoint or AppConfig endpoint for background isolates
    if (apiUrl != null && apiUrl.isNotEmpty) {
      await AppConfig.updateApiEndpoint(apiUrl);
    } else if (configUrl != null && configUrl.isNotEmpty) {
      await AppConfig.updateApiEndpoint(configUrl);
    }

    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      debugPrint(" Warning: API endpoint not configured!");
      debugPrint(" Set it via SensorData.initialize(apiUrl: 'your-url')");
    }

    // Load offline queue from storage
    await _loadOfflineQueue();

    // Clean expired events
    await _cleanExpiredEvents();

    // Start processing queue if we have items
    if (_offlineQueue.isNotEmpty) {
      _processOfflineQueue();
    }
  }

  //  Update API endpoint at runtime (for admin users)
  static Future<void> updateApiEndpoint(String newUrl) async {
    _scriptUrl = newUrl;
    await AppConfig.updateApiEndpoint(newUrl);
    debugPrint(" API endpoint updated");
  }

  //
  // MAIN INSERT FUNCTION WITH RETRY LOGIC
  //

  static Future<bool> insert({
    required double lat,
    required double lon,
    required double ax,
    required double ay,
    required double az,
    required double gx,
    required double gy,
    required double gz,
    required double speed,
    required String type,
    double confidence = 0.0,
    String location = "Pakistan",
  }) async {
    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      debugPrint(" Cannot send data: API endpoint not configured");
      return false;
    }

    final eventData = {
      "timestamp": DateTime.now().toIso8601String(),
      "lat": lat,
      "lon": lon,
      "ax": ax,
      "ay": ay,
      "az": az,
      "gx": gx,
      "gy": gy,
      "gz": gz,
      "speed": speed,
      "type": type,
      "confidence": confidence,
      "device": Platform.isAndroid ? 'Android' : 'iOS',
      "location": location,
    };

    // Try to send immediately
    final success = await _sendWithRetry(eventData);

    if (!success) {
      // Add to offline queue
      await _addToOfflineQueue(eventData);
      debugPrint(
          " Event queued for later (offline queue: ${_offlineQueue.length})");
    }

    return success;
  }

  //
  // RETRY LOGIC WITH EXPONENTIAL BACKOFF
  //

  static Future<bool> _sendWithRetry(
    Map<String, dynamic> eventData, {
    int attempt = 0,
  }) async {
    //  BUG FIX: Capture scriptUrl in local variable to avoid repeated force unwraps
    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      debugPrint(" Cannot send: API endpoint not configured");
      return false;
    }

    final scriptUrl = _scriptUrl!;

    try {
      final body = jsonEncode(eventData);
      final headers = await AppConfig.getAuthHeaders(body: body);
      headers['User-Agent'] =
          'RoadSense/${Platform.isAndroid ? 'Android' : 'iOS'}';

      final response = await http
          .post(
            Uri.parse(scriptUrl),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 302) {
        final type = eventData['type'];
        final conf = (eventData['confidence'] * 100).toStringAsFixed(0);
        debugPrint(" $type sent ($conf%)");
        return true;
      } else if (response.statusCode >= 500) {
        // Server error - retry
        if (attempt < maxRetries) {
          return await _retryWithBackoff(eventData, attempt);
        }
      } else if (response.statusCode == 429) {
        // Rate limited - retry with longer delay
        debugPrint(" Rate limited, retrying...");
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 5 * (attempt + 1)));
          return await _sendWithRetry(eventData, attempt: attempt + 1);
        }
      }

      debugPrint(" HTTP ${response.statusCode}: ${response.body}");
      return false;
    } on TimeoutException {
      debugPrint(" Request timeout (attempt ${attempt + 1}/${maxRetries + 1})");
      if (attempt < maxRetries) {
        return await _retryWithBackoff(eventData, attempt);
      }
      return false;
    } catch (e) {
      debugPrint(" Error sending data: $e");
      if (attempt < maxRetries) {
        return await _retryWithBackoff(eventData, attempt);
      }
      return false;
    }
  }

  static Future<bool> _retryWithBackoff(
    Map<String, dynamic> eventData,
    int attempt,
  ) async {
    //  Using dart:math pow (imported at top)
    final delaySeconds = initialRetryDelay.inSeconds * pow(2, attempt).toInt();
    final delay = Duration(seconds: delaySeconds);

    debugPrint(
        " Retrying in ${delay.inSeconds}s (attempt ${attempt + 2}/${maxRetries + 1})");
    await Future.delayed(delay);

    return await _sendWithRetry(eventData, attempt: attempt + 1);
  }

  //
  // OFFLINE QUEUE MANAGEMENT
  //

  static Future<void> _addToOfflineQueue(Map<String, dynamic> eventData) async {
    if (_offlineQueue.length >= maxQueueSize) {
      // Remove oldest event if queue is full
      _offlineQueue.removeAt(0);
      debugPrint(" Offline queue full, removed oldest event");
    }

    _offlineQueue.add(eventData);
    await _saveOfflineQueue();

    // Try to process queue (non-blocking)
    if (!_isProcessingQueue) {
      _processOfflineQueue();
    }
  }

  //  BUG FIX: Improved queue processing with index-based removal
  static Future<void> _processOfflineQueue() async {
    if (_isProcessingQueue || _offlineQueue.isEmpty) return;

    _isProcessingQueue = true;
    debugPrint(" Processing offline queue (${_offlineQueue.length} items)...");

    int successCount = 0;
    int processedCount = 0;
    final initialQueueSize = _offlineQueue.length;

    // Process from the front of the queue
    while (_offlineQueue.isNotEmpty && processedCount < initialQueueSize) {
      final eventData = _offlineQueue.first;
      final success = await _sendWithRetry(eventData);

      if (success) {
        _offlineQueue.removeAt(0);
        successCount++;
      } else {
        // If one fails, stop processing to avoid wasting battery
        debugPrint(" Queue processing paused (network issue)");
        break;
      }

      processedCount++;

      // Small delay between requests to avoid rate limiting
      if (_offlineQueue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    await _saveOfflineQueue();

    if (successCount > 0) {
      debugPrint(" Uploaded $successCount queued events");
    }

    _isProcessingQueue = false;
  }

  //
  // QUEUE EXPIRATION (NEW IN v3.1)
  //

  static Future<void> _cleanExpiredEvents() async {
    final now = DateTime.now();
    final before = _offlineQueue.length;

    _offlineQueue.removeWhere((event) {
      final timestampStr = event['timestamp'] as String?;
      if (timestampStr == null) return true; // Remove if no timestamp

      try {
        final timestamp = DateTime.parse(timestampStr);
        final age = now.difference(timestamp);
        return age > maxQueueAge;
      } catch (e) {
        return true; // Remove if invalid timestamp
      }
    });

    final removed = before - _offlineQueue.length;
    if (removed > 0) {
      debugPrint(
          " Removed $removed expired events (>${maxQueueAge.inDays} days old)");
      await _saveOfflineQueue();
    }
  }

  //
  // PERSISTENT STORAGE
  //

  static Future<void> _saveOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_offlineQueue);
      await prefs.setString('offline_queue', jsonString);
    } catch (e) {
      debugPrint(" Failed to save offline queue: $e");
    }
  }

  //  BUG FIX: Safe type casting with validation
  static Future<void> _loadOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('offline_queue');

      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        _offlineQueue.clear();

        // Safe iteration with type checking
        for (var item in decoded) {
          if (item is Map<String, dynamic>) {
            // Validate required fields
            if (item.containsKey('timestamp') &&
                item.containsKey('lat') &&
                item.containsKey('lon') &&
                item.containsKey('type')) {
              _offlineQueue.add(item);
            } else {
              debugPrint(" Skipping invalid queued event: missing fields");
            }
          } else {
            debugPrint(" Skipping non-map item in queue");
          }
        }

        if (_offlineQueue.isNotEmpty) {
          debugPrint(" Loaded ${_offlineQueue.length} valid queued events");
        }
      }
    } catch (e) {
      debugPrint(" Failed to load offline queue: $e");
      // Clear corrupted queue
      _offlineQueue.clear();
      await _saveOfflineQueue();
    }
  }

  //
  // PUBLIC UTILITIES
  //

  /// Get number of events waiting to be uploaded
  static int getQueueSize() => _offlineQueue.length;

  /// Manually trigger queue processing (e.g., when network comes back)
  static Future<void> retryOfflineQueue() async {
    if (_offlineQueue.isEmpty) {
      debugPrint(" Queue is empty");
      return;
    }
    await _processOfflineQueue();
  }

  /// Clear the offline queue (use with caution!)
  static Future<void> clearOfflineQueue() async {
    _offlineQueue.clear();
    await _saveOfflineQueue();
    debugPrint(" Offline queue cleared");
  }

  ///  BUG FIX: Improved getQueueStats with proper timestamp parsing
  static Map<String, dynamic> getQueueStats() {
    final types = <String, int>{};
    DateTime? oldestTimestamp;

    for (var event in _offlineQueue) {
      // Count event types
      final type = event['type'] as String? ?? 'Unknown';
      types[type] = (types[type] ?? 0) + 1;

      // Track oldest timestamp
      final timestampStr = event['timestamp'] as String?;
      if (timestampStr != null) {
        try {
          final timestamp = DateTime.parse(timestampStr);
          if (oldestTimestamp == null || timestamp.isBefore(oldestTimestamp)) {
            oldestTimestamp = timestamp;
          }
        } catch (e) {
          // Invalid timestamp format - skip
        }
      }
    }

    return {
      'totalCount': _offlineQueue.length,
      'eventTypes': types,
      'oldestTimestamp': oldestTimestamp?.toIso8601String(),
    };
  }
}

// ============================================================================
//  CHANGELOG v3.1
// ============================================================================
/*
VERSION 3.1 - Bug Fixes & Enhancements


 BUG FIX #1: Removed Duplicate pow() Function
  - Removed custom pow() function (lines 239-246 in v3.0)
  - Now properly uses dart:math pow throughout
  - Eliminates name collision and type mismatch

 BUG FIX #2: Safe Type Casting in _loadOfflineQueue
  - Added validation for each item in decoded JSON
  - Checks for required fields (timestamp, lat, lon, type)
  - Skips invalid items instead of crashing
  - Clears corrupted queue on parse error

 BUG FIX #3: Fixed Queue Processing Race Condition
  - Changed from _offlineQueue.remove(eventData) to removeAt(0)
  - Processes from front of queue using index-based removal
  - Prevents map equality issues
  - Safer iteration with bounds checking

 BUG FIX #4: Eliminated Force Unwraps
  - Captured _scriptUrl in local variable in _sendWithRetry
  - Added null check at function start
  - Reduced crash risk from force unwraps

 BUG FIX #5: Improved getQueueStats
  - Properly parses timestamps instead of returning raw strings
  - Finds actual oldest timestamp
  - Handles invalid timestamps gracefully
  - Returns ISO8601 formatted string

 NEW FEATURE: Queue Age Expiration
  - Added maxQueueAge = 7 days constant
  - _cleanExpiredEvents() removes old events
  - Called automatically on initialization
  - Prevents indefinite queue bloat

 ENHANCEMENT: Better Initialization
  - Now calls _cleanExpiredEvents() after loading queue
  - Ensures only fresh events remain
  - Improved startup reliability


FIXES FROM v3.0:
   Secure configuration (no hardcoded URLs)
   Offline queue with persistent storage
   Exponential backoff retry logic
   Battery optimization
   Rate limiting awareness

NEW IN v3.1:
   Removed duplicate pow() function
   Safe type casting with validation
   Index-based queue removal
   Eliminated force unwraps
   Proper timestamp parsing in stats
   7-day queue age expiration


USAGE:

1. Initialize on app start:
   await SensorData.initialize(apiUrl: 'https://your-secure-endpoint.com/api');

2. Or load from remote config:
   await SensorData.initialize(); // Loads from SharedPreferences

3. Update endpoint at runtime (admin only):
   await SensorData.updateApiEndpoint(newUrl);

4. Check queue status:
   final stats = SensorData.getQueueStats();
   print("Queued events: ${stats['totalCount']}");
   print("Oldest event: ${stats['oldestTimestamp']}");

5. Manually retry queue:
   await SensorData.retryOfflineQueue();


SECURITY RECOMMENDATIONS:

1.  Use HTTPS endpoints only
2.  Implement server-side API key validation
3.  Add rate limiting on backend (100 events/user/hour)
4.  Use Firebase Remote Config for dynamic endpoint updates
5.  Implement HMAC signatures for request validation
6.  Never commit API keys to version control


*/
