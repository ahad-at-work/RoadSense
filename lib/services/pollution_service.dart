import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pollution_model.dart';
import '../utils/pollution_constants.dart';

class PollutionService extends ChangeNotifier {
  //  Use the same API key as your other Google services
  static const String apiKey = 'AIzaSyAmr6QANQ42SFt-o5XyVN0jlYlmuMV_dgQ';
  static const String baseUrl = 'https://airquality.googleapis.com/v1/currentConditions:lookup';

  // Current pollution data
  PollutionData? _currentPollution;
  PollutionData? get currentPollution => _currentPollution;

  // Loading and error states
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // Cache management
  final Map<String, PollutionData> _cache = {};
  LatLng? _lastFetchLocation;
  DateTime? _lastFetchTime;
  DateTime? _lastAlertTime;

  // User settings
  PollutionAlertSettings _alertSettings = PollutionAlertSettings();
  PollutionAlertSettings get alertSettings => _alertSettings;

  PollutionService() {
    _loadAlertSettings();
  }

  /// Fetch air quality data for given coordinates
  Future<void> fetchAirQuality(double lat, double lon) async {
    // Check cache first
    final cachedData = _getCachedData(lat, lon);
    if (cachedData != null && !cachedData.isExpired()) {
      _currentPollution = cachedData;
      notifyListeners();
      debugPrint(" Using cached pollution data (age: ${PollutionFormatters.getTimeAgo(cachedData.timestamp)})");
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'location': {
            'latitude': lat,
            'longitude': lon,
          },
          // Request additional data
          'extraComputations': [
            'HEALTH_RECOMMENDATIONS',
            'DOMINANT_POLLUTANT_CONCENTRATION',
            'POLLUTANT_CONCENTRATION',
            'LOCAL_AQI',
          ],
          'languageCode': 'en',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pollutionData = PollutionData.fromJson(data, lat, lon);
        
        _currentPollution = pollutionData;
        _cacheData(lat, lon, pollutionData);
        _lastFetchLocation = LatLng(lat, lon);
        _lastFetchTime = DateTime.now();
        
        debugPrint(" Pollution data fetched: AQI ${pollutionData.aqi} (${pollutionData.category})");
        debugPrint("    Location: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}");
        debugPrint("    Dominant: ${pollutionData.dominantPollutant}");
        
        // Check if alert should be triggered
        _checkAndTriggerAlert(pollutionData);
        
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      } else {
        throw Exception('API returned status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      debugPrint(" Failed to fetch pollution data: $e");
      notifyListeners();
    }
  }

  /// Smart update: fetch only if moved significantly or time elapsed
  Future<void> smartUpdate(double lat, double lon) async {
    // Check if we should update
    if (!_shouldUpdate(lat, lon)) {
      debugPrint(" Skipping pollution update (within thresholds)");
      return;
    }

    await fetchAirQuality(lat, lon);
  }

  /// Determine if update is needed
  bool _shouldUpdate(double lat, double lon) {
    // Always update if no data
    if (_currentPollution == null || _lastFetchLocation == null) {
      return true;
    }

    // Check if data is expired
    if (_currentPollution!.isExpired()) {
      debugPrint(" Pollution data expired, updating...");
      return true;
    }

    // Check if moved significantly
    final distance = _calculateDistance(
      _lastFetchLocation!.latitude,
      _lastFetchLocation!.longitude,
      lat,
      lon,
    );

    if (distance > PollutionConfig.significantMoveDistanceMeters) {
      debugPrint(" Moved ${(distance / 1000).toStringAsFixed(1)}km, updating pollution data...");
      return true;
    }

    // Check if enough time has passed
    final timeSinceLastFetch = DateTime.now().difference(_lastFetchTime!);
    if (timeSinceLastFetch > PollutionConfig.updateInterval) {
      debugPrint(" 15 minutes elapsed, updating pollution data...");
      return true;
    }

    return false;
  }

  ///  FIXED: Calculate distance between two coordinates (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    
    // Convert to radians
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double lat1Rad = _toRadians(lat1);
    final double lat2Rad = _toRadians(lat2);
    
    // Haversine formula
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
                     math.cos(lat1Rad) * math.cos(lat2Rad) *
                     math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = earthRadius * c;
    
    return distance;
  }

