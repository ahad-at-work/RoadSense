import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_execution_service.dart';
import 'trip_logger_service.dart';

class LocationService extends ChangeNotifier {
  static const String backgroundLastLatKey = 'bg_last_known_lat';
  static const String backgroundLastLonKey = 'bg_last_known_lon';
  static const String backgroundLastUpdatedAtKey = 'bg_last_known_updated_at';

  Position? _currentLocation;
  Position? get currentLocation => _currentLocation;

  StreamSubscription<Position>? _positionStream;
  final StreamController<Position> _locationUpdatesController =
      StreamController<Position>.broadcast();
  bool _isTracking = false;
  String _locationStatus = 'Initializing...';
  bool _hasRetriedWithoutForegroundService = false;
  DateTime? _lastLocationLogAt;
  DateTime? _lastPersistedLocationAt;
  DateTime? _lastLocationNotifyAt;

  //  UI-friendly location stream configuration
  Stream<Position> _buildLocationStream({
    required bool useForegroundNotification,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        // Balanced accuracy for map updates and location monitoring
        accuracy: LocationAccuracy.high,

        // Notify only on meaningful movement to avoid overloading the app.
        distanceFilter: 10,

        forceLocationManager: false,

        // Reduced frequency eases UI updates and battery usage.
        intervalDuration: const Duration(seconds: 1),

        foregroundNotificationConfig: useForegroundNotification
            ? const ForegroundNotificationConfig(
                notificationText: "RoadSense is tracking your location",
                notificationTitle: "Location Tracking Active",
                enableWakeLock: true,
              )
            : null,
      ),
    );
  }

  Stream<Position> get locationUpdates {
    return _locationUpdatesController.stream;
  }

  LocationService() {
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      _locationStatus = 'Checking location services...';
      notifyListeners();

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _locationStatus = 'Location services are disabled';
        notifyListeners();
        return;
      }

      _locationStatus = 'Checking location permission...';
      notifyListeners();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        _locationStatus = 'Location permission is needed to show your position';
        notifyListeners();
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _locationStatus =
            'Location permission is permanently denied. Open app settings to enable it.';
        notifyListeners();
        return;
      }

      _locationStatus = 'Restoring last known location...';
      notifyListeners();

      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final now = DateTime.now();
        final age = now.difference(lastKnown.timestamp).inSeconds;
        if (age <= 120) {
          _currentLocation = lastKnown;
          _locationStatus = 'Using cached location ($age seconds old)';
          notifyListeners();
          debugPrint(
              " Restored cached location: ${lastKnown.latitude.toStringAsFixed(6)}, ${lastKnown.longitude.toStringAsFixed(6)} (age: ${age}s)");
          return;
        }
      }

      _locationStatus = 'Getting initial location...';
      notifyListeners();

      _currentLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _locationStatus = 'Location ready';
      notifyListeners();

      debugPrint(
          " Initial location: ${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}");
    } catch (e) {
      _locationStatus = 'Error: $e';
      notifyListeners();
      debugPrint(' Error initializing location: $e');
    }
  }

  Future<void> refreshLocation() async {
    try {
      _locationStatus = 'Refreshing location...';
      notifyListeners();

      _currentLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      _locationStatus = 'Location refreshed';
      notifyListeners();

      debugPrint(
          " Refreshed location: ${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}");
    } catch (e) {
      _locationStatus = 'Refresh failed: $e';
      notifyListeners();
      debugPrint(' Error refreshing location: $e');
    }
  }

  Future<Position?> getFreshLocation() async {
    try {
      _locationStatus = 'Getting fresh location...';
      notifyListeners();

      final freshLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      _currentLocation = freshLocation;
      _locationStatus = 'Fresh location acquired';
      notifyListeners();

      debugPrint(
          " Fresh location: ${freshLocation.latitude.toStringAsFixed(6)}, ${freshLocation.longitude.toStringAsFixed(6)}");
      return freshLocation;
    } catch (e) {
      _locationStatus = 'Fresh location failed: $e';
      notifyListeners();
      debugPrint(' Error getting fresh location: $e');
      return null;
    }
  }

  bool isLocationFresh() {
    if (_currentLocation == null) return false;
    final now = DateTime.now();
    final locationTime = _currentLocation!.timestamp;
    final age = now.difference(locationTime).inSeconds;

    return age < 5;
  }

  int get locationAge {
    if (_currentLocation == null) return -1;
    final now = DateTime.now();
    return now.difference(_currentLocation!.timestamp).inSeconds;
  }

  bool _shouldNotifyListeners(Position position) {
    final now = DateTime.now();
    if (_lastLocationNotifyAt == null) {
      _lastLocationNotifyAt = now;
      return true;
    }

    if (now.difference(_lastLocationNotifyAt!).inMilliseconds >= 500) {
      _lastLocationNotifyAt = now;
      return true;
    }

    return false;
  }

  void startContinuousTracking() {
    if (_isTracking) {
      final age = _currentLocation == null ? 'unknown' : '${locationAge}s';
      debugPrint(
          " Continuous tracking already active - current location age: $age");
      return;
    }

    _lastLocationNotifyAt = null;

    try {
      _locationStatus = 'Starting continuous tracking...';
      _hasRetriedWithoutForegroundService = false;

      void subscribe({required bool useForegroundNotification}) {
        _positionStream?.cancel();
        _positionStream = _buildLocationStream(
          useForegroundNotification: useForegroundNotification,
        ).listen(
          (Position position) {
            _currentLocation = position;
            _isTracking = true;
            if (!_locationUpdatesController.isClosed) {
              _locationUpdatesController.add(position);
            }

            // Keep trip coordinate logging tied to the core location stream,
            // so logging continues even when map UI listeners are inactive.
            unawaited(TripLoggerService.logPosition(position));

            final now = DateTime.now();
            if (_lastPersistedLocationAt == null ||
                now.difference(_lastPersistedLocationAt!) >=
                    const Duration(seconds: 5)) {
              _lastPersistedLocationAt = now;
              unawaited(_persistLastKnownLocation(position));
            }

            _locationStatus =
                'Tracking active - Speed: ${(position.speed * 3.6).toStringAsFixed(1)} km/h';
            if (_shouldNotifyListeners(position)) {
              notifyListeners();
            }

            if (_lastLocationLogAt == null ||
                now.difference(_lastLocationLogAt!) >=
                    const Duration(seconds: 1)) {
              _lastLocationLogAt = now;
              final speedKmh = position.speed * 3.6;
              debugPrint(
                  " Location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)} | Speed: ${speedKmh.toStringAsFixed(1)} km/h | Accuracy: ${position.accuracy.toStringAsFixed(1)}m | Heading: ${position.heading.toStringAsFixed(0)}");
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _locationStatus = 'Tracking error: $error';
            _isTracking = false;
            notifyListeners();
            debugPrint(' Location stream error: $error');

            if (useForegroundNotification &&
                !_hasRetriedWithoutForegroundService) {
              _hasRetriedWithoutForegroundService = true;
              debugPrint(
                  ' Retrying location stream without foreground notification config');
              Future.microtask(() {
                subscribe(useForegroundNotification: false);
              });
            }
          },
        );

        _isTracking = true;
        _locationStatus = 'Continuous tracking active';
        Future.microtask(() => notifyListeners());
      }

      subscribe(useForegroundNotification: true);

      debugPrint(
          " Started HIGH-FREQUENCY location tracking (500ms intervals, 3m distance filter)");
      debugPrint(" Optimized for bike/vehicle speeds up to 100+ km/h");
    } catch (e) {
      _locationStatus = 'Failed to start tracking: $e';
      Future.microtask(() => notifyListeners());
      debugPrint(' Error starting continuous tracking: $e');
    }
  }

  Future<void> startContinuousTrackingWithBackgroundSupport() async {
    final permission = await checkPermissions();
    if (permission == LocationPermission.denied) {
      final requested = await requestPermissions();
      if (requested == LocationPermission.denied) {
        _locationStatus = 'Location permission denied. Tracking cannot start.';
        notifyListeners();
        return;
      }
      if (requested == LocationPermission.deniedForever) {
        _locationStatus =
            'Location permission permanently denied. Open app settings to enable it.';
        notifyListeners();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _locationStatus =
          'Location permission permanently denied. Open app settings to enable it.';
      notifyListeners();
      return;
    }

    final preparationResult =
        await BackgroundExecutionService.ensureReadyForRoadMonitoring();

    if (!preparationResult.canStart) {
      debugPrint(
        ' Background-ready tracking blocked: ${preparationResult.userMessage}',
      );
      if (preparationResult.userMessage != null) {
        _locationStatus = preparationResult.userMessage!;
        notifyListeners();
      }
      return;
    }

    startContinuousTracking();
  }

  void stopContinuousTracking() {
    _positionStream?.cancel();
    _isTracking = false;
    _locationStatus = 'Tracking stopped';
    _hasRetriedWithoutForegroundService = false;
    notifyListeners();

    debugPrint(" Stopped continuous location tracking");
  }

  double? get speedKmh {
    if (_currentLocation?.speed == null) return null;
    return _currentLocation!.speed * 3.6;
  }

  double? get speedMs => _currentLocation?.speed;
  double? get accuracy => _currentLocation?.accuracy;
  double? get heading => _currentLocation?.heading;
  double? get altitude => _currentLocation?.altitude;
  String get status => _locationStatus;
  bool get isTracking => _isTracking;
  bool get hasLocation => _currentLocation != null;

  LatLng? get latLng {
    if (_currentLocation == null) return null;
    return LatLng(_currentLocation!.latitude, _currentLocation!.longitude);
  }

  String get formattedLocation {
    if (_currentLocation == null) return 'No location';
    return '${_currentLocation!.latitude.toStringAsFixed(6)}, ${_currentLocation!.longitude.toStringAsFixed(6)}';
  }

  String get formattedSpeed {
    if (speedKmh == null) return 'N/A';
    return '${speedKmh!.toStringAsFixed(1)} km/h';
  }

  double? distanceTo(double lat, double lng) {
    if (_currentLocation == null) return null;

    return Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      lat,
      lng,
    );
  }

  Future<bool> checkLocationServices() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  Future<LocationPermission> checkPermissions() async {
    return await Geolocator.checkPermission();
  }

  Future<LocationPermission> requestPermissions() async {
    return await Geolocator.requestPermission();
  }

  static Future<Map<String, double>?>
      getLastKnownCoordinateForBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(backgroundLastLatKey);
    final lon = prefs.getDouble(backgroundLastLonKey);
    if (lat == null || lon == null) {
      return null;
    }

    return {
      'lat': lat,
      'lon': lon,
    };
  }

  Future<void> _persistLastKnownLocation(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(backgroundLastLatKey, position.latitude);
      await prefs.setDouble(backgroundLastLonKey, position.longitude);
      await prefs.setString(
        backgroundLastUpdatedAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (error) {
      debugPrint(' Failed to persist last known location: $error');
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _locationUpdatesController.close();
    debugPrint(" LocationService disposed");
    super.dispose();
  }
}
