import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../utils/app_config.dart';
import 'dart:math' show min, sqrt, sin, cos, atan2, pi;

class EventModel {
  final double lat;
  final double lon;
  final String type;
  final double? confidence;
  final String? device;
  final DateTime? timestamp;
  final int? consensusCount;

  EventModel({
    required this.lat,
    required this.lon,
    required this.type,
    this.confidence,
    this.device,
    this.timestamp,
    this.consensusCount,
  });

  LatLng get position => LatLng(lat, lon);

  factory EventModel.fromJson(Map<String, dynamic> json) {
    final rawTimestamp = json['Timestamp'] ??
        json['timestamp'] ??
        json['time'] ??
        json['createdAt'];

    return EventModel(
      lat: double.tryParse(json['Latitude']?.toString() ?? '') ??
          double.tryParse(json['lat']?.toString() ?? '') ??
          0.0,
      lon: double.tryParse(json['Longitude']?.toString() ?? '') ??
          double.tryParse(json['lon']?.toString() ?? '') ??
          0.0,
      type: json['Type']?.toString() ?? json['type']?.toString() ?? 'Unknown',
      confidence: double.tryParse(
            json['Confidence']?.toString() ??
                json['confidence']?.toString() ??
                '',
          ) ??
          double.tryParse(json['conf']?.toString() ?? ''),
      device: json['Device']?.toString() ?? json['device']?.toString(),
      timestamp: _parseTimestamp(rawTimestamp),
      consensusCount: int.tryParse(
        json['ConsensusCount']?.toString() ??
            json['consensusCount']?.toString() ??
            json['consensus']?.toString() ??
            '',
      ),
    );
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;

    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;

      final asInt = int.tryParse(raw);
      if (asInt != null) {
        // Accept both seconds and milliseconds epoch.
        return asInt > 1000000000000
            ? DateTime.fromMillisecondsSinceEpoch(asInt)
            : DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
      }
    }

    if (raw is num) {
      final v = raw.toInt();
      return v > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(v)
          : DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }

    return null;
  }

  bool get isHighConfidence => confidence != null && confidence! >= 0.8;

  bool get isRecentEvent {
    if (timestamp == null) {
      if (EventService.debugConsensusDetails) {
        debugPrint(" Event without timestamp - treating as stale");
      }
      return false;
    }
    final age = DateTime.now().difference(timestamp!);
    return age.inHours < 24;
  }

  double get trustScore {
    final confScore = confidence ?? 0.5;
    final consScore =
        consensusCount != null ? min(consensusCount! / 5.0, 1.0) : 0.5;
    return (confScore * 0.6) + (consScore * 0.4);
  }
}

class EventService {
  static String? _scriptUrl;
  static bool debugConsensusDetails = false;
  static bool verboseLogging = false;

  static double consensusRadiusMeters = 15.0;
  static int minConsensusCount = 1;
  static Duration consensusTimeWindow = const Duration(minutes: 30);

  static DateTime? _lastFetchTime;
  static List<EventModel>? _cachedEvents;
  static const Duration cacheValidity = Duration(seconds: 30);
  static bool get isConfigured => _scriptUrl != null && _scriptUrl!.isNotEmpty;

  static void _logConsensus(String message) {
    if (debugConsensusDetails) {
      debugPrint(message);
    }
  }

  static void _log(String message) {
    if (verboseLogging || debugConsensusDetails) {
      debugPrint(message);
    }
  }