  double _toRadians(double degrees) {
    return degrees * math.pi / 180;
  }

  /// Cache management
  void _cacheData(double lat, double lon, PollutionData data) {
    final key = _getCacheKey(lat, lon);
    _cache[key] = data;
    
    // Limit cache size
    if (_cache.length > PollutionConfig.maxCacheSize) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    
    debugPrint(" Cached pollution data (cache size: ${_cache.length})");
  }

  PollutionData? _getCachedData(double lat, double lon) {
    final key = _getCacheKey(lat, lon);
    return _cache[key];
  }

  String _getCacheKey(double lat, double lon) {
    // Round to 2 decimal places for cache key (~1km precision)
    return '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
  }

  void clearCache() {
    _cache.clear();
    debugPrint(" Pollution cache cleared");
    notifyListeners();
  }

  /// Alert management
  Future<void> _loadAlertSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('pollution_alert_settings');
      
      if (settingsJson != null) {
        final map = jsonDecode(settingsJson) as Map<String, dynamic>;
        _alertSettings = PollutionAlertSettings.fromJson(map);
        debugPrint(" Loaded pollution alert settings: threshold=${_alertSettings.aqiThreshold}");
      }
    } catch (e) {
      debugPrint(" Failed to load alert settings: $e");
    }
  }

  Future<void> updateAlertSettings(PollutionAlertSettings settings) async {
    _alertSettings = settings;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pollution_alert_settings', jsonEncode(settings.toJson()));
      debugPrint(" Saved pollution alert settings");
    } catch (e) {
      debugPrint(" Failed to save alert settings: $e");
    }
    
    notifyListeners();
  }

  void _checkAndTriggerAlert(PollutionData data) {
    if (!_alertSettings.enabled) return;

    // Check cooldown
    if (_lastAlertTime != null) {
      final timeSinceLastAlert = DateTime.now().difference(_lastAlertTime!);
      if (timeSinceLastAlert < PollutionConfig.alertCooldown) {
        return;
      }
    }

    // Check if AQI exceeds threshold
    if (data.exceedsThreshold(_alertSettings.aqiThreshold)) {
      _lastAlertTime = DateTime.now();
      debugPrint(" POLLUTION ALERT: AQI ${data.aqi} exceeds threshold ${_alertSettings.aqiThreshold}");
      // The UI will listen to this change and show the alert
    }
  }

  /// Check if current pollution exceeds user's threshold
  bool hasActiveAlert() {
    if (_currentPollution == null || !_alertSettings.enabled) return false;
    return _currentPollution!.exceedsThreshold(_alertSettings.aqiThreshold);
  }

  /// Get status text
  String getStatusText() {
    if (_isLoading) return 'Loading air quality data...';
    if (_errorMessage != null) return 'Failed to load pollution data';
    if (_currentPollution == null) return 'No pollution data';
    
    final age = PollutionFormatters.getTimeAgo(_currentPollution!.timestamp);
    return 'Updated $age';
  }

  /// Clear current data
  void clearCurrentData() {
    _currentPollution = null;
    _errorMessage = null;
    notifyListeners();
    debugPrint(" Cleared current pollution data");
  }

  /// Retry last failed request
  Future<void> retry() async {
    if (_lastFetchLocation != null) {
      await fetchAirQuality(
        _lastFetchLocation!.latitude,
        _lastFetchLocation!.longitude,
      );
    }
  }

  @override
  void dispose() {
    _cache.clear();
    debugPrint(" PollutionService disposed");
    super.dispose();
  }
}