  static Future<void> initialize({String? apiUrl}) async {
    final configUrl = await AppConfig.getApiEndpoint();

    if (apiUrl != null && apiUrl.isNotEmpty) {
      _scriptUrl = apiUrl;
      await AppConfig.updateApiEndpoint(apiUrl);
    } else if (configUrl != null && configUrl.isNotEmpty) {
      _scriptUrl = configUrl;
      await AppConfig.updateApiEndpoint(configUrl);
    } else {
      _scriptUrl = await AppConfig.getApiEndpoint();
    }

    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      debugPrint(" Warning: Event service API endpoint not configured!");
    }
  }

  static Future<void> updateApiEndpoint(String newUrl) async {
    _scriptUrl = newUrl;
    await AppConfig.updateApiEndpoint(newUrl);
    _cachedEvents = null;
    debugPrint(" Event service endpoint updated");
  }

  Future<List<EventModel>> fetchEvents({bool forceRefresh = false}) async {
    if (_scriptUrl == null || _scriptUrl!.isEmpty) {
      debugPrint(" Cannot fetch events: API endpoint not configured");
      return [];
    }

    if (!forceRefresh &&
        _cachedEvents != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < cacheValidity) {
      debugPrint(" Returning cached events (${_cachedEvents!.length})");
      return _cachedEvents!;
    }

    try {
      final uri = Uri.parse(_scriptUrl!);
      _log(" Fetching events from API...");

      final headers = await AppConfig.getAuthHeaders();
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception("Request timeout after 15 seconds");
        },
      );

      _log(" Event fetch response status: ${response.statusCode}");

      if (response.statusCode != 200) {
        throw Exception(
            "HTTP ${response.statusCode}: ${response.reasonPhrase}");
      }

      final body = response.body.trim();

      if (body.isEmpty) {
        debugPrint(" Empty response body");
        return [];
      }

      if (!body.startsWith("[")) {
        debugPrint(" Event fetch invalid response format (expected JSON array)");
        throw Exception("Invalid response format - expected JSON array");
      }

      final List<dynamic> data = jsonDecode(body);

      if (data.isEmpty) {
        debugPrint(" No events found in response");
        _cachedEvents = [];
        _lastFetchTime = DateTime.now();
        return [];
      }

      final List<EventModel> rawEvents = data
          .map((e) {
            try {
              return EventModel.fromJson(e as Map<String, dynamic>);
            } catch (e) {
              debugPrint(" Failed to parse event: $e");
              return null;
            }
          })
          .whereType<EventModel>()
          .where((event) => event.lat != 0.0 && event.lon != 0.0)
          .toList();

      _log(" Parsed ${rawEvents.length} valid events");

      _logConsensus("");
      _logConsensus(" EVENT TIMESTAMPS DEBUG:");
      for (var i = 0; i < rawEvents.length; i++) {
        final event = rawEvents[i];
        _logConsensus(
            "  Event $i: ${event.type} at ${event.timestamp} (${event.lat.toStringAsFixed(6)}, ${event.lon.toStringAsFixed(6)}) - Conf: ${(event.confidence ?? 0) * 100}%");
      }
      _logConsensus("");

      final List<EventModel> consensusEvents =
          _applyEnhancedConsensusFiltering(rawEvents);

      _log(
          " ${rawEvents.length} raw  ${consensusEvents.length} after consensus");

      _cachedEvents = consensusEvents;
      _lastFetchTime = DateTime.now();

      return consensusEvents;
    } on TimeoutException catch (e) {
      _log(" Timeout error: $e");
      return _cachedEvents ?? [];
    } on FormatException catch (e) {
      _log(" JSON parsing error: $e");
      return _cachedEvents ?? [];
    } catch (e, stackTrace) {
      _log(" Fetch error: $e");
      _log("Stack trace: $stackTrace");
      return _cachedEvents ?? [];
    }
  }

  List<EventModel> _applyEnhancedConsensusFiltering(List<EventModel> events) {
    _logConsensus("");
    _logConsensus(" CONSENSUS FILTERING DEBUG");
    _logConsensus("");
    _logConsensus("Settings:");
    _logConsensus("  - Radius: ${consensusRadiusMeters}m");
    _logConsensus("  - Min Count: $minConsensusCount");
    _logConsensus("  - Time Window: ${consensusTimeWindow.inMinutes} minutes");
    _logConsensus("  - Input Events: ${events.length}");
    _logConsensus("");

    // Filter out stale events first
    int staleCount = 0;
    final recentEvents = events.where((e) {
      final isRecent = e.isRecentEvent;
      if (!isRecent) {
        staleCount++;
        if (debugConsensusDetails) {
          debugPrint(" Rejected (stale): ${e.type} at ${e.timestamp}");
        }
      }
      return isRecent;
    }).toList();

    _log(
        " Recent events: ${recentEvents.length}/${events.length} (stale: $staleCount)");

    // If backend sends older historical/demo timestamps, keep showing events
    // instead of returning an empty map.
    final eventsForConsensus = recentEvents.isEmpty ? events : recentEvents;
    if (recentEvents.isEmpty && events.isNotEmpty) {
      _log(" No recent events by timestamp; using all events as fallback");
    }

    if (eventsForConsensus.isEmpty) return [];

    final validatedEvents = <EventModel>[];
    final processedIndices = <int>{};

    for (int i = 0; i < eventsForConsensus.length; i++) {
      if (processedIndices.contains(i)) continue;

      final event = eventsForConsensus[i];
      final nearbyEvents = <EventModel>[event];

      _logConsensus("\n Processing event #$i:");
      _logConsensus("  Type: ${event.type}");
      _logConsensus(
          "  Location: ${event.lat.toStringAsFixed(6)}, ${event.lon.toStringAsFixed(6)}");
      _logConsensus("  Timestamp: ${event.timestamp}");
      _logConsensus("  Confidence: ${(event.confidence ?? 0) * 100}%");

      for (int j = i + 1; j < eventsForConsensus.length; j++) {
        if (processedIndices.contains(j)) continue;

        final otherEvent = eventsForConsensus[j];

        final distance = _calculateDistance(
          event.lat,
          event.lon,
          otherEvent.lat,
          otherEvent.lon,
        );

        final sameType =
            event.type.toLowerCase() == otherEvent.type.toLowerCase();

        bool withinTimeWindow = false;
        String timeInfo = "N/A";
        if (event.timestamp != null && otherEvent.timestamp != null) {
          final timeDiff =
              (event.timestamp!.difference(otherEvent.timestamp!)).abs();
          withinTimeWindow = timeDiff <= consensusTimeWindow;
          timeInfo = "${timeDiff.inMinutes}min ${timeDiff.inSeconds % 60}sec";
        } else {
          // For legacy rows that have no timestamp, fall back to spatial/type consensus.
          withinTimeWindow = true;
          timeInfo = "Missing timestamp (time check bypassed)";
          _log(
              "     Missing timestamp - bypassing time window check for legacy data");
        }

        _logConsensus("   Comparing with event #$j:");
        _logConsensus(
            "    Distance: ${distance.toStringAsFixed(1)}m (limit: ${consensusRadiusMeters}m) ${distance <= consensusRadiusMeters ? '' : ''}");
        _logConsensus(
            "    Type match: ${otherEvent.type} ${sameType ? '' : ''}");
        _logConsensus("    Time diff: $timeInfo ${withinTimeWindow ? '' : ''}");

        if (distance <= consensusRadiusMeters && sameType && withinTimeWindow) {
          nearbyEvents.add(otherEvent);
          processedIndices.add(j);
          _logConsensus("     MATCHED - Added to consensus group");
        } else {
          _logConsensus("     NOT MATCHED");
        }
      }

      _logConsensus("   Consensus group size: ${nearbyEvents.length}");

      if (nearbyEvents.length >= minConsensusCount) {
        double totalWeight = 0.0;
        double weightedLat = 0.0;
        double weightedLon = 0.0;
        double avgConfidence = 0.0;

        for (var e in nearbyEvents) {
          final weight = e.confidence ?? 0.5;
          totalWeight += weight;
          weightedLat += e.lat * weight;
          weightedLon += e.lon * weight;
          avgConfidence += (e.confidence ?? 0.5);
        }

        if (totalWeight > 0) {
          weightedLat /= totalWeight;
          weightedLon /= totalWeight;
        } else {
          weightedLat = nearbyEvents.map((e) => e.lat).reduce((a, b) => a + b) /
              nearbyEvents.length;
          weightedLon = nearbyEvents.map((e) => e.lon).reduce((a, b) => a + b) /
              nearbyEvents.length;
        }

        avgConfidence /= nearbyEvents.length;

        final consensusBoost = min(nearbyEvents.length / 10.0, 0.2);
        final finalConfidence = min(avgConfidence + consensusBoost, 1.0);

        validatedEvents.add(EventModel(
          lat: weightedLat,
          lon: weightedLon,
          type: event.type,
          confidence: finalConfidence,
          device: event.device,
          timestamp: event.timestamp,
          consensusCount: nearbyEvents.length,
        ));

        _log("   CONSENSUS VALIDATED: ${event.type}");
        _log("    Reports: ${nearbyEvents.length}");
        _log(
            "    Final Confidence: ${(finalConfidence * 100).toStringAsFixed(0)}%");
      } else {
        _logConsensus("   Checking single-report criteria...");
        if ((event.confidence ?? 0.0) >= 0.65) {
          validatedEvents.add(event);
          _logConsensus("   HIGH-CONFIDENCE SINGLE REPORT ACCEPTED");
          _logConsensus(
              "    Confidence: ${((event.confidence ?? 0) * 100).toStringAsFixed(0)}%");
        } else {
          _logConsensus(
              "   REJECTED: Low consensus (${nearbyEvents.length} reports) and low confidence (${((event.confidence ?? 0) * 100).toStringAsFixed(0)}%)");
        }
      }

      processedIndices.add(i);
    }

    validatedEvents.sort((a, b) => b.trustScore.compareTo(a.trustScore));

    _log(" FINAL RESULT: ${validatedEvents.length} events validated");

    return validatedEvents;
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * pi / 180;
  }

  void clearCache() {
    _cachedEvents = null;
    _lastFetchTime = null;
    debugPrint(" Event cache cleared");
  }

  Future<List<EventModel>> fetchEventsByType(String type,
      {bool forceRefresh = false}) async {
    final allEvents = await fetchEvents(forceRefresh: forceRefresh);
    return allEvents
        .where((e) => e.type.toLowerCase() == type.toLowerCase())
        .toList();
  }

  Future<List<EventModel>> fetchEventsNearby({
    required LatLng center,
    required double radiusMeters,
    bool forceRefresh = false,
  }) async {
    final allEvents = await fetchEvents(forceRefresh: forceRefresh);
    return allEvents.where((event) {
      final distance = _calculateDistance(
        center.latitude,
        center.longitude,
        event.lat,
        event.lon,
      );
      return distance <= radiusMeters;
    }).toList();
  }

  Future<Map<String, dynamic>> getEventStatistics(
      {bool forceRefresh = false}) async {
    final events = await fetchEvents(forceRefresh: forceRefresh);

    final potholes =
        events.where((e) => e.type.toLowerCase() == 'pothole').length;
    final speedBumps =
        events.where((e) => e.type.toLowerCase() == 'speed bump').length;

    final highConfidence = events.where((e) => e.isHighConfidence).length;
    final withConsensus = events
        .where((e) => (e.consensusCount ?? 0) >= minConsensusCount)
        .length;

    final avgConfidence = events.isEmpty
        ? 0.0
        : events.map((e) => e.confidence ?? 0.0).reduce((a, b) => a + b) /
            events.length;

    return {
      'totalEvents': events.length,
      'potholes': potholes,
      'speedBumps': speedBumps,
      'highConfidence': highConfidence,
      'withConsensus': withConsensus,
      'averageConfidence': avgConfidence,
      'cacheAge': _lastFetchTime != null
          ? DateTime.now().difference(_lastFetchTime!).inSeconds
          : null,
    };
  }

  static void updateConsensusParams({
    double? radius,
    int? minCount,
    Duration? timeWindow,
  }) {
    if (radius != null) consensusRadiusMeters = radius;
    if (minCount != null) minConsensusCount = minCount;
    if (timeWindow != null) consensusTimeWindow = timeWindow;

    debugPrint(" Consensus params updated: "
        "radius=${consensusRadiusMeters.toStringAsFixed(1)}m, "
        "minCount=$minConsensusCount, "
        "timeWindow=${consensusTimeWindow.inMinutes}min");
  }
}
